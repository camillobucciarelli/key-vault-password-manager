import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/safe_vault_file_writer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// =============================================================================
// spec 008 Gate 1 — T108 (collision-safe backup) and T110 (failure injection).
//
// Invariant asserted by EVERY failure case: the target file is either its old
// content, complete, or the new content, complete — never truncated or mixed —
// and no backup file is ever overwritten.
// =============================================================================

// -----------------------------------------------------------------------------
// Platform-aware OS error codes for the fault-injection harness.
//
// `SafeVaultFileWriter` classifies a permission refusal with a PLATFORM-
// CONDITIONAL check: Win32 `ERROR_ACCESS_DENIED` (5) on Windows, POSIX `EPERM`
// (1) / `EACCES` (13) everywhere else. The harness used to hard-code the POSIX
// numbers as if they were universal, which made every case below assert the
// OPPOSITE contract once the suite ran on Windows (CI job `test-windows`, added
// in #114):
//
//   * errno 1 is not a refusal on Windows, so the sandbox fallback never
//     engaged and the five "degrades and succeeds" cases failed;
//   * POSIX `EIO` is 5, which collides with `ERROR_ACCESS_DENIED`, so the
//     NEGATIVE control was classified as a refusal, the fallback engaged, and
//     the two "never mistaken for a sandbox refusal" cases failed by not
//     throwing.
//
// Generating both codes for the host keeps each branch asserted on the platform
// where it is actually live. Inverting either side of the production check now
// fails the suite on that platform — see the "platform contract" group.
// -----------------------------------------------------------------------------

/// The OS error a genuine permission refusal carries on the host platform.
///
/// POSIX has TWO spellings and production accepts both, so the harness must be
/// able to produce both: [alt] selects `EACCES` (13) instead of `EPERM` (1).
/// Without a live `EACCES` site, deleting `code == 13` from the production
/// check survives the whole file. Windows has a single code, so [alt] is a
/// no-op there and the Windows branch stays asserted either way.
OSError _permissionDeniedOsError({bool alt = false}) => Platform.isWindows
    ? const OSError('Access is denied', 5) // ERROR_ACCESS_DENIED
    : (alt
          ? const OSError('Permission denied', 13) // EACCES
          : const OSError('Operation not permitted', 1)); // EPERM

/// The `strerror`-style text of [_permissionDeniedOsError], for assertions on
/// the reason the writer surfaces.
String get _permissionDeniedReason => _permissionDeniedOsError().message;

