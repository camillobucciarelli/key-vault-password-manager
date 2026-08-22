import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

/// Every unique-name attempt collided (spec 008 T108). Defined behaviour for
/// suffix exhaustion: nothing was written or overwritten; the caller's target
/// file is untouched.
class SafeVaultNameCollisionException implements Exception {
  const SafeVaultNameCollisionException(this.attempts);

  final int attempts;

  @override
  String toString() =>
      'SafeVaultNameCollisionException: could not claim a fresh file name '
      'after $attempts exclusive-create attempts';
}

/// Filesystem seam for the safe writer. Production uses this default; T110
/// failure tests subclass it to inject faults at every phase. The methods are
/// exactly the operations the writer performs — nothing else touches the disk.
class SafeVaultFileIo {
  const SafeVaultFileIo();

  Future<bool> exists(String path) => File(path).exists();

  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  /// Claims [path] atomically; throws [FileSystemException] if it exists.
  /// This is the no-overwrite guarantee for temp AND final backup names.
  Future<void> createExclusive(String path) async {
    await File(path).create(exclusive: true);
  }

  Future<RandomAccessFile> openWrite(String path) =>
      File(path).open(mode: FileMode.writeOnly);

  Future<void> writeFull(RandomAccessFile file, Uint8List bytes) async {
    await file.writeFrom(bytes);
  }

  /// `RandomAccessFile.flush` is the only fsync Dart exposes.
  Future<void> flush(RandomAccessFile file) => file.flush();

  Future<void> close(RandomAccessFile file) => file.close();

  /// Atomic replace. POSIX `rename(2)`/Win32 `ReplaceFile` semantics: the
  /// target is either its old content or the full new content, never a mix.
  /// No delete-first anywhere in the writer.
  Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }

  Future<void> delete(String path) async {
    await File(path).delete();
  }

  /// Follows a symlink AT THE LEAF of [path] and returns what it points at.
  /// Returns [path] unchanged when it is not a link, or when the link is
  /// dangling/unresolvable — see [SafeVaultFileWriter.write] for why that
  /// fallback is the safe direction.
  String resolveLeafLink(String path) {
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.link) {
        return path;
      }
      return File(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return path;
    }
  }

  /// POSIX permission bits of [path], or `null` when they are not meaningful
  /// or not readable: Windows (no POSIX mode), or a missing file.
  Future<int?> permissionBits(String path) async {
    if (Platform.isWindows) {
      return null;
    }
    final stat = await FileStat.stat(path);
    if (stat.type == FileSystemEntityType.notFound) {
      return null;
    }
    return stat.mode & 0xFFF;
  }

  /// Applies [bits] to [path]. No-op on Windows, which has no POSIX mode.
  ///
  /// Dart exposes no `chmod`, so this shells out. Callers treat a failure as
  /// non-fatal — see [SafeVaultFileWriter.write].
  Future<void> setPermissionBits(String path, int bits) async {
    if (Platform.isWindows) {
      return;
    }
    final octal = bits.toRadixString(8).padLeft(4, '0');
    final result = await Process.run('chmod', [octal, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $octal failed: ${result.stderr}', path);
    }
  }

  /// Best-effort directory sync after the replace. Dart has no portable
  /// directory-fsync API; opening a directory as a [File] throws on most
  /// platforms, so this succeeds only where the runtime supports it. Failure
  /// is swallowed by the writer: the data fsync already happened on the file.
  Future<void> syncDirectory(String path) async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open(mode: FileMode.read);
      await raf.flush();
    } finally {
      await raf?.close();
    }
  }
}

class SafeVaultFileWriteResult {
  const SafeVaultFileWriteResult({
    required this.targetPath,
    this.backupPath,
    this.atomic = true,
  });

  /// The path the caller asked for — NOT the symlink-resolved one, so a
  /// caller that handed over `~/vault.kdbx -> ~/Dropbox/vault.kdbx` gets its
  /// own spelling back.
  final String targetPath;

  /// Verified backup of the pre-write target, when one was requested.
  final String? backupPath;

  /// `false` when the sandbox fallback ran: content is complete and verified,
  /// but it was written in place rather than atomically renamed.
  final bool atomic;
}

