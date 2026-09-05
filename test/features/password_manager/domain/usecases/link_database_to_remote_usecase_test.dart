import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/usecases/link_database_to_remote_usecase.dart';

import '../../presentation/coordinators/fake_database_ports.dart';

class _RecordingSyncRepository extends FakeDatabaseSyncRepository {
  final calls = <({String path, String? id, String? name})>[];

  @override
  Future<DatabaseSyncMapping> linkDatabaseToRemote({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
  }) {
    calls.add((path: databasePath, id: remoteFileId, name: remoteFileName));
    return super.linkDatabaseToRemote(
      databasePath: databasePath,
      remoteFileId: remoteFileId,
      remoteFileName: remoteFileName,
    );
  }
}

void main() {
  late _RecordingSyncRepository repository;
  late LinkDatabaseToRemoteUseCase useCase;

  setUp(() {
    repository = _RecordingSyncRepository();
    useCase = LinkDatabaseToRemoteUseCase(repository);
  });

  test('blank database path is rejected before touching the repository', () {
    expect(
      () => useCase(databasePath: '   ', remoteFileId: 'x'),
      throwsArgumentError,
    );
    expect(repository.calls, isEmpty);
  });

  test(
    'blank remote id means "create new": repository receives null',
    () async {
      await useCase(databasePath: '/db.kdbx', remoteFileId: '  ');

      expect(repository.calls.single.id, isNull);
      expect(repository.calls.single.path, '/db.kdbx');
    },
  );

  test('id and name are trimmed and forwarded; mapping is returned', () async {
    final mapping = await useCase(
      databasePath: ' /db.kdbx ',
      remoteFileId: ' remote-7 ',
      remoteFileName: ' Vault.kdbx ',
    );

    expect(repository.calls.single, (
      path: '/db.kdbx',
      id: 'remote-7',
      name: 'Vault.kdbx',
    ));
    expect(mapping.remoteFileId, 'remote-7');
    expect(mapping.remoteFileName, 'Vault.kdbx');
    expect(repository.mappings['/db.kdbx'], mapping);
  });
}
