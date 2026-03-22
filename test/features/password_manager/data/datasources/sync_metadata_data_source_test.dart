import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';

void main() {
  group('SyncMetadataDataSource', () {
    test('moveMappingPath updates key from old to new path', () async {
      final dataSource = SyncMetadataDataSourceImpl();

      const oldPath = '/tmp/old.kdbx';
      const newPath = '/tmp/new.kdbx';
      await dataSource.upsertMapping(
        const DatabaseSyncMapping(
          databasePath: oldPath,
          driveFileId: 'drive-id',
          driveFileName: 'vault.kdbx',
        ),
      );

      await dataSource.moveMappingPath(
        fromDatabasePath: oldPath,
        toDatabasePath: newPath,
      );

      final oldMapping = await dataSource.getMapping(oldPath);
      final newMapping = await dataSource.getMapping(newPath);

      expect(oldMapping, isNull);
      expect(newMapping, isNotNull);
      expect(newMapping!.databasePath, newPath);
      expect(newMapping.driveFileId, 'drive-id');
    });
  });
}
