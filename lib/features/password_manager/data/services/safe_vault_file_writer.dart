import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/portable_path.dart';

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

/// The pre-write backup could not be created because the OS refused the
/// sibling file (spec 008 T109 MEDIUM-2 follow-up).
///
/// Nothing was written and the target is untouched: FR-9 mandates a hard stop
/// when the target cannot be backed up first, and unlike the temp there is no
/// degraded alternative — a backup IS a second file, so a sandbox that only
/// authorizes the chosen path cannot host one at all. This exists so the
/// caller (the three sync replacements) reports something a human can act on
/// instead of a raw `FileSystemException` carrying a verbatim vault path.
class SafeVaultBackupUnavailableException implements Exception {
  const SafeVaultBackupUnavailableException({
    required this.operation,
    required this.osReason,
  });

  /// The flow that was stopped, as passed to [SafeVaultFileWriter.write].
  final String operation;

  /// OS-level reason, WITHOUT any path: the constructor is fed through
  /// `_osReasonSafe`, which strips absolute-path-shaped tokens rather than
  /// trusting `strerror` to contain none.
  final String osReason;

  @override
  String toString() =>
      'SafeVaultBackupUnavailableException: "$operation" was stopped before '
      'anything was written because the system refused to create the backup '
      'file next to the database ($osReason). The database is unchanged. A '
      'sandboxed build is authorized for the file you picked, not for its '
      'folder — re-grant access to the folder, or keep the database in app '
      'storage.';
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

  /// Root of the app-private container, or `null` when this platform has no
  /// such directory, or it cannot be determined.
  ///
  /// This is the perimeter the writer gates symlink resolution on (T109
  /// HIGH-4 follow-up). `null` means "no perimeter", which the writer treats
  /// as "outside": links are resolved, i.e. the pre-follow-up behaviour that
  /// keeps the desktop write-through working — including in every
  /// environment where no Flutter plugin binding exists (unit tests, the
  /// native host).
  ///
  /// **Seam contract for subclasses: this must not throw.** [write] awaits it
  /// on every call, so an override that throws fails the save outright.
  /// Return `null` for "unknown" instead — which is what the `catch` below
  /// does for the production implementation.
  Future<String?> appDirectoryRoot() async {
    try {
      final root = await PortablePath.documentsRoot();
      return isAppPrivateDocumentsRoot(root, Platform.operatingSystem)
          ? root
          : null;
    } catch (_) {
      // No plugin binding, or the platform refused: perimeter unknown.
      return null;
    }
  }

