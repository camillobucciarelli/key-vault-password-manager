import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_conflict.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/sync_database_now_usecase.dart';

import '../../presentation/coordinators/fake_database_ports.dart';

const _conflict = SyncConflict(
  databasePath: '/db.kdbx',
  remoteFileId: 'remote-1',
  remoteFileName: 'Vault.kdbx',
  localChecksum: 'aaa',
  remoteChecksum: 'bbb',
);

class _RecordingSyncRepository extends FakeDatabaseSyncRepository {
  SyncNowResult result = const SyncNowSuccess();
  final calls = <({String path, SyncConflictResolution? resolution})>[];

  @override
  Future<SyncNowResult> syncNow(
    String databasePath, {
    SyncConflictResolution? resolution,
  }) async {
    calls.add((path: databasePath, resolution: resolution));
    return result;
  }
}

void main() {
  late _RecordingSyncRepository repository;
  late SyncDatabaseNowUseCase useCase;

  setUp(() {
    repository = _RecordingSyncRepository();
    useCase = SyncDatabaseNowUseCase(repository);
  });

  test('blank database path is rejected before touching the repository', () {
    expect(() => useCase(''), throwsArgumentError);
    expect(repository.calls, isEmpty);
  });

  test('conflict result is propagated untouched', () async {
    repository.result = const SyncNowConflict(_conflict);

    final result = await useCase(' /db.kdbx ');

    expect(result, isA<SyncNowConflict>());
    expect((result as SyncNowConflict).conflict, _conflict);
    expect(repository.calls.single.path, '/db.kdbx');
  });

  test('resolution is forwarded to the repository', () async {
    final result = await useCase(
      '/db.kdbx',
      resolution: SyncConflictResolution.keepLocal,
    );

    expect(result, isA<SyncNowSuccess>());
    expect(repository.calls.single, (
      path: '/db.kdbx',
      resolution: SyncConflictResolution.keepLocal,
    ));
  });
}