/// An OS error that is emphatically NOT a permission refusal on the host.
///
/// The negative control, and deliberately the ADJACENT class rather than an
/// arbitrary one: `ERROR_SHARING_VIOLATION` is what Windows raises when another
/// handle holds the file — the exact situation the T109 group below builds, and
/// the one a careless widening of the permission check would swallow. POSIX
/// `EIO` cannot serve on Windows because its number (5) IS
/// `ERROR_ACCESS_DENIED` there. Neither value is in the permission set of
/// either platform.
OSError _nonPermissionOsError() => Platform.isWindows
    ? const OSError(
        'The process cannot access the file',
        32,
      ) // SHARING_VIOLATION
    : const OSError('Input/output error', 5); // EIO

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('safe_writer_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> targetFile(List<int> bytes, {String name = 'vault.kdbx'}) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  List<File> backupsIn(Directory dir) => dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.bak'))
      .toList();

  group('T108 collision-safe backup', () {
    test('two backups in the same frozen microsecond get distinct names and '
        'both survive with the source content', () async {
      final frozen = DateTime.fromMicrosecondsSinceEpoch(1755859200000001);
      final writer = SafeVaultFileWriter(
        clock: () => frozen,
        random: _SequenceRandom([1, 2]),
      );
      final target = await targetFile(const [10, 20, 30]);

      final first = await writer.createBackup(target.path);
      final second = await writer.createBackup(target.path);

      expect(first, isNot(second));
      expect(first, contains('${frozen.microsecondsSinceEpoch}'));
      expect(await File(first).readAsBytes(), [10, 20, 30]);
      expect(await File(second).readAsBytes(), [10, 20, 30]);
      expect(backupsIn(tempDir), hasLength(2));
    });

    test('a preexisting file at the generated name is never overwritten; the '
        'backup retries with a new suffix', () async {
      final frozen = DateTime.fromMicrosecondsSinceEpoch(42);
      // First candidate suffix collides with the precreated file; the retry
      // suffix (7) is free.
      final writer = SafeVaultFileWriter(
        clock: () => frozen,
        random: _SequenceRandom([5, 7]),
      );
      final target = await targetFile(const [1, 2, 3]);
      final occupiedName =
          '${target.path}.${frozen.microsecondsSinceEpoch}-00005.bak';
      await File(occupiedName).writeAsBytes(const [99], flush: true);

      final backupPath = await writer.createBackup(target.path);

      expect(backupPath, isNot(occupiedName));
      expect(
        await File(occupiedName).readAsBytes(),
        [99],
        reason: 'the preexisting backup was truncated or replaced',
      );
      expect(await File(backupPath).readAsBytes(), [1, 2, 3]);
    });

    test('exhausting every suffix attempt is a defined failure: throws, '
        'nothing overwritten, target untouched', () async {
      final frozen = DateTime.fromMicrosecondsSinceEpoch(42);
      // Constant random + frozen clock -> every attempt generates the same
      // occupied name.
      final writer = SafeVaultFileWriter(
        clock: () => frozen,
        random: _SequenceRandom([5]),
      );
      final target = await targetFile(const [1, 2, 3]);
      final occupiedName =
          '${target.path}.${frozen.microsecondsSinceEpoch}-00005.bak';
      await File(occupiedName).writeAsBytes(const [99], flush: true);

      await expectLater(
        writer.createBackup(target.path),
        throwsA(isA<SafeVaultNameCollisionException>()),
      );
      expect(await File(occupiedName).readAsBytes(), [99]);
      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(backupsIn(tempDir), hasLength(1));
    });

    test('backup preserves the exact source content', () async {
      final writer = SafeVaultFileWriter();
      final bytes = List<int>.generate(4096, (i) => i % 251);
      final target = await targetFile(bytes);

      final backupPath = await writer.createBackup(target.path);

      expect(await File(backupPath).readAsBytes(), bytes);
      expect(p.dirname(backupPath), tempDir.path);
    });
  });

  group('T109 safe target writer', () {
    test('replaces an existing target and leaves a verified backup', () async {
      final writer = SafeVaultFileWriter();
      final target = await targetFile(const [1, 1, 1]);

      final result = await writer.write(
        targetPath: target.path,
        bytes: Uint8List.fromList(const [2, 2, 2]),
        backupExistingTarget: true,
      );

      expect(
        result.atomic,
        isTrue,
        reason:
            'the happy path must report an atomic replace — without this the '
            'flag can be flipped off for every write and no test notices',
      );
      expect(await target.readAsBytes(), [2, 2, 2]);
      expect(result.backupPath, isNotNull);
      expect(await File(result.backupPath!).readAsBytes(), [1, 1, 1]);
      // No stray temp left behind.
      final leftovers = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('writes a brand-new target without requiring a backup', () async {
      final writer = SafeVaultFileWriter();
      final path = p.join(tempDir.path, 'new.kdbx');

      final result = await writer.write(
        targetPath: path,
        bytes: Uint8List.fromList(const [7, 8]),
        backupExistingTarget: true,
      );

      expect(await File(path).readAsBytes(), [7, 8]);
      expect(result.backupPath, isNull);
      expect(result.atomic, isTrue);
    });

    test('temp lives in the SAME directory as the target, the write is '
        'flushed then closed before the rename, and the target is never '
        'deleted first', () async {
      final io = _RecordingIo();
      final writer = SafeVaultFileWriter(io: io);
      final target = await targetFile(const [1]);

      await writer.write(
        targetPath: target.path,
        bytes: Uint8List.fromList(const [2]),
        backupExistingTarget: true,
      );

      final tempPath = io.renames.last.$1;
      expect(p.dirname(tempPath), p.dirname(target.path));
      expect(io.renames.last.$2, target.path);
      expect(io.deleted, isNot(contains(target.path)));
      // Phase order on the temp: write -> flush -> close -> rename.
      expect(
        io.phases.join(','),
        contains('write,flush,close'),
        reason: 'fsync must happen before close, close before rename',
      );
      expect(io.phases.indexOf('rename'), io.phases.lastIndexOf('close') + 1);
    });
  });

  group('T110 failure injection', () {
    final oldBytes = Uint8List.fromList(const [1, 2, 3]);
    final newBytes = Uint8List.fromList(const [9, 8, 7, 6]);

    Future<(File, _FaultyIo, SafeVaultFileWriter)> setup(_Fault fault) async {
      final target = await targetFile(oldBytes);
      final io = _FaultyIo(fault);
      return (target, io, SafeVaultFileWriter(io: io));
    }

    Future<void> expectOldTargetIntact(
      File target,
      _FaultyIo io,
      SafeVaultFileWriter writer, {
      bool expectNoTargetRename = true,
    }) async {
      await expectLater(
        writer.write(
          targetPath: target.path,
          bytes: newBytes,
          backupExistingTarget: true,
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        await target.readAsBytes(),
        oldBytes,
        reason: 'the old target must remain intact and complete',
      );
      if (expectNoTargetRename) {
        expect(
          io.renames.where((r) => r.$2 == target.path),
          isEmpty,
          reason: 'no target write may be attempted after this failure',
        );
      }
    }

    test(
      'backup exclusive-create failure -> no target write attempted',
      () async {
        final (target, io, writer) = await setup(_Fault.backupCreate);
        await expectOldTargetIntact(target, io, writer);
        expect(backupsIn(tempDir), isEmpty);
      },
    );

    test(
      'backup write failure -> no target write; partial backup removed',
      () async {
        final (target, io, writer) = await setup(_Fault.backupWrite);
        await expectOldTargetIntact(target, io, writer);
        expect(backupsIn(tempDir), isEmpty);
      },
    );

    test('backup flush failure -> no target write attempted', () async {
      final (target, io, writer) = await setup(_Fault.backupFlush);
      await expectOldTargetIntact(target, io, writer);
    });

    test(
      'backup verify failure (corrupt read-back) -> no target write',
      () async {
        final (target, io, writer) = await setup(_Fault.backupVerify);
        await expectOldTargetIntact(target, io, writer);
        expect(backupsIn(tempDir), isEmpty);
      },
    );

    test(
      'disk-full short write on the temp -> old target intact, temp gone',
      () async {
        final (target, io, writer) = await setup(_Fault.shortWrite);
        await expectOldTargetIntact(target, io, writer);
        expect(
          tempDir.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.tmp'),
          ),
          isEmpty,
        );
      },
    );

    test('target flush failure -> old target intact', () async {
      final (target, io, writer) = await setup(_Fault.targetFlush);
      await expectOldTargetIntact(target, io, writer);
    });

    test(
      'rename failure -> old target intact; verified backup retained',
      () async {
        final (target, io, writer) = await setup(_Fault.rename);
        await expectOldTargetIntact(
          target,
          io,
          writer,
          expectNoTargetRename: false,
        );
        final backups = backupsIn(tempDir);
        expect(backups, hasLength(1));
        expect(await backups.single.readAsBytes(), oldBytes);
      },
    );

    test('LOW-1: a close() failure never masks the write error that caused '
        'it', () async {
      // Disk-full surfaces on flush; the close that follows in the `finally`
      // then fails too. The caller must still see the flush diagnosis — with
      // an unguarded `close` in the `finally`, the close error replaces it
      // and the disk-full is lost.
      final (target, _, writer) = await setup(_Fault.targetFlushAndClose);
      await expectLater(
        writer.write(
          targetPath: target.path,
          bytes: newBytes,
          backupExistingTarget: true,
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('disk full on flush'),
          ),
        ),
      );
      expect(await target.readAsBytes(), oldBytes);
    });

    test('cleanup failure never masks the original error and never touches '
        'the target', () async {
      final (target, io, writer) = await setup(_Fault.shortWriteAndCleanup);
      await expectLater(
        writer.write(
          targetPath: target.path,
          bytes: newBytes,
          backupExistingTarget: true,
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('verification failed'),
          ),
        ),
      );
      expect(await target.readAsBytes(), oldBytes);
    });

    test('directory sync failure after the rename is swallowed: the new '
        'target is complete', () async {
      final (target, _, writer) = await setup(_Fault.directorySync);
      final result = await writer.write(
        targetPath: target.path,
        bytes: newBytes,
        backupExistingTarget: true,
      );
      expect(await target.readAsBytes(), newBytes);
      expect(await File(result.backupPath!).readAsBytes(), oldBytes);
    });

    test('every failure mode leaves the directory with zero overwritten '
        'backups', () async {
      for (final fault in [
        _Fault.backupCreate,
        _Fault.backupWrite,
        _Fault.backupFlush,
        _Fault.backupVerify,
        _Fault.shortWrite,
        _Fault.targetFlush,
        _Fault.rename,
      ]) {
        final dir = await Directory.systemTemp.createTemp('safe_writer_all_');
        addTearDown(() => dir.delete(recursive: true));
        final target = File(p.join(dir.path, 'vault.kdbx'));
        await target.writeAsBytes(oldBytes, flush: true);
        final sentinel = File(p.join(dir.path, 'vault.kdbx.sentinel.bak'));
        await sentinel.writeAsBytes(const [42], flush: true);

        final writer = SafeVaultFileWriter(io: _FaultyIo(fault));
        await expectLater(
          writer.write(
            targetPath: target.path,
            bytes: newBytes,
            backupExistingTarget: true,
          ),
          throwsA(isA<Exception>()),
          reason: '$fault must surface',
        );
        expect(
          await target.readAsBytes(),
          oldBytes,
          reason: '$fault corrupted the target',
        );
        expect(
          await sentinel.readAsBytes(),
          [42],
          reason: '$fault overwrote an existing backup',
        );
      }
    });
  });

  // ===========================================================================
  // Tester HIGH-1 — the replace must not declass POSIX permissions.
  // Probe that produced the finding: target_before=600|after=644|backup=644.
  // `writeAsBytes` reused the existing inode and kept its mode; a rename
  // installs a NEW inode created with `0666 & ~umask`.
  // ===========================================================================
  group('HIGH-1 permission preservation', () {
    Future<int> modeOf(String path) async =>
        (await FileStat.stat(path)).mode & 0x1FF;

    test(
      'an owner-only target stays owner-only, and so does its backup',
      () async {
        final writer = SafeVaultFileWriter();
        final target = await targetFile(const [1, 2, 3]);
        await Process.run('chmod', ['600', target.path]);
        expect(await modeOf(target.path), 0x180, reason: 'setup failed');

        final result = await writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [4, 5, 6]),
          backupExistingTarget: true,
        );

        expect(
          await modeOf(target.path),
          0x180,
          reason: 'the rename declassed the vault to world-readable',
        );
        expect(
          await modeOf(result.backupPath!),
          0x180,
          reason:
              'the .bak is a full copy of the vault and must match its mode',
        );
      },
      skip: Platform.isWindows ? 'POSIX modes are not meaningful' : null,
    );

    test(
      'a group-readable target keeps exactly its own mode, not a default',
      () async {
        final writer = SafeVaultFileWriter();
        final target = await targetFile(const [1]);
        await Process.run('chmod', ['640', target.path]);

        await writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [2]),
          backupExistingTarget: true,
        );

        expect(await modeOf(target.path), 0x1A0); // 0640
      },
      skip: Platform.isWindows ? 'POSIX modes are not meaningful' : null,
    );

    test(
      'a brand-new vault is created owner-only, never 0644',
      () async {
        final writer = SafeVaultFileWriter();
        final path = p.join(tempDir.path, 'fresh.kdbx');

        await writer.write(
          targetPath: path,
          bytes: Uint8List.fromList(const [1]),
        );

        // Literal, NOT `SafeVaultFileWriter.defaultVaultMode`: comparing the
        // constant against itself let a mutation of it to 0644 stay green.
        expect(await modeOf(path), 0x180); // 0600
      },
      skip: Platform.isWindows ? 'POSIX modes are not meaningful' : null,
    );

    test('the mode is applied BEFORE any content exists, so there is no '
        'world-readable window', () async {
      final io = _RecordingIo();
      final writer = SafeVaultFileWriter(io: io);
      final target = await targetFile(const [1]);
      await Process.run('chmod', ['600', target.path]);

      await writer.write(
        targetPath: target.path,
        bytes: Uint8List.fromList(const [2]),
        backupExistingTarget: true,
      );

      for (final (path, _) in io.chmods) {
        final chmodIndex = io.phases.indexOf('createExclusive:$path');
        expect(chmodIndex, isNonNegative);
        // The chmod is issued between the exclusive-create and the first
        // write on that path.
        expect(
          io.phases.indexOf('write', chmodIndex),
          greaterThan(chmodIndex),
          reason: 'content reached $path before its mode was tightened',
        );
      }
      expect(io.chmods, isNotEmpty);
    }, skip: Platform.isWindows ? 'POSIX modes are not meaningful' : null);

    test(
      'a chmod failure degrades with a warning instead of failing the save',
      () async {
        // exFAT / FAT32 / some network mounts have no POSIX modes at all.
        final writer = SafeVaultFileWriter(io: _ChmodRefusingIo());
        final target = await targetFile(const [1, 2, 3]);

        final result = await writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [7, 7]),
          backupExistingTarget: true,
        );

        expect(await target.readAsBytes(), [7, 7]);
        expect(result.backupPath, isNotNull);
      },
      skip: Platform.isWindows ? 'POSIX modes are not meaningful' : null,
    );
  });

  // ===========================================================================
  // Tester HIGH-2 — a symlinked vault must be written THROUGH.
  // Probe: link_still_link=false|real_bytes=[1,2,3]|link_bytes=[9,9,9] — the
  // rename replaced the link entry, freezing the cloud-synced real file.
  //
  // The counterpart is the attacker-plantable staging path (#45/#46), which
  // must NOT be followed. The two are distinguished by liveness: a DANGLING
  // link cannot be a legitimate cloud target, so it is left unresolved and
  // the rename replaces the entry. `MobileFileStorage` (app-private, plantable
  // directory) never resolves at all — see its comment.
  // ===========================================================================
  group('HIGH-2 symlink write-through', () {
    test(
      'a live symlinked vault survives the write and the real file changes',
      () async {
        final writer = SafeVaultFileWriter();
        final real = File(p.join(tempDir.path, 'real.kdbx'));
        await real.writeAsBytes(const [1, 2, 3], flush: true);
        final linkPath = p.join(tempDir.path, 'vault.kdbx');
        await Link(linkPath).create(real.path);

        await writer.write(
          targetPath: linkPath,
          bytes: Uint8List.fromList(const [9, 9, 9]),
        );

        expect(
          FileSystemEntity.isLinkSync(linkPath),
          isTrue,
          reason:
              'the symlink entry was replaced; the cloud file is now frozen',
        );
        expect(await real.readAsBytes(), [9, 9, 9]);
        expect(await File(linkPath).readAsBytes(), [9, 9, 9]);
      },
    );

    test('the backup lands next to the CALLER path, never inside the cloud '
        'folder the link points at', () async {
      final writer = SafeVaultFileWriter();
      final realDir = await Directory(p.join(tempDir.path, 'cloud')).create();
      final real = File(p.join(realDir.path, 'real.kdbx'));
      await real.writeAsBytes(const [1], flush: true);
      final linkPath = p.join(tempDir.path, 'vault.kdbx');
      await Link(linkPath).create(real.path);

      final result = await writer.write(
        targetPath: linkPath,
        bytes: Uint8List.fromList(const [2]),
        backupExistingTarget: true,
      );

      // MEDIUM-4 / HIGH-4: the backup belongs next to the CALLER's path, not
      // next to the link's destination. Naming it next to the resolved path
      // dropped every `.bak` into the cloud folder (uploaded, unbounded, no
      // cleanup) and, under a planted link, into a directory of the
      // attacker's choosing. The temp is the opposite — it MUST be a sibling
      // of the resolved target so the rename stays same-filesystem.
      expect(
        p.dirname(result.backupPath!),
        p.dirname(linkPath),
        reason: 'the .bak escaped the caller directory',
      );
      expect(
        p.dirname(result.backupPath!),
        isNot(realDir.resolveSymbolicLinksSync()),
      );
      expect(await File(result.backupPath!).readAsBytes(), [1]);
      // ...and the write still went THROUGH the link.
      expect(await real.readAsBytes(), [2]);
      expect(FileSystemEntity.isLinkSync(linkPath), isTrue);
    });

    test(
      'the caller gets its OWN spelling back, not the resolved one',
      () async {
        final writer = SafeVaultFileWriter();
        final real = File(p.join(tempDir.path, 'real.kdbx'));
        await real.writeAsBytes(const [1], flush: true);
        final linkPath = p.join(tempDir.path, 'vault.kdbx');
        await Link(linkPath).create(real.path);

        final result = await writer.write(
          targetPath: linkPath,
          bytes: Uint8List.fromList(const [2]),
        );

        expect(result.targetPath, linkPath);
      },
    );

    test('a DANGLING link is not followed: the entry is replaced and nothing '
        'is created outside (#45/#46 attack shape)', () async {
      final writer = SafeVaultFileWriter();
      final outside = await Directory(p.join(tempDir.path, 'outside')).create();
      final victimPath = p.join(outside.path, 'victim.kdbx');
      final linkPath = p.join(tempDir.path, 'planted.kdbx');
      await Link(linkPath).create(victimPath);
      expect(await File(victimPath).exists(), isFalse);

      await writer.write(
        targetPath: linkPath,
        bytes: Uint8List.fromList(const [5]),
      );

      expect(
        await File(victimPath).exists(),
        isFalse,
        reason: 'following a dangling link would create a file outside',
      );
      expect(FileSystemEntity.isLinkSync(linkPath), isFalse);
      expect(await File(linkPath).readAsBytes(), [5]);
    });
  });

  // ===========================================================================
  // Tester HIGH-3 — macOS sandbox authorizes the chosen PATH, not its parent,
  // so a sibling temp can be refused where a direct write succeeds. Same shape
  // for Android SAF and the iOS document picker. Cannot be reproduced on host;
  // the fault seam stands in for the refusal.
  // ===========================================================================
  group('HIGH-3 sandbox fallback', () {
    test('a permission-refused temp falls back to a verified in-place write '
        'instead of failing the save', () async {
      final io = _FaultyIo(_Fault.tempPermissionDenied);
      final writer = SafeVaultFileWriter(io: io);
      final target = await targetFile(const [1, 2, 3]);

      final result = await writer.write(
        targetPath: target.path,
        bytes: Uint8List.fromList(const [7, 7, 7, 7]),
        backupExistingTarget: true,
      );

      expect(await target.readAsBytes(), [7, 7, 7, 7]);
      expect(
        result.atomic,
        isFalse,
        reason: 'the caller must be able to see that atomicity was lost',
      );
      // The backup still exists: the degraded path is recoverable.
      expect(await File(result.backupPath!).readAsBytes(), [1, 2, 3]);
      expect(io.renames, isEmpty);
    });

    test('the fallback creates a brand-new target owner-only', () async {
      final writer = SafeVaultFileWriter(
        io: _FaultyIo(_Fault.tempPermissionDenied),
      );
      final path = p.join(tempDir.path, 'sandboxed.kdbx');

      final result = await writer.write(
        targetPath: path,
        bytes: Uint8List.fromList(const [1]),
      );

      expect(result.atomic, isFalse);
      expect(await File(path).readAsBytes(), [1]);
      if (!Platform.isWindows) {
        // Literal for the same reason as above.
        expect((await FileStat.stat(path)).mode & 0x1FF, 0x180); // 0600
      }
    });

    test('a NON-permission temp failure is never mistaken for a sandbox '
        'refusal or for a name collision', () async {
      // Regression on the retry loop: it used to swallow every
      // FileSystemException as "name taken" and report 32 collisions.
      final writer = SafeVaultFileWriter(io: _TempIoErrorIo());
      final target = await targetFile(const [1, 2, 3]);

      await expectLater(
        writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [9]),
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('injected: non-permission error on the temp'),
          ),
        ),
      );
      expect(await target.readAsBytes(), [1, 2, 3]);
    });
  });

  // ===========================================================================
  // Tester MEDIUM-1 — FR-9.5 (spec.md:665): the verified backup happens before
  // ANY target byte is written. Mutation (g) — moving createBackup after the
  // temp write — survived the whole suite before this test existed.
  // ===========================================================================
  group('MEDIUM-1 backup-before-write ordering', () {
    test(
      'the first exclusive-create of the write is the backup, not the temp',
      () async {
        final io = _RecordingIo();
        final writer = SafeVaultFileWriter(io: io);
        final target = await targetFile(const [1, 2, 3]);

        await writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [4, 5, 6]),
          backupExistingTarget: true,
        );

        expect(io.exclusiveCreates, hasLength(2));
        expect(
          io.exclusiveCreates.first,
          endsWith('.bak'),
          reason:
              'FR-9.5: the backup must be claimed before the target temp — a '
              'temp claimed first means bytes can reach the target with no '
              'verified backup on disk',
        );
        expect(io.exclusiveCreates.last, endsWith('.tmp'));
        // ...and the backup is fully written+verified before the temp exists.
        final backupCreate = io.phases.indexOf(
          'createExclusive:${io.exclusiveCreates.first}',
        );
        final tempCreate = io.phases.indexOf(
          'createExclusive:${io.exclusiveCreates.last}',
        );
        expect(backupCreate, lessThan(tempCreate));
        expect(
          io.phases.indexOf('write'),
          inInclusiveRange(backupCreate, tempCreate),
          reason: 'the first write must be the backup content',
        );
      },
    );
  });

  // ===========================================================================
  // Tester HIGH-4 follow-up — symlink resolution is gated on the app-private
  // perimeter. BOTH directions have a killer here: dropping the gate breaks
  // the "inside" test, gating everything breaks the "outside" one, so neither
  // mutation survives.
  //
  // Perimeter = the app documents container. Outside it a path was chosen by
  // the user through a picker (HIGH-2 write-through must keep working);
  // inside it an entry may have been planted (#45/#46) and `MobileFileStorage`
  // already refuses to follow links in that same directory.
  // ===========================================================================
  group('HIGH-4 perimeter-gated symlink resolution', () {
    late Directory appDocs;
    late Directory cloud;
    late File real;

    setUp(() async {
      appDocs = await Directory(p.join(tempDir.path, 'appdocs')).create();
      cloud = await Directory(p.join(tempDir.path, 'cloud')).create();
      real = File(p.join(cloud.path, 'real.kdbx'));
      await real.writeAsBytes(const [1, 2, 3], flush: true);
    });

    test('OUTSIDE the perimeter a live link is still followed: the cloud file '
        'changes and the link survives', () async {
      // `~/vault.kdbx -> ~/Dropbox/vault.kdbx`: the HIGH-2 fix. The perimeter
      // is a real, unrelated directory, so the gate must not fire.
      final writer = SafeVaultFileWriter(io: _PerimeterIo(appDocs.path));
      final linkPath = p.join(tempDir.path, 'vault.kdbx');
      await Link(linkPath).create(real.path);

      await writer.write(
        targetPath: linkPath,
        bytes: Uint8List.fromList(const [9, 9, 9]),
      );

      expect(
        FileSystemEntity.isLinkSync(linkPath),
        isTrue,
        reason: 'the link entry was replaced; the cloud file is now frozen',
      );
      expect(await real.readAsBytes(), [9, 9, 9]);
    });

    test('INSIDE the perimeter a live link is NOT followed: the entry is '
        'replaced and the file it pointed at is untouched', () async {
      // The #45/#46 attack shape that HIGH-2 left open: a LIVE link planted
      // in app-private storage. Nothing legitimate creates one there.
      final writer = SafeVaultFileWriter(io: _PerimeterIo(appDocs.path));
      final linkPath = p.join(appDocs.path, 'planted.kdbx');
      await Link(linkPath).create(real.path);

      await writer.write(
        targetPath: linkPath,
        bytes: Uint8List.fromList(const [9, 9, 9]),
        operation: 'vault save',
      );

      expect(
        await real.readAsBytes(),
        [1, 2, 3],
        reason: 'the write escaped app storage through a planted link',
      );
      expect(FileSystemEntity.isLinkSync(linkPath), isFalse);
      expect(await File(linkPath).readAsBytes(), [9, 9, 9]);
    });

    test(
      'INSIDE the perimeter the backup is taken too, and also stays put',
      () async {
        final writer = SafeVaultFileWriter(io: _PerimeterIo(appDocs.path));
        final linkPath = p.join(appDocs.path, 'planted.kdbx');
        await Link(linkPath).create(real.path);

        final result = await writer.write(
          targetPath: linkPath,
          bytes: Uint8List.fromList(const [4]),
          backupExistingTarget: true,
        );

        expect(p.dirname(result.backupPath!), appDocs.path);
        expect(await real.readAsBytes(), [1, 2, 3]);
        expect(await File(linkPath).readAsBytes(), [4]);
      },
    );

    test(
      'a sibling directory sharing the perimeter prefix is OUTSIDE',
      () async {
        // `startsWith` instead of `p.isWithin` would swallow `<root>-old`.
        final writer = SafeVaultFileWriter(io: _PerimeterIo(appDocs.path));
        final sibling = await Directory('${appDocs.path}-old').create();
        final linkPath = p.join(sibling.path, 'vault.kdbx');
        await Link(linkPath).create(real.path);

        await writer.write(
          targetPath: linkPath,
          bytes: Uint8List.fromList(const [6]),
        );

        expect(FileSystemEntity.isLinkSync(linkPath), isTrue);
        expect(await real.readAsBytes(), [6]);
      },
    );

    test('createBackup goes through the gate too, instead of resolving on its '
        'own', () async {
      // The bypass is nearly invisible by content (readBytes/stat follow the
      // link at OS level either way), so it is pinned by the call itself.
      final io = _PerimeterIo(appDocs.path);
      final writer = SafeVaultFileWriter(io: io);
      final linkPath = p.join(appDocs.path, 'planted.kdbx');
      await Link(linkPath).create(real.path);

      await writer.createBackup(linkPath);

      expect(
        io.resolveLeafLinkCalls,
        isEmpty,
        reason: 'the backup resolved a link the perimeter gate refused',
      );
    });

    test('a write that takes a backup asks the platform for the perimeter '
        'exactly once', () async {
      final io = _ClassifyingIo(appDocs.path, 'ios');
      final writer = SafeVaultFileWriter(io: io);
      final target = File(p.join(appDocs.path, 'vault.kdbx'));
      await target.writeAsBytes(const [1], flush: true);

      await writer.write(
        targetPath: target.path,
        bytes: Uint8List.fromList(const [2]),
        backupExistingTarget: true,
      );

      expect(io.appDirectoryRootCalls, 1);
    });

    test('a perimeter that cannot be determined counts as OUTSIDE, so the '
        'pre-follow-up write-through is unchanged', () async {
      // The production default: on desktop and in every non-Flutter host the
      // documents root may be unavailable. Unknown must never mean "refuse to
      // follow", or a cloud-symlinked vault would silently stop syncing.
      final writer = SafeVaultFileWriter(io: _PerimeterIo(null));
      final linkPath = p.join(appDocs.path, 'vault.kdbx');
      await Link(linkPath).create(real.path);

      await writer.write(
        targetPath: linkPath,
        bytes: Uint8List.fromList(const [8]),
      );

      expect(FileSystemEntity.isLinkSync(linkPath), isTrue);
      expect(await real.readAsBytes(), [8]);
    });
  });

  // ===========================================================================
  // Tester FINDING-1 — "the documents directory" is NOT one concept.
  // `getApplicationDocumentsDirectory()` is the app container on iOS/Android
  // and under the macOS sandbox, but the user's own `~/Documents` on Linux,
  // Windows and unsandboxed macOS — where it is also the picker's DEFAULT
  // location. Treating it as app-private there re-broke HIGH-2 on exactly the
  // most likely desktop setup.
  // ===========================================================================
  group('FINDING-1 the perimeter is app-private on every platform', () {
    test('per-platform classification of a documents root', () {
      bool classify(String root, String os) =>
          SafeVaultFileIo.isAppPrivateDocumentsRoot(root, os);

      // Per-app containers: app-private.
      expect(
        classify('/var/mobile/Containers/Data/App/X/Documents', 'ios'),
        isTrue,
      );
      expect(
        classify('/data/user/0/com.example/app_flutter', 'android'),
        isTrue,
      );
      // macOS: only under the sandbox container.
      expect(
        classify('/Users/u/Library/Containers/com.x/Data/Documents', 'macos'),
        isTrue,
      );
      expect(classify('/Users/u/Documents', 'macos'), isFalse);
      // LOW-1: the marker is the `Library/Containers` PAIR. A home that
      // happens to hold a directory named `Containers` must not switch the
      // perimeter on over the user's real ~/Documents.
      expect(classify('/Users/Containers/Documents', 'macos'), isFalse);
      expect(classify('/Containers/x/Documents', 'macos'), isFalse);
      // Linux `xdg DOCUMENTS` and the Windows known folder are the USER's.
      expect(classify('/home/u/Documents', 'linux'), isFalse);
      expect(classify(r'C:\Users\u\Documents', 'windows'), isFalse);
    });

    test('MEDIUM-1 composition: the PRODUCTION seam applies the '
        'classification, not just the pure function', () async {
      // Every other test here replaces `appDirectoryRoot()` with a fake, so
      // dropping the classification INSIDE it — i.e. reintroducing FINDING-1
      // verbatim — survived the whole suite. This is the only test that runs
      // the real seam over a real path_provider answer.
      final original = PathProviderPlatform.instance;
      addTearDown(() => PathProviderPlatform.instance = original);

      // Shape of the USER's documents directory: what Linux, Windows and
      // unsandboxed macOS actually return.
      final userDocuments = await Directory(
        p.join(tempDir.path, 'home', 'Documents'),
      ).create(recursive: true);
      PathProviderPlatform.instance = _FixedPathProvider(userDocuments.path);

      expect(
        await const SafeVaultFileIo().appDirectoryRoot(),
        isNull,
        reason:
            'the production seam handed back a USER directory as the '
            'app-private perimeter — FINDING-1, on ${Platform.operatingSystem}',
      );

      // ...and the positive half, on the one host that can express it.
      final container = await Directory(
        p.join(
          tempDir.path,
          'Library',
          'Containers',
          'com.x',
          'Data',
          'Documents',
        ),
      ).create(recursive: true);
      PathProviderPlatform.instance = _FixedPathProvider(container.path);

      expect(
        await const SafeVaultFileIo().appDirectoryRoot(),
        Platform.isMacOS ? container.path : isNull,
        reason:
            'a sandboxed macOS container must be a perimeter; every other '
            'host has no documents-based perimeter at all',
      );
    });

    test('DESKTOP REPRO: ~/Documents/vault.kdbx -> ~/Dropbox/vault.kdbx is '
        'still written THROUGH', () async {
      // The regression the tester reproduced: followed=false, cloud bytes
      // frozen, app reporting a successful save.
      final documents = await Directory(
        p.join(tempDir.path, 'home', 'Documents'),
      ).create(recursive: true);
      final dropbox = await Directory(
        p.join(tempDir.path, 'home', 'Dropbox'),
      ).create();
      final cloudVault = File(p.join(dropbox.path, 'vault.kdbx'));
      await cloudVault.writeAsBytes(const [1, 2, 3], flush: true);
      final linkPath = p.join(documents.path, 'vault.kdbx');
      await Link(linkPath).create(cloudVault.path);

      final writer = SafeVaultFileWriter(
        io: _ClassifyingIo(documents.path, 'linux'),
      );
      await writer.write(
        targetPath: linkPath,
        bytes: Uint8List.fromList(const [9, 9]),
        operation: 'vault save',
      );

      expect(
        await cloudVault.readAsBytes(),
        [9, 9],
        reason: 'the cloud vault froze: sync stops silently from here on',
      );
      expect(FileSystemEntity.isLinkSync(linkPath), isTrue);
    });

    test('the SAME fixture on iOS is inside the perimeter and is not '
        'followed', () async {
      // One fixture, both platforms: what changes is only the classification.
      final documents = await Directory(
        p.join(tempDir.path, 'Containers', 'Data', 'App', 'X', 'Documents'),
      ).create(recursive: true);
      final outside = await Directory(p.join(tempDir.path, 'outside')).create();
      final victim = File(p.join(outside.path, 'victim.kdbx'));
      await victim.writeAsBytes(const [1, 2, 3], flush: true);
      final linkPath = p.join(documents.path, 'planted.kdbx');
      await Link(linkPath).create(victim.path);

      final writer = SafeVaultFileWriter(
        io: _ClassifyingIo(documents.path, 'ios'),
      );
      await writer.write(
        targetPath: linkPath,
        bytes: Uint8List.fromList(const [9, 9]),
        operation: 'vault save',
      );

      expect(await victim.readAsBytes(), [1, 2, 3]);
      expect(FileSystemEntity.isLinkSync(linkPath), isFalse);
    });
  });

  // ===========================================================================
  // Tester FINDING-2 — the kernel follows an intermediate symlink BEFORE it
  // applies `..`, so a textually-inside path can land anywhere. Neither answer
  // of the symlink gate helps; the write itself has to be refused.
  // ===========================================================================
  group('FINDING-2 traversal is refused, not classified', () {
    test('REPRO: a planted directory symlink plus ".." never reaches the '
        'victim', () async {
      final documents = await Directory(
        p.join(tempDir.path, 'Containers', 'Data', 'App', 'X', 'Documents'),
      ).create(recursive: true);
      final outside = await Directory(p.join(tempDir.path, 'outside')).create();
      final victim = File(p.join(outside.path, 'victim.kdbx'));
      await victim.writeAsBytes(const [1, 2, 3], flush: true);
      // The planted piece: a DIRECTORY link inside app storage. `..` after it
      // is resolved by the kernel relative to `outside`, not to `documents`.
      await Link(p.join(documents.path, 'evil')).create(outside.path);
      final targetPath = p.join(
        documents.path,
        'evil',
        '..',
        'outside',
        'victim.kdbx',
      );

      final writer = SafeVaultFileWriter(
        io: _ClassifyingIo(documents.path, 'ios'),
      );

      await expectLater(
        writer.write(
          targetPath: targetPath,
          bytes: Uint8List.fromList(const [9, 9]),
          operation: 'vault save',
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('".." segment'),
          ),
        ),
      );
      expect(
        await victim.readAsBytes(),
        [1, 2, 3],
        reason: 'the write escaped the perimeter through link + ".."',
      );
      expect(
        outside.listSync().whereType<File>().map((f) => p.basename(f.path)),
        ['victim.kdbx'],
        reason: 'no temp may be left outside the perimeter either',
      );
    });

    test('the refusal does not depend on the perimeter being known', () async {
      // The guard runs before the perimeter question, so a desktop path with
      // traversal is refused too — no caller produces one, and a tampered
      // `appdocs:` record decodes straight into `p.joinAll`.
      final writer = SafeVaultFileWriter(io: _PerimeterIo(null));

      await expectLater(
        writer.write(
          targetPath: p.join(tempDir.path, 'a', '..', 'vault.kdbx'),
          bytes: Uint8List.fromList(const [1]),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(p.join(tempDir.path, 'vault.kdbx')).existsSync(), isFalse);
    });

    test('the refusal names no verbatim path', () async {
      final writer = SafeVaultFileWriter(io: _PerimeterIo(null));
      final targetPath = p.join(tempDir.path, 'a', '..', 'secret-vault.kdbx');

      try {
        await writer.write(
          targetPath: targetPath,
          bytes: Uint8List.fromList(const [1]),
        );
        fail('a traversal path must be refused');
      } on FileSystemException catch (error) {
        expect(error.toString(), isNot(contains('secret-vault')));
      }
    });
  });

  // ===========================================================================
  // Tester MEDIUM-2 — the HIGH-3 sandbox fallback covers the temp only. The
  // backup keeps its FR-9 hard stop (a backup IS a second file: under a
  // sandbox that authorizes one path there is no degraded way to make one,
  // and the only alternative would be to skip it). What must NOT survive is
  // the raw FileSystemException, which carried a verbatim vault path into the
  // sync error log.
  // ===========================================================================
  group('MEDIUM-2 backup refusal is a comprehensible hard stop', () {
    test('a permission-refused backup aborts with a typed error and leaves '
        'the target intact', () async {
      final io = _FaultyIo(_Fault.backupPermissionDenied);
      final writer = SafeVaultFileWriter(io: io);
      final target = await targetFile(const [1, 2, 3]);

      await expectLater(
        writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [9, 9, 9, 9]),
          backupExistingTarget: true,
          operation: 'sync replace from remote',
        ),
        throwsA(
          isA<SafeVaultBackupUnavailableException>()
              .having(
                (e) => e.toString(),
                'message',
                contains('sync replace from remote'),
              )
              .having(
                (e) => e.toString(),
                'message',
                contains(_permissionDeniedReason),
              ),
        ),
      );

      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(backupsIn(tempDir), isEmpty);
      expect(
        io.renames.where((r) => r.$2 == target.path),
        isEmpty,
        reason: 'no target write may follow a refused backup',
      );
    });

    test('the OTHER permission errno is a hard stop too', () async {
      // POSIX reports a refused sibling as EPERM or EACCES depending on the
      // cause, and production accepts both. The rest of this file injects only
      // the first, so deleting `code == 13` from `_isPermissionDenied` used to
      // survive the entire suite: the raw FileSystemException would escape
      // instead of the typed hard stop, and the sync error path would go back
      // to logging a verbatim vault path. On Windows there is one refusal code,
      // so this asserts the same live branch as its sibling test.
      final writer = SafeVaultFileWriter(
        io: _FaultyIo(_Fault.backupPermissionDeniedAlt),
      );
      final target = await targetFile(const [1, 2, 3]);

      await expectLater(
        writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [9, 9]),
          backupExistingTarget: true,
          operation: 'sync replace from remote',
        ),
        throwsA(isA<SafeVaultBackupUnavailableException>()),
      );

      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(backupsIn(tempDir), isEmpty);
    });

    test('the typed error never carries the verbatim vault path', () async {
      // AGENTS.md: paths are logged as a shape. The sync error path logs the
      // exception object, so its `toString` is the leak surface.
      final writer = SafeVaultFileWriter(
        io: _FaultyIo(_Fault.backupPermissionDenied),
      );
      final target = await targetFile(const [1]);

      try {
        await writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [2]),
          backupExistingTarget: true,
          operation: 'sync replace from remote',
        );
        fail('the refused backup must abort the write');
      } on SafeVaultBackupUnavailableException catch (error) {
        expect(error.toString(), isNot(contains(target.path)));
        expect(error.toString(), isNot(contains('vault.kdbx')));
      }
    });

    test(
      'a NON-permission backup failure still propagates unchanged',
      () async {
        // The typed error must mean exactly "the OS refused the sibling", not
        // "the backup failed somehow" — a disk error keeps its own diagnosis.
        final writer = SafeVaultFileWriter(io: _FaultyIo(_Fault.backupIoError));
        final target = await targetFile(const [1, 2, 3]);

        await expectLater(
          writer.write(
            targetPath: target.path,
            bytes: Uint8List.fromList(const [9]),
            backupExistingTarget: true,
          ),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.message,
              'message',
              contains('injected: non-permission error on the backup'),
            ),
          ),
        );
        expect(await target.readAsBytes(), [1, 2, 3]);
      },
    );

    test('an unreadable SOURCE vault keeps its own diagnosis instead of the '
        'backup-sibling advice', () async {
      // FINDING-3: wrapping all of createBackup told the user to re-grant
      // folder access when the real cause was an unreadable vault.
      final writer = SafeVaultFileWriter(
        io: _FaultyIo(_Fault.sourceReadPermissionDenied),
      );
      final target = await targetFile(const [1, 2, 3]);

      await expectLater(
        writer.write(
          targetPath: target.path,
          bytes: Uint8List.fromList(const [9]),
          backupExistingTarget: true,
          operation: 'sync replace from remote',
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('the vault itself is unreadable'),
          ),
        ),
      );
      expect(await target.readAsBytes(), [1, 2, 3]);
    });

    test(
      'a path smuggled into the OS message is stripped from the reason',
      () async {
        final writer = SafeVaultFileWriter(
          io: _FaultyIo(_Fault.backupPermissionDeniedWithPathInMessage),
        );
        final target = await targetFile(const [1]);

        try {
          await writer.write(
            targetPath: target.path,
            bytes: Uint8List.fromList(const [2]),
            backupExistingTarget: true,
            operation: 'sync replace from remote',
          );
          fail('the refused backup must abort the write');
        } on SafeVaultBackupUnavailableException catch (error) {
          expect(error.osReason, isNot(contains('secret-vault')));
          expect(error.osReason, contains(_permissionDeniedReason));
        }
      },
    );

    test('a routine save (no backup requested) still degrades and succeeds '
        'under the same refusal', () async {
      // The documented asymmetry, pinned: the sandbox stops the three sync
      // replacements but never a routine vault save.
      final writer = SafeVaultFileWriter(
        io: _FaultyIo(_Fault.tempPermissionDenied),
      );
      final target = await targetFile(const [1, 2, 3]);

      final result = await writer.write(
        targetPath: target.path,
        bytes: Uint8List.fromList(const [7, 7]),
        operation: 'vault save',
      );

      expect(result.atomic, isFalse);
      expect(await target.readAsBytes(), [7, 7]);
    });
  });

  // ===========================================================================
  // T109 — the replace, with a SECOND handle open on the vault.
  //
  // This is the risk the `test-windows` CI job was created for and the one
  // thing the fault seam cannot stand in for, because it is not an injected
  // error: it is the real kernel refusing a real `rename`. `SafeVaultFileWriter`
  // replaces the target with exactly one `rename`, and Win32 `MoveFileEx` onto
  // a target opened WITHOUT `FILE_SHARE_DELETE` fails with ERROR_ACCESS_DENIED
  // where POSIX `rename(2)` succeeds silently.
  //
  // What the open handle stands in for: a second instance of this app holding
  // the vault, or any tool that opened the file without sharing delete. NOT a
  // well-behaved antivirus — a correct scanner opens with `FILE_SHARE_DELETE`
  // precisely so it does not block renames, so this test is STRICTER than a
  // well-behaved AV, not weaker. That makes it a good guard, but it should not
  // be quoted as proof that AV interference is covered.
  //
  // The per-platform outcome is ASSERTED, not merely tolerated. An earlier
  // version accepted either branch, which made it self-fulfilling: if Windows
  // ever stopped refusing — a Dart share-mode change, ReFS, a different runner
  // image — it would take the `replaced` branch and stay green, and the
  // divergence this whole job exists to detect would vanish without ever
  // producing a red. The `RENAME_PROBE` line below is a convenience for reading
  // the log, never the signal.
  //
  // The invariant on top of that is the same on both families and is checked in
  // both branches: the target is its old content, complete, or the new content,
  // complete. A platform that silently truncated, or that swallowed the refusal
  // and reported success, fails here regardless of which branch it took.
  // ===========================================================================
  group('T109 replace while another handle holds the vault open', () {
    /// Runs [body] with a second read handle open on [file], and closes it
    /// before returning. On Windows a leaked handle also blocks `tearDown`'s
    /// directory delete, so the close is in a `finally`.
    Future<T> withOpenHandle<T>(File file, Future<T> Function() body) async {
      final holder = await file.open(mode: FileMode.read);
      try {
        // Force a real kernel handle rather than a lazily-opened one.
        await holder.read(1);
        return await body();
      } finally {
        await holder.close();
      }
    }

    test('the replace takes this platform\'s branch, and the vault survives '
        'either way', () async {
      final writer = SafeVaultFileWriter();
      final target = await targetFile(const [1, 2, 3, 4]);
      final newBytes = Uint8List.fromList(const [9, 9, 9, 9, 9, 9]);

      final (replaced, error) = await withOpenHandle(target, () async {
        try {
          await writer.write(targetPath: target.path, bytes: newBytes);
          return (true, null);
        } on FileSystemException catch (e) {
          return (false, e);
        }
      });

      // A convenience for reading the log, NOT the signal — the assertion
      // below is. Same shape as `GUARD_PROBE` in
      // mobile_file_storage_guard_qa_test.dart.
      // ignore: avoid_print
      print(
        'RENAME_PROBE platform=${Platform.operatingSystem} '
        'replaced=$replaced osError=${error?.osError}',
      );

      expect(
        replaced,
        Platform.isWindows ? isFalse : isTrue,
        reason: Platform.isWindows
            ? 'Windows must REFUSE a rename onto a target another handle holds '
                  'open (ERROR_ACCESS_DENIED). Observing a successful replace '
                  'here means the platform divergence this job exists to catch '
                  'has changed shape — check whether Dart now opens with '
                  'FILE_SHARE_DELETE, or whether the runner filesystem changed. '
                  'Do not relax this to accept both outcomes: that is what made '
                  'the test self-fulfilling. Observed: ${error?.osError}'
            : 'POSIX rename(2) replaces a target that other handles hold open, '
                  'so the save must SUCCEED here. A refusal on POSIX would be a '
                  'real regression in the writer. Observed: ${error?.osError}',
      );

      final after = await target.readAsBytes();
      if (replaced) {
        expect(
          after,
          newBytes,
          reason:
              'The rename reported success, so the vault must hold the FULL '
              'new content. Anything else is a torn write.',
        );
      } else {
        expect(
          after,
          [1, 2, 3, 4],
          reason:
              'The rename was refused (${error?.osError}), so the OLD vault '
              'must survive byte-for-byte. A refused replace that still '
              'damaged the target would be the worst outcome of the three.',
        );
      }

      // True either way: a temp that outlives the call leaks a full plaintext
      // copy of the vault next to it.
      expect(
        tempDir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.tmp'),
        ),
        isEmpty,
        reason: 'the temp must be cleaned up on both paths',
      );
    });

    test('a backup taken while the vault is held open still verifies', () async {
      // `createBackup` READS the target — that is a shared-read operation and
      // must not be affected by another reader on either platform. Pinned
      // because the sync flows take a backup before every replacement, so a
      // regression here would stop cloud sync whenever the vault is open twice.
      final writer = SafeVaultFileWriter();
      final target = await targetFile(const [7, 7, 7]);

      final backupPath = await withOpenHandle(
        target,
        () => writer.createBackup(target.path),
      );

      expect(await File(backupPath).readAsBytes(), [7, 7, 7]);
    });
  });

  // ===========================================================================
  // The platform contract behind every injection above.
  //
  // The two groups before this one are the real killers: they drive the writer
  // with a host-correct permission code and a host-correct non-permission code
  // and assert opposite outcomes, so inverting either side of
  // `_isPermissionDenied` fails the suite ON THE PLATFORM WHERE THAT BRANCH IS
  // LIVE. This group guards the harness itself — the failure mode where both
  // helpers drift onto the same number and the "negative control" quietly stops
  // being negative, which is exactly how the POSIX-only version fooled CI for
  // as long as CI was POSIX-only.
  // ===========================================================================
  group('fault-injection codes match the host platform', () {
    test('the refusal code and the non-refusal code are never the same', () {
      expect(
        _nonPermissionOsError().errorCode,
        isNot(_permissionDeniedOsError().errorCode),
        reason:
            'If these collide the negative control asserts nothing: the same '
            'injected error would be expected to both engage and not engage '
            'the fallback.',
      );
    });

    test('the codes are the ones the production check looks for', () {
      // Mirrors `SafeVaultFileWriter._isPermissionDenied` deliberately: the
      // check is private, so this states the mapping the injections rely on.
      // A change to the production branch that is not reflected here shows up
      // as this test plus the behavioural cases going red together.
      if (Platform.isWindows) {
        expect(_permissionDeniedOsError().errorCode, 5); // ERROR_ACCESS_DENIED
        expect(_nonPermissionOsError().errorCode, isNot(5));
      } else {
        // BOTH spellings, named individually. `anyOf(1, 13)` used to pass
        // against a helper hard-coded to 1, so this axis could not fail.
        expect(_permissionDeniedOsError().errorCode, 1); // EPERM
        expect(_permissionDeniedOsError(alt: true).errorCode, 13); // EACCES
        expect(_nonPermissionOsError().errorCode, isNot(anyOf(1, 13)));
      }
    });
  });
}

