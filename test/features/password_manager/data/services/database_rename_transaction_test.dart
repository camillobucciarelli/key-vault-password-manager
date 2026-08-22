import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/database_path_mutex.dart';
import 'package:password_manager/features/password_manager/data/services/database_rename_transaction.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';

import 'lock_routing_test_mutexes.dart';

// =============================================================================
// spec 008 Gate 1 T106 — rename transaction.
//
// The transaction must lock the old AND new canonical paths in one
// deterministic acquisition, rename the file and move the sync mapping while
// holding both, and roll the file rename back when the mapping move fails.
// =============================================================================

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rename_transaction_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'successful rename moves file and mapping under one old+new lock',
    () async {
      final mutex = RecordingDatabasePathMutex();
      final sync = _MappingRecorder();
      // Tester finding K3: the mapping move must run WHILE the lock is
      // held. Without this live-depth assertion, re-ordering
      // `moveMappingPath` to after the `withDatabaseLock` block survives
      // every acquisition-shape assertion below.
      sync.onMove = () {
        expect(
          mutex.currentDepth,
          greaterThanOrEqualTo(1),
          reason: 'moveMappingPath ran outside the database lock',
        );
      };
      final transaction = DatabaseRenameTransaction(
        mutex: mutex,
        syncRepository: sync,
      );
      final source = File('${tempDir.path}/old.kdbx');
      await source.writeAsBytes(const [1, 2, 3], flush: true);
      final target = '${tempDir.path}/new.kdbx';

      await transaction.renameDatabase(
        sourcePath: source.path,
        targetPath: target,
      );

      expect(await source.exists(), isFalse);
      expect(await File(target).exists(), isTrue);
      expect(sync.moves, [(source.path, target)]);
      // One single acquisition covering BOTH paths — never two sequential
      // locks, which would open a window between file and mapping.
      expect(mutex.acquisitions, [
        [source.path, target],
      ]);
      expect(mutex.maxDepth, 1);
    },
  );

  test(
    'mapping move failure rolls the file rename back and rethrows',
    () async {
      final sync = _MappingRecorder()..failNextMove = true;
      final transaction = DatabaseRenameTransaction(
        mutex: RecordingDatabasePathMutex(),
        syncRepository: sync,
      );
      final source = File('${tempDir.path}/old.kdbx');
      await source.writeAsBytes(const [7, 8, 9], flush: true);
      final target = '${tempDir.path}/new.kdbx';

      await expectLater(
        transaction.renameDatabase(sourcePath: source.path, targetPath: target),
        throwsException,
      );

      expect(await source.exists(), isTrue);
      expect(await source.readAsBytes(), [7, 8, 9]);
      expect(await File(target).exists(), isFalse);
    },
  );

  test('a refused lock leaves file and mapping untouched', () async {
    final sync = _MappingRecorder();
    final transaction = DatabaseRenameTransaction(
      mutex: RefusingDatabasePathMutex(),
      syncRepository: sync,
    );
    final source = File('${tempDir.path}/old.kdbx');
    await source.writeAsBytes(const [1], flush: true);

    await expectLater(
      () => transaction.renameDatabase(
        sourcePath: source.path,
        targetPath: '${tempDir.path}/new.kdbx',
      ),
      throwsA(isA<LockRefused>()),
    );

    expect(await source.exists(), isTrue);
    expect(sync.moves, isEmpty);
  });

  test('inverse concurrent renames through the REAL mutex settle without '
      'deadlock and leave exactly one file', () async {
    // T104 already pins the dedup/sort property on the bare mutex; this is
    // the end-to-end case with the real transaction: A→B racing B→A.
    final mutex = DatabasePathMutex();
    final sync = _MappingRecorder();
    final transaction = DatabaseRenameTransaction(
      mutex: mutex,
      syncRepository: sync,
    );
    final pathA = '${tempDir.path}/a.kdbx';
    final pathB = '${tempDir.path}/b.kdbx';
    await File(pathA).writeAsBytes(const [42], flush: true);

    final results = await Future.wait<Object?>([
      transaction
          .renameDatabase(sourcePath: pathA, targetPath: pathB)
          .then<Object?>((_) => null, onError: (Object e) => e),
      transaction
          .renameDatabase(sourcePath: pathB, targetPath: pathA)
          .then<Object?>((_) => null, onError: (Object e) => e),
    ]).timeout(const Duration(seconds: 10));

    // Whichever order the mutex granted, the pair must settle (no
    // deadlock — enforced by the timeout above), at least one direction
    // must succeed, and exactly one spelling of the file must remain.
    expect(results.where((e) => e == null), isNotEmpty);
    final aExists = await File(pathA).exists();
    final bExists = await File(pathB).exists();
    expect(aExists ^ bExists, isTrue);
    expect(await File(aExists ? pathA : pathB).readAsBytes(), [42]);
    // Every successful rename moved its mapping too.
    expect(sync.moves.length, results.where((e) => e == null).length);
  });
}

class _MappingRecorder implements DatabaseSyncRepository {
  final List<(String, String)> moves = [];
  bool failNextMove = false;

  /// K3 hook: invoked on every successful move so tests can assert the move
  /// executes while the lock is held
  /// (see `RecordingDatabasePathMutex.currentDepth`).
  void Function()? onMove;

  @override
  Future<void> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  }) async {
    if (failNextMove) {
      failNextMove = false;
      throw Exception('Mapping move failed.');
    }
    onMove?.call();
    moves.add((fromDatabasePath, toDatabasePath));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed here');
}