/// spec 008 T108/T109 — collision-safe backup + safe target writer.
///
/// Lock-free by design: callers are the T105-routed writers and invoke this
/// INSIDE their existing `DatabasePathMutex.withDatabaseLock` action (the
/// mutex is not reentrant, so this helper must never acquire it).
///
/// Guarantees, enforced by `safe_vault_file_writer_test.dart` (T110):
/// - the target is always either its old content or the full new content;
/// - a backup file is never overwritten (exclusive-create, microsecond
///   timestamp + random suffix, bounded retry, then a defined failure);
/// - the backup is written, flushed and read-back verified BEFORE the target
///   is touched;
/// - the replace is a same-directory rename — atomic, no delete-first;
/// - the target's POSIX permission bits survive the replace (T109 HIGH-1);
/// - a symlinked target is written THROUGH, not replaced (T109 HIGH-2).
class SafeVaultFileWriter {
  SafeVaultFileWriter({
    SafeVaultFileIo io = const SafeVaultFileIo(),
    DateTime Function()? clock,
    Random? random,
  }) : _io = io,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final SafeVaultFileIo _io;
  final DateTime Function() _clock;
  final Random _random;

  /// Bound on exclusive-create attempts per name (backup or temp). Each
  /// attempt uses a fresh random suffix; exhaustion throws
  /// [SafeVaultNameCollisionException] with nothing written.
  static const maxNameAttempts = 32;

  /// Permission bits for a `.kdbx` we are creating from scratch. A vault is
  /// owner-only by default; `0666 & ~umask` (what the OS gives a fresh file)
  /// is typically world-readable, which is what HIGH-1 reported.
  static const defaultVaultMode = 0x180; // 0600

  /// T108: collision-safe, verified backup of [targetPath].
  ///
  /// Name shape: `<target>.<microsecondsSinceEpoch>-<random>.bak`, claimed
  /// with exclusive-create so a frozen clock, a preexisting file or a
  /// concurrent backup can only force a retry with a new suffix — never an
  /// overwrite. The permission bits of [targetPath] are applied to the backup
  /// BEFORE any content is written, so a `0600` vault never has a
  /// world-readable copy on disk, not even briefly. Content is written,
  /// flushed (fsync) and read-back verified; a failed verify removes the
  /// partial backup and rethrows.
  Future<String> createBackup(String targetPath) async {
    final resolved = _io.resolveLeafLink(targetPath);
    final mode = await _io.permissionBits(resolved);
    final source = await _io.readBytes(resolved);
    final backupPath = await _claimFreshName(
      (micros, suffix) => '$resolved.$micros-$suffix.bak',
      mode: mode,
    );
    try {
      await _writeVerified(backupPath, source);
    } catch (_) {
      await _bestEffortDelete(backupPath);
      rethrow;
    }
    return backupPath;
  }

  /// T109: safe write of [bytes] to [targetPath].
  ///
  /// Order: resolve a symlinked target, optional verified backup of the
  /// existing target FIRST (any backup failure aborts with the target
  /// untouched), then an exclusive-created temp in the SAME directory as the
  /// resolved target, permission bits applied before content, full write,
  /// fsync, close, read-back verify, atomic rename over the target and a
  /// best-effort directory sync. Any failure before the rename leaves the
  /// old target intact (temp removed best-effort); the rename itself is
  /// atomic, so the target is never truncated or mixed.
  ///
  /// **Symlink handling (HIGH-2).** A leaf symlink is resolved first, so
  /// `~/vault.kdbx -> ~/Dropbox/vault.kdbx` is written THROUGH: the link
  /// survives and the cloud-synced file really changes. Without this,
  /// `rename(2)` would replace the link entry itself and silently freeze the
  /// real file forever. A **dangling** link is deliberately NOT resolved: the
  /// rename then replaces the entry, which is the safe direction for the
  /// attacker-plantable case (#45/#46) — a dangling link cannot be a
  /// legitimate cloud target, since there is nothing on the other end.
  ///
  /// **Sandbox fallback (HIGH-3).** Under the macOS app sandbox the
  /// `files.user-selected.read-write` entitlement authorizes the chosen PATH,
  /// not its directory, so creating a sibling temp can fail with
  /// `Operation not permitted` where a direct write succeeds. The same shape
  /// exists for Android SAF and the iOS document picker. When the temp cannot
  /// be created for a permission reason, this falls back to writing the
  /// authorized path in place (pre-slice behaviour) and logs the degradation.
  /// **Trade-off: the fallback is NOT atomic** — a crash mid-write can leave
  /// a truncated target. It is chosen over failing the save outright because
  /// the backup (when requested) still exists and losing the ability to save
  /// at all is the worse outcome. [SafeVaultFileWriteResult.atomic] reports
  /// which path ran.
  Future<SafeVaultFileWriteResult> write({
    required String targetPath,
    required Uint8List bytes,
    bool backupExistingTarget = false,
  }) async {
    final resolved = _io.resolveLeafLink(targetPath);

    String? backupPath;
    if (backupExistingTarget && await _io.exists(resolved)) {
      backupPath = await createBackup(resolved);
    }

    // Mode of the file we are about to replace; absent target -> owner-only.
    final existingMode = await _io.permissionBits(resolved);
    final mode = existingMode ?? (Platform.isWindows ? null : defaultVaultMode);

    final directory = p.dirname(resolved);
    final name = p.basename(resolved);

    String tempPath;
    try {
      tempPath = await _claimFreshName(
        (micros, suffix) =>
            p.join(directory, '.$name.safe-$micros-$suffix.tmp'),
        mode: mode,
      );
    } on FileSystemException catch (error) {
      if (!_isPermissionDenied(error)) {
        rethrow;
      }
      logWarning(
        'Safe writer degraded to a non-atomic in-place write: the sandbox '
        'refused a sibling temp file in $directory ($error). The target is '
        'still fully written and verified, but a crash mid-write can '
        'truncate it.',
      );
      // Create-then-chmod-then-write, so a brand-new target is owner-only
      // before it holds any bytes.
      if (!await _io.exists(resolved)) {
        await _io.createExclusive(resolved);
      }
      await _applyMode(resolved, mode);
      await _writeVerified(resolved, bytes);
      return SafeVaultFileWriteResult(
        targetPath: targetPath,
        backupPath: backupPath,
        atomic: false,
      );
    }

    try {
      await _writeVerified(tempPath, bytes);
      await _io.rename(tempPath, resolved);
    } catch (_) {
      await _bestEffortDelete(tempPath);
      rethrow;
    }

    try {
      await _io.syncDirectory(directory);
    } catch (_) {
      // Best-effort only: the new target is complete and fsynced.
    }
    return SafeVaultFileWriteResult(
      targetPath: targetPath,
      backupPath: backupPath,
    );
  }