/// Stands in for `path_provider` so the PRODUCTION [SafeVaultFileIo
/// .appDirectoryRoot] can be exercised end to end (MEDIUM-1). Same harness
/// as `mobile_file_storage_guard_qa_test.dart`.
class _FixedPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FixedPathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

/// Reports a fixed app-private perimeter; `null` stands in for "no
/// perimeter", which is what the real IO returns on desktop and wherever no
/// plugin binding exists. Also records every [resolveLeafLink] call, so a
/// gate BYPASS (resolving where the gate said not to) is observable even when
/// the two paths would otherwise behave alike.
class _PerimeterIo extends SafeVaultFileIo {
  _PerimeterIo(this.root);

  final String? root;
  final resolveLeafLinkCalls = <String>[];

  @override
  Future<String?> appDirectoryRoot() async => root;

  @override
  String resolveLeafLink(String path) {
    resolveLeafLinkCalls.add(path);
    return super.resolveLeafLink(path);
  }
}

/// Runs the REAL per-platform perimeter classification over a fake documents
/// root, so the desktop and mobile shapes of the same fixture are exercised
/// end to end through [SafeVaultFileWriter.write].
class _ClassifyingIo extends SafeVaultFileIo {
  _ClassifyingIo(this.documentsRoot, this.operatingSystem);