  /// Whether the documents root of [operatingSystem] is a directory that only
  /// this app can populate.
  ///
  /// `getApplicationDocumentsDirectory()` is NOT one concept across targets,
  /// and taking it for an app-private container is what made the first cut of
  /// this gate a HIGH regression:
  /// - **iOS / Android** — the per-app container. App-private: a `.kdbx`
  ///   there is managed storage written by `MobileFileStorage`, so an entry
  ///   that is a symlink can only have been planted (#45/#46).
  /// - **macOS** — `~/Documents`, shared with every other app and the
  ///   picker's default location. UNLESS the app sandbox is on, where it
  ///   becomes `~/Library/Containers/<id>/Data/Documents`; the `Containers`
  ///   segment is the marker for that.
  /// - **Linux** — `xdg.getUserDirectory('DOCUMENTS')`, i.e. `~/Documents`.
  /// - **Windows** — `WindowsKnownFolder.Documents`, i.e.
  ///   `C:\Users\<user>\Documents`.
  ///
  /// On the last three a `~/Documents/vault.kdbx -> ~/Dropbox/vault.kdbx` is
  /// an ordinary, extremely plausible user setup that MUST keep being written
  /// through (HIGH-2), so those platforms get no perimeter at all.
  @visibleForTesting
  static bool isAppPrivateDocumentsRoot(String root, String operatingSystem) {
    switch (operatingSystem) {
      case 'ios':
      case 'android':
        return true;
      case 'macos':
        return p.split(root).contains('Containers');
      default:
        return false;
    }
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

  /// Whether POSIX permission bits are worth managing on this platform.
  ///
  /// Windows has no POSIX mode at all. iOS and Android are excluded for a
  /// different reason: every file lives in a per-app private container that
  /// no other app can read, so there is nothing to tighten — and the iOS
  /// sandbox forbids spawning a process, so a `chmod` there is a guaranteed
  /// failure plus a warning line on EVERY save.
  static bool get _managesPosixModes =>
      !Platform.isWindows && !Platform.isIOS && !Platform.isAndroid;

  /// POSIX permission bits of [path], or `null` when they are not meaningful
  /// or not readable: a platform without managed modes, or a missing file.
  Future<int?> permissionBits(String path) async {
    if (!_managesPosixModes) {
      return null;
    }
    final stat = await FileStat.stat(path);
    if (stat.type == FileSystemEntityType.notFound) {
      return null;
    }
    return stat.mode & 0xFFF;
  }

  /// Applies [bits] to [path]. No-op where [_managesPosixModes] is false.
  ///
  /// Dart exposes no `chmod`, so this shells out. Callers treat a failure as
  /// non-fatal — see [SafeVaultFileWriter.write].
  Future<void> setPermissionBits(String path, int bits) async {
    if (!_managesPosixModes) {
      return;
    }
    final octal = bits.toRadixString(8).padLeft(4, '0');
    // `--` so a path that begins with `-` is never parsed as an option.
    final result = await Process.run('chmod', [octal, '--', path]);
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
  ///
  /// Production surfacing of a degraded write is the writer's own
  /// `logWarning`, which names the `operation` — see
  /// [SafeVaultFileWriter.write]. This flag exists so a caller that wants to
  /// branch (or a test that wants to pin the happy path) can, without every
  /// call site having to duplicate that log line.
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
/// - a symlinked target OUTSIDE the app-private container is written
///   THROUGH, not replaced (T109 HIGH-2); one INSIDE it is replaced, not
///   followed (T109 HIGH-4 follow-up).
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
  Future<String> createBackup(String targetPath, {String? operation}) async {
    return _createBackup(targetPath, await _io.appDirectoryRoot(), operation);
  }

  /// [createBackup] against an already-fetched perimeter [root], so a
  /// [write] that takes a backup asks the platform for it exactly once.
  Future<String> _createBackup(
    String targetPath,
    String? root,
    String? operation,
  ) async {
    final resolved = _resolveTarget(targetPath, root);
    final mode = await _io.permissionBits(resolved);
    final source = await _io.readBytes(resolved);
    // The backup is named next to the CALLER's path, deliberately NOT next to
    // the resolved one — unlike the temp, which must be a sibling of the
    // resolved target to keep the rename same-filesystem and atomic.
    //
    // Naming it next to the resolved path put every `.bak` wherever the link
    // pointed: inside Dropbox/iCloud for a `~/vault.kdbx -> ~/Cloud/...`
    // setup, so full vault copies accumulated at the provider with nobody
    // cleaning them up (MEDIUM-4); and under a planted symlink it handed an
    // attacker complete vault copies in a directory of their choosing
    // (HIGH-4). Both close here: backups stay in the caller's perimeter,
    // which is also what the pre-slice `_backupFile` copy did.
    // MEDIUM-2: ONLY the sibling claim is converted. A permission failure
    // anywhere else in this method — above all an unreadable source vault —
    // has a different cause and a different remedy, and must not be reported
    // as "the folder refused a second file".
    final String backupPath;
    try {
      backupPath = await _claimFreshName(
        (micros, suffix) => '$targetPath.$micros-$suffix.bak',
        mode: mode,
      );
    } on FileSystemException catch (error) {
      if (!_isPermissionDenied(error)) {
        rethrow;
      }
      // The hard stop stays (FR-9) — only the diagnosis improves.
      throw SafeVaultBackupUnavailableException(
        operation: operation ?? 'unnamed operation',
        osReason: _osReasonSafe(error),
      );
    }
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
  /// **Symlink handling (HIGH-2 + HIGH-4).** A leaf symlink on a path the
  /// user chose — anything OUTSIDE the app-private container — is resolved
  /// first, so `~/vault.kdbx -> ~/Dropbox/vault.kdbx` is written THROUGH: the
  /// link survives and the cloud-synced file really changes. Without this,
  /// `rename(2)` would replace the link entry itself and silently freeze the
  /// real file forever.
  ///
  /// Two cases are deliberately NOT resolved, and in both the rename replaces
  /// the entry — the safe direction for the attacker-plantable case
  /// (#45/#46):
  /// - a **dangling** link, anywhere: it cannot be a legitimate cloud target,
  ///   since there is nothing on the other end;
  /// - **any** leaf link INSIDE the app-private container, live or not.
  ///   Nothing legitimate creates one there, an entry there may have been
  ///   planted, and `MobileFileStorage` already refuses to follow links in
  ///   that exact directory — the two layers agreed in prose but not in code
  ///   until this gate (see [_resolveTarget]). The gate is a runtime
  ///   perimeter check rather than a caller-supplied flag because the same
  ///   call site (`VaultKdbxService._save`, the sync replacements) serves a
  ///   managed mobile path and a user-picked desktop path interchangeably.
  ///   "App-private container" is decided per platform by
  ///   [SafeVaultFileIo.isAppPrivateDocumentsRoot] — NOT by the documents
  ///   directory alone, which on Linux, Windows and unsandboxed macOS is the
  ///   user's own `~/Documents` and hence the picker's default location.
  ///   When there is no perimeter the path counts as outside, i.e.
  ///   write-through — unchanged pre-follow-up behaviour.
  ///
  /// A path holding a `..` segment is refused outright before any of this:
  /// see [_refuseTraversal].
  ///
  /// **Sandbox fallback (HIGH-3).** Under the macOS app sandbox the
  /// `files.user-selected.read-write` entitlement authorizes the chosen PATH,
  /// not its directory, so creating a sibling temp can fail with
  /// `Operation not permitted` where a direct write succeeds. The same shape
  /// exists for Android SAF and the iOS document picker. When the temp cannot
  /// be created for a permission reason, this falls back to writing the
  /// authorized path in place (pre-slice behaviour) and logs the degradation,
  /// naming [operation] so the flow that degraded is identifiable.
  /// **Trade-off: the fallback is NOT atomic** — a crash mid-write can leave
  /// a truncated target. It is chosen over failing the save outright because
  /// the backup (when requested) still exists and losing the ability to save
  /// at all is the worse outcome. [SafeVaultFileWriteResult.atomic] reports
  /// which path ran.
  ///
  /// **Documented asymmetry, MEDIUM-2 — the fallback covers the temp only,
  /// on purpose.** [createBackup] runs first and also creates a sibling. It
  /// gets NO fallback: a backup is by definition a second file, so under a
  /// sandbox that authorizes the chosen path alone there is no degraded way
  /// to produce one — the only "fallback" available would be to skip the
  /// backup, which is exactly what FR-9 forbids, and the callers that ask for
  /// one are the three sync replacements, where remote bytes overwrite the
  /// local vault and the backup is the last line of defence.
  ///
  /// So IF the HIGH-3 premise holds on sandboxed macOS, a
  /// `backupExistingTarget: false` write (every routine vault save) degrades
  /// and succeeds, while a `backupExistingTarget: true` write fails
  /// permanently — fail-safe, target intact. What changed with the follow-up
  /// is only the diagnosis: that refusal now surfaces as a
  /// [SafeVaultBackupUnavailableException] naming [operation] and the OS
  /// reason, instead of a raw `FileSystemException` carrying a verbatim vault
  /// path into the sync error log. A non-permission backup failure still
  /// propagates unchanged.
  Future<SafeVaultFileWriteResult> write({
    required String targetPath,
    required Uint8List bytes,
    bool backupExistingTarget = false,
    String? operation,
  }) async {
    // One platform round-trip per write: asking twice would also open a
    // window in which the two answers disagree and the backup and the target
    // resolve against different perimeters.
    final root = await _io.appDirectoryRoot();
    final resolved = _resolveTarget(targetPath, root);

    String? backupPath;
    if (backupExistingTarget && await _io.exists(resolved)) {
      // Caller's path, not `resolved`: see createBackup on why the backup
      // stays in the caller's perimeter while the temp follows the link.
      backupPath = await _createBackup(targetPath, root, operation);
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
        'Safe writer degraded to a non-atomic in-place write during '
        '"${operation ?? 'unnamed operation'}": the sandbox refused a sibling '
        'temp file in ${_shape(directory)} (${_osReason(error)}). The target '
        'is still fully written and verified, but a crash mid-write can '
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

  /// The path the temp must be a sibling of, and the path the rename lands
  /// on — the leaf symlink resolved, or NOT resolved inside the app-private
  /// perimeter (T109 HIGH-4 follow-up).
  ///
  /// Outside the perimeter the path was chosen by the user through a picker,
  /// so a live leaf link is a deliberate `~/vault.kdbx -> ~/Dropbox/...`
  /// setup and must be written THROUGH (HIGH-2). Inside the app-private
  /// container the same entry is plantable (#45/#46) and nothing legitimate
  /// creates a link there, so it is left unresolved and the rename replaces
  /// the entry — the rule `MobileFileStorage` already applies to the very
  /// same directory. Dangling links are unaffected: [SafeVaultFileIo
  /// .resolveLeafLink] never resolves one, on either side of the perimeter.
  String _resolveTarget(String path, String? root) {
    _refuseTraversal(path);
    if (root != null && _isInsideAppPerimeter(path, root)) {
      return path;
    }
    return _io.resolveLeafLink(path);
  }

  /// Refuses a path holding a `..` segment, before the perimeter is even
  /// consulted.
  ///
  /// Textual containment and the kernel disagree the moment an intermediate
  /// symlink is involved: the kernel follows `dir` in `<root>/dir/../x`
  /// BEFORE applying `..`, so a planted directory link makes a
  /// textually-inside path land anywhere. Neither answer of the symlink gate
  /// helps — resolving lands on the link's target, not resolving lets the
  /// kernel do the same thing at rename time — so the only safe answer is to
  /// not write at all.
  ///
  /// `MobileFileStorage` refuses traversal for the same reason, and is loud
  /// (`deleteFileFromAppDirectory`) exactly where the operation acts rather
  /// than merely answers. This one acts.
  ///
  /// No legitimate caller produces `..`: paths come from `p.join` or from a
  /// picker. A tampered persisted record can, though — `PortablePath.decode`
  /// joins a stored `appdocs:` value onto the documents root without
  /// inspecting it — which is the #45/#46 threat model again.
  static void _refuseTraversal(String path) {
    // NOT `p.normalize(path)` first: normalize collapses `..` out of an
    // absolute path, which made the first cut of this guard dead code.
    if (!p.split(path).contains('..')) {
      return;
    }
    throw FileSystemException(
      'safe write refused: the path contains a ".." segment, which can leave '
      'the app perimeter through an intermediate symlink no matter how the '
      'symlink gate answers',
      _shape(path),
    );
  }

  /// Whether the ENTRY at [path] lives inside the app container at [root].
  ///
  /// Same two-part rule as `MobileFileStorage`: the parent is symlink-resolved
  /// (so iOS's `/var` vs `/private/var` spellings compare equal) while the
  /// leaf is left alone — the question here is where the entry lives, not
  /// what it points at, because the rename acts on the entry.
  ///
  /// Traversal never reaches here: [_refuseTraversal] rejects it first, which
  /// is why this can compare textually normalized paths at all.
  static bool _isInsideAppPerimeter(String path, String root) {
    final resolvedRoot = PortablePath.resolveForComparison(root);
    return p.isWithin(
      resolvedRoot,
      PortablePath.resolveParentForComparison(path),
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
        '0${mode.toRadixString(8)} on ${_shape(path)} '
        '(${_osReason(error)}); the file keeps the filesystem default, which '
        'may be more permissive.',
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

  /// A path reduced to something that identifies nothing: depth and
  /// extension only.
  ///
  /// AGENTS.md requires paths to be logged as a *shape*, never verbatim. On a
  /// password manager the vault's location is itself sensitive — a verbatim
  /// path written on every save ends up in crash reporters and support logs.
  static String _shape(String path) {
    final extension = p.extension(path);
    return '<depth ${p.split(path).length}>/*$extension';
  }

  /// [_osReason] with any absolute-path-shaped token replaced by `<path>`.
  ///
  /// `strerror`/`FormatMessage` messages carry no path today, so this is
  /// belt-and-braces — but [SafeVaultBackupUnavailableException] promises a
  /// path-free message to a UI/log surface, and a promise kept by the OS
  /// rather than by the code is not kept. Only tokens that START a path are
  /// stripped, so "Input/output error" survives intact.
  static String _osReasonSafe(Object error) =>
      _osReason(error).replaceAll(_absolutePathToken, '<path>');

  /// A whitespace-delimited token beginning like an absolute path: POSIX `/`
  /// or a Windows drive root.
  static final _absolutePathToken = RegExp(r'(?<![^\s])(/|[A-Za-z]:\\)\S*');

  /// The OS-level reason for [error] WITHOUT its path: a
  /// [FileSystemException]'s own `toString` embeds the offending path.
  static String _osReason(Object error) {
    if (error is FileSystemException) {
      return error.osError?.message ?? error.message;
    }
    return error.runtimeType.toString();
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
