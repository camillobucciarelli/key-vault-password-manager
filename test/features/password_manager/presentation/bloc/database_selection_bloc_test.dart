import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/models/database_dedup_result.dart';
import 'package:password_manager/features/password_manager/domain/models/database_import_result.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_state.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';

void main() {
  group('DatabaseSelectionBloc', () {
    late _FakeDatabaseSessionCoordinator coordinator;
    late DatabaseSelectionBloc bloc;

    setUp(() {
      coordinator = _FakeDatabaseSessionCoordinator();
      bloc = DatabaseSelectionBloc(databaseSessionCoordinator: coordinator);
    });

    tearDown(() async {
      await bloc.close();
    });

    test(
      'emits duplicate decision required then success after resolution',
      () async {
        final duplicatePrompt = DatabaseDuplicatePrompt(
          imported: const DatabaseImportResult(
            path: '/tmp/imported.kdbx',
            fileName: 'imported.kdbx',
            fileHash: 'abc123',
            sourceType: DatabaseSourceType.local,
          ),
          existingRecord: DatabaseRecord(
            databaseId: 'db-existing',
            canonicalPath: '/tmp/existing.kdbx',
            displayName: 'existing.kdbx',
            sourceType: DatabaseSourceType.local,
            fileHash: 'abc123',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
          clearCredentials: true,
        );

        coordinator.selectExistingResult = DatabaseSelectionSessionResult(
          status: DatabaseSessionStatus.duplicateDecisionRequired,
          recentDatabasePaths: const ['/tmp/existing.kdbx'],
          message: 'Duplicate found',
          duplicatePrompt: duplicatePrompt,
        );
        coordinator.resolveDuplicateResult =
            const DatabaseSelectionSessionResult(
              status: DatabaseSessionStatus.success,
              path: '/tmp/imported.kdbx',
              recentDatabasePaths: ['/tmp/imported.kdbx', '/tmp/existing.kdbx'],
            );

        final states = <DatabaseSelectionState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(
          const SelectExistingDatabase(
            fileName: 'imported.kdbx',
            selectedPath: '/tmp/imported.kdbx',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.any((s) => s is DatabaseSelectionLoading), isTrue);
        expect(
          states.whereType<DatabaseSelectionDuplicateDecisionRequired>().length,
          1,
        );

        bloc.add(
          const ResolveDuplicateDecision(DatabaseDuplicateResolution.keepBoth),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.whereType<DatabaseSelectionSuccess>().length, 1);
        expect(
          coordinator.lastResolution,
          DatabaseDuplicateResolution.keepBoth,
        );

        await sub.cancel();
      },
    );
  });
}

class _FakeDatabaseSessionCoordinator
    implements DatabaseSessionCoordinatorContract {
  DatabaseSelectionSessionResult selectExistingResult =
      const DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: [],
      );

  DatabaseSelectionSessionResult resolveDuplicateResult =
      const DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: [],
      );

  DatabaseDuplicateResolution? lastResolution;

  @override
  Future<DatabaseSelectionSessionResult> checkInitialDatabase() async {
    return const DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.unselected,
      recentDatabasePaths: [],
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> createNewDatabase({
    required String databaseFileName,
    required String password,
    String? keyFilePath,
    required bool biometricProtectionEnabled,
    required bool generateKeyFile,
    String? generatedKeyFilePath,
  }) async {
    return const DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.unselected,
      recentDatabasePaths: [],
    );
  }

  @override
  Future<bool> hasStoredMasterPassword() async => false;

  @override
  Future<UnlockBootstrapResult> initializeUnlock({
    required String databasePath,
    required bool biometricAvailable,
  }) async {
    return const UnlockBootstrapResult(
      keyFilePath: null,
      biometricRequired: false,
      biometricAvailable: false,
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> openRecentDatabase(String path) async {
    return const DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.unselected,
      recentDatabasePaths: [],
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> removeRecentDatabase({
    required String path,
    required RecentDatabaseRemovalMode mode,
  }) async {
    return const DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.info,
      recentDatabasePaths: [],
      message: 'Removed',
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> resolveDuplicateDecision({
    required DatabaseDuplicatePrompt duplicatePrompt,
    required DatabaseDuplicateResolution decision,
  }) async {
    lastResolution = decision;
    return resolveDuplicateResult;
  }

  @override
  Future<DatabaseSelectionSessionResult> selectDriveDatabaseLocalCopy({
    required String localPath,
    required String remoteFileId,
  }) async {
    return const DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.unselected,
      recentDatabasePaths: [],
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> selectExistingDatabase({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
    bool overwriteExisting = false,
  }) async {
    return selectExistingResult;
  }

  @override
  Future<void> unlockWithManualCredentials({
    required String databasePath,
    required String password,
    required String? keyFilePath,
  }) async {}

  @override
  Future<void> unlockWithStoredCredentials({
    required String databasePath,
    required String? keyFilePath,
  }) async {}

  @override
  Future<void> updateKeyFilePath({
    required String databasePath,
    required String? keyFilePath,
  }) async {}

  @override
  Future<void> updateBiometricProtection({
    required String databasePath,
    required bool enabled,
  }) async {}
}