  final String documentsRoot;
  final String operatingSystem;

  var appDirectoryRootCalls = 0;

  @override
  Future<String?> appDirectoryRoot() async {
    appDirectoryRootCalls++;
    return SafeVaultFileIo.isAppPrivateDocumentsRoot(
          documentsRoot,
          operatingSystem,
        )
        ? documentsRoot
        : null;
  }
}

/// Every chmod is refused — stands in for exFAT/FAT32/network mounts.
class _ChmodRefusingIo extends SafeVaultFileIo {
  @override
  Future<void> setPermissionBits(String path, int bits) async {
    throw const FileSystemException('injected: chmod unsupported');
  }
}

/// The temp exclusive-create fails with a non-permission, non-EEXIST error.
class _TempIoErrorIo extends SafeVaultFileIo {
  @override
  Future<void> createExclusive(String path) {
    if (path.endsWith('.tmp')) {
      throw FileSystemException(
        'injected: non-permission error on the temp',
        'temp',
        _nonPermissionOsError(),
      );
    }
    return super.createExclusive(path);
  }
}

/// Deterministic random: replays [values] then repeats the last one forever.
class _SequenceRandom implements Random {
  _SequenceRandom(this.values);

  final List<int> values;
  int _index = 0;

  @override
  int nextInt(int max) {
    final value = values[_index.clamp(0, values.length - 1)];
    _index++;
    return value % max;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

class _RecordingIo extends SafeVaultFileIo {
  final phases = <String>[];
  final renames = <(String, String)>[];
  final deleted = <String>[];

  /// MEDIUM-1: every exclusive-create, in order and WITH its path, so the
  /// FR-9.5 ordering invariant (backup strictly before any target byte is
  /// written) has a killer instead of only being described in a comment.
  final exclusiveCreates = <String>[];
  final chmods = <(String, int)>[];

  @override
  Future<void> createExclusive(String path) {
    phases.add('createExclusive:$path');
    exclusiveCreates.add(path);
    return super.createExclusive(path);
  }

  @override
  Future<void> setPermissionBits(String path, int bits) {
    chmods.add((path, bits));
    return super.setPermissionBits(path, bits);
  }

  @override
  Future<void> writeFull(RandomAccessFile file, Uint8List bytes) {
    phases.add('write');
    return super.writeFull(file, bytes);
  }

  @override
  Future<void> flush(RandomAccessFile file) {
    phases.add('flush');
    return super.flush(file);
  }

  @override
  Future<void> close(RandomAccessFile file) {
    phases.add('close');
    return super.close(file);
  }

  @override
  Future<void> rename(String from, String to) {
    phases.add('rename');
    renames.add((from, to));
    return super.rename(from, to);
  }

  @override
  Future<void> delete(String path) {
    deleted.add(path);
    return super.delete(path);
  }
}

enum _Fault {
  tempPermissionDenied,
  targetFlushAndClose,
  backupCreate,
  backupIoError,
  backupPermissionDenied,
  backupPermissionDeniedAlt,
  backupPermissionDeniedWithPathInMessage,
  sourceReadPermissionDenied,
  backupWrite,
  backupFlush,
  backupVerify,
  shortWrite,
  targetFlush,
  rename,
  shortWriteAndCleanup,
  directorySync,
}

/// Injects exactly one fault; every other operation is the real filesystem.
class _FaultyIo extends _RecordingIo {
  _FaultyIo(this.fault);

  final _Fault fault;
  final _writeTargets = <RandomAccessFile, String>{};

  bool _isBackup(String path) => path.endsWith('.bak');

  @override
  Future<void> createExclusive(String path) {
    if (fault == _Fault.backupCreate && _isBackup(path)) {
      throw const FileSystemException('injected: backup create failure');
    }
    if (fault == _Fault.backupIoError && _isBackup(path)) {
      throw FileSystemException(
        'injected: non-permission error on the backup',
        'backup',
        _nonPermissionOsError(),
      );
    }
    if (fault == _Fault.backupPermissionDeniedWithPathInMessage &&
        _isBackup(path)) {
      // FINDING-4: the guarantee "no path in the reason" must be enforced by
      // the code, not inherited from whatever `strerror` happens to say.
      throw FileSystemException(
        'injected',
        'backup',
        OSError(
          '$_permissionDeniedReason, path = /Users/u/secret-vault.kdbx',
          _permissionDeniedOsError().errorCode,
        ),
      );
    }
    if (fault == _Fault.backupPermissionDeniedAlt && _isBackup(path)) {
      // The SECOND POSIX spelling of a refusal. Keeps `code == 13` in the
      // production check killable; on Windows this is the same code 5 as
      // above, so the live branch is asserted there too.
      throw FileSystemException(
        'injected: sandbox refuses the sibling backup (alt errno)',
        'backup',
        _permissionDeniedOsError(alt: true),
      );
    }
    if (fault == _Fault.backupPermissionDenied && _isBackup(path)) {
      // MEDIUM-2: the sandbox refuses the backup sibling exactly as it
      // refuses the temp one — same shape as `tempPermissionDenied`.
      throw FileSystemException(
        'injected: sandbox refuses the sibling backup',
        'backup',
        _permissionDeniedOsError(),
      );
    }
    if (fault == _Fault.tempPermissionDenied && path.endsWith('.tmp')) {
      // Shape of a macOS-sandbox refusal on a sibling path. Uses the host's
      // primary refusal code (EPERM on POSIX, ERROR_ACCESS_DENIED on Windows);
      // the EACCES spelling is exercised by `backupPermissionDeniedAlt`.
      throw FileSystemException(
        'injected: sandbox refuses the sibling temp',
        'temp',
        _permissionDeniedOsError(),
      );
    }
    return super.createExclusive(path);
  }

  @override
  Future<RandomAccessFile> openWrite(String path) async {
    final raf = await super.openWrite(path);
    _writeTargets[raf] = path;
    return raf;
  }

  @override
  Future<void> writeFull(RandomAccessFile file, Uint8List bytes) {
    final path = _writeTargets[file] ?? '';
    if (fault == _Fault.backupWrite && _isBackup(path)) {
      throw const FileSystemException('injected: backup write failure');
    }
    if ((fault == _Fault.shortWrite || fault == _Fault.shortWriteAndCleanup) &&
        !_isBackup(path)) {
      // Disk-full: only part of the payload reaches the temp.
      return super.writeFull(
        file,
        Uint8List.sublistView(bytes, 0, bytes.length ~/ 2),
      );
    }
    return super.writeFull(file, bytes);
  }

  @override
  Future<void> flush(RandomAccessFile file) {
    final path = _writeTargets[file] ?? '';
    if (fault == _Fault.backupFlush && _isBackup(path)) {
      throw const FileSystemException('injected: backup flush failure');
    }
    if ((fault == _Fault.targetFlush || fault == _Fault.targetFlushAndClose) &&
        !_isBackup(path)) {
      throw const FileSystemException('injected: disk full on flush');
    }
    return super.flush(file);
  }

  @override
  Future<void> close(RandomAccessFile file) async {
    if (fault == _Fault.targetFlushAndClose) {
      // Really close it (no descriptor leak), then fail the way a failing
      // close does.
      await super.close(file);
      throw const FileSystemException('injected: close failure');
    }
    return super.close(file);
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    if (fault == _Fault.sourceReadPermissionDenied && !_isBackup(path)) {
      throw FileSystemException(
        'injected: the vault itself is unreadable',
        'source',
        _permissionDeniedOsError(),
      );
    }
    final bytes = await super.readBytes(path);
    if (fault == _Fault.backupVerify && _isBackup(path)) {
      // Read-back sees corrupt content.
      return Uint8List.fromList(const [0xDE, 0xAD]);
    }
    return bytes;
  }

  @override
  Future<void> rename(String from, String to) {
    if (fault == _Fault.rename && !_isBackup(to)) {
      renames.add((from, to));
      throw const FileSystemException('injected: rename failure');
    }
    return super.rename(from, to);
  }

  @override
  Future<void> delete(String path) {
    if (fault == _Fault.shortWriteAndCleanup) {
      throw const FileSystemException('injected: cleanup failure');
    }
    return super.delete(path);
  }

  @override
  Future<void> syncDirectory(String path) {
    if (fault == _Fault.directorySync) {
      throw const FileSystemException('injected: directory sync failure');
    }
    return super.syncDirectory(path);
  }
}
