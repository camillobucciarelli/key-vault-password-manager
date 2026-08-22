import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/safe_vault_file_writer.dart';
import 'package:path/path.dart' as p;

// =============================================================================
// spec 008 Gate 1 — T108 (collision-safe backup) and T110 (failure injection).
//
// Invariant asserted by EVERY failure case: the target file is either its old
// content, complete, or the new content, complete — never truncated or mixed —
// and no backup file is ever overwritten.
// =============================================================================

void main() {
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
            contains('injected: EIO'),
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
      throw const FileSystemException(
        'injected: EIO',
        'temp',
        OSError('Input/output error', 5),
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
    if (fault == _Fault.tempPermissionDenied && path.endsWith('.tmp')) {
      // Shape of a macOS-sandbox refusal on a sibling path: EACCES.
      throw const FileSystemException(
        'injected: sandbox refuses the sibling temp',
        'temp',
        OSError('Operation not permitted', 1),
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