  Future<String> _claimFreshName(
    String Function(int micros, String suffix) build, {
    required int? mode,
  }) async {
    for (var attempt = 0; attempt < maxNameAttempts; attempt++) {
      final suffix = _random
          .nextInt(0x100000)
          .toRadixString(16)
          .padLeft(5, '0');
      final candidate = build(_clock().microsecondsSinceEpoch, suffix);
      try {
        await _io.createExclusive(candidate);
      } on FileSystemException catch (error) {
        if (_isAlreadyExists(error)) {
          // Name taken — never overwrite, retry with a new suffix.
          continue;
        }
        // Anything else (notably a sandbox permission refusal) is NOT a
        // collision; retrying 32 times would mask it as one.
        rethrow;
      }
      // Applied before any content exists, so the file is never readable by
      // anyone the target was not already readable by.
      await _applyMode(candidate, mode);
      return candidate;
    }
    throw const SafeVaultNameCollisionException(maxNameAttempts);
  }

  /// chmod failure is logged, never fatal: a filesystem with no POSIX modes
  /// (exFAT, FAT32, some network mounts) would otherwise make saving
  /// impossible. The cost is that the write may land world-readable there —
  /// which is what the pre-slice code did on those volumes anyway.
  Future<void> _applyMode(String path, int? mode) async {
    if (mode == null) {
      return;
    }
    try {
      await _io.setPermissionBits(path, mode);
    } catch (error) {
      logWarning(
        'Safe writer could not set permission bits '
        '0${mode.toRadixString(8)} on $path ($error); the file keeps the '
        'filesystem default, which may be more permissive.',
      );
    }
  }

  Future<void> _writeVerified(String path, Uint8List bytes) async {
    final raf = await _io.openWrite(path);
    try {
      await _io.writeFull(raf, bytes);
      await _io.flush(raf);
    } finally {
      // A close failure must never replace the write/flush error the caller
      // needs to see (a disk-full EIO is the diagnosis; "close failed" is
      // not). The descriptor is abandoned either way.
      try {
        await _io.close(raf);
      } catch (_) {
        // Intentionally silent — see above.
      }
    }
    final actual = await _io.readBytes(path);
    if (actual.length != bytes.length || !_bytesEqual(actual, bytes)) {
      throw FileSystemException(
        'safe write verification failed: short or corrupt write',
        path,
      );
    }
  }

  Future<void> _bestEffortDelete(String path) async {
    try {
      await _io.delete(path);
    } catch (_) {
      // A failed cleanup must never mask the original failure; the stray
      // temp/partial backup is harmless — the target was never touched.
    }
  }

  static bool _isAlreadyExists(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == null) {
      // No OS detail (a fake IO in tests): treat as a collision, which is
      // what `create(exclusive: true)` overwhelmingly means here.
      return true;
    }
    return Platform.isWindows
        ? code == 80 || code == 183
        : code == 17; // EEXIST
  }

  static bool _isPermissionDenied(Object error) {
    if (error is! FileSystemException) {
      return false;
    }
    final code = error.osError?.errorCode;
    if (code == null) {
      return false;
    }
    return Platform.isWindows
        ? code == 5
        : code == 1 || code == 13; // EPERM, EACCES
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
