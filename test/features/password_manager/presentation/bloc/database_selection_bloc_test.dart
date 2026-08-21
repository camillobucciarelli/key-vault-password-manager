import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/models/create_database_step.dart';
import 'package:password_manager/features/password_manager/domain/models/database_dedup_result.dart';
import 'package:password_manager/features/password_manager/domain/models/database_import_result.dart';
import 'package:password_manager/features/password_manager/domain/models/database_import_transaction.dart';
import 'package:password_manager/features/password_manager/domain/usecases/create_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/resolve_database_duplicate_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/unlock_database_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_state.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';

import '../coordinators/fake_database_ports.dart';

void main() {
  group('DatabaseSelectionBloc', () {
    late FakeDatabaseFileRepository fileRepository;
    late FakeDatabaseSessionRepository sessionRepository;
    late FakeDatabaseRegistryRepository registryRepository;
    late FakeDatabaseSecurityRepository securityRepository;
    late FakeDatabaseSyncRepository syncRepository;
    late DatabaseSessionCoordinator coordinator;
    late DatabaseSelectionBloc bloc;

    setUp(() {
      fileRepository = FakeDatabaseFileRepository();
      sessionRepository = FakeDatabaseSessionRepository();
      registryRepository = FakeDatabaseRegistryRepository();
      securityRepository = FakeDatabaseSecurityRepository();
      syncRepository = FakeDatabaseSyncRepository();
      coordinator = DatabaseSessionCoordinator(
        sessionSecretHolder: SessionSecretHolder(),
        databaseFileRepository: fileRepository,
        databaseSessionRepository: sessionRepository,
        databaseRegistryRepository: registryRepository,
        databaseSecurityRepository: securityRepository,
        databaseSyncRepository: syncRepository,
        getActiveDatabaseUseCase: GetActiveDatabaseUseCase(registryRepository),
        resolveDatabaseDuplicateUseCase: ResolveDatabaseDuplicateUseCase(
          registryRepository,
        ),
        unlockDatabaseUseCase: UnlockDatabaseUseCase(),
        createDatabaseUseCase: CreateDatabaseUseCase(
          databaseFileRepository: fileRepository,
        ),
      );
      bloc = DatabaseSelectionBloc(databaseSessionCoordinator: coordinator);
    });

    tearDown(() async {
      await bloc.close();
    });

    test(
      'emits duplicate decision required then success after resolution',
      () async {
        fileRepository.existingPaths.addAll([
          '/tmp/imported.kdbx',
          '/tmp/existing.kdbx',
        ]);
        fileRepository.stageResult = const StagedDatabaseImport(
          imported: DatabaseImportResult(
            path: '/tmp/imported.kdbx',
            fileName: 'imported.kdbx',
            fileHash: 'abc123',
            sourceType: DatabaseSourceType.local,
          ),
          preferredFileName: 'imported.kdbx',
        );
        registryRepository.records = [
          DatabaseRecord(
            databaseId: 'db-existing',
            canonicalPath: '/tmp/existing.kdbx',
            displayName: 'existing.kdbx',
            sourceType: DatabaseSourceType.local,
            fileHash: 'abc123',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ];

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
        expect(registryRepository.records, hasLength(2));

        await sub.cancel();
      },
    );

    test('emits success for initial active database', () async {
      fileRepository.existingPaths.addAll(['/tmp/a.kdbx', '/tmp/b.kdbx']);
      registryRepository.records = [
        DatabaseRecord(
          databaseId: 'db-a',
          canonicalPath: '/tmp/a.kdbx',
          displayName: 'a.kdbx',
          sourceType: DatabaseSourceType.local,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          lastOpenedAt: DateTime(2026, 1),
        ),
        DatabaseRecord(
          databaseId: 'db-b',
          canonicalPath: '/tmp/b.kdbx',
          displayName: 'b.kdbx',
          sourceType: DatabaseSourceType.local,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          lastOpenedAt: DateTime(2026, 2),
        ),
      ];
      registryRepository.activeId = 'db-b';

      final states = <DatabaseSelectionState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(CheckInitialDatabase());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(states.any((s) => s is DatabaseSelectionLoading), isTrue);
      final success = states.whereType<DatabaseSelectionSuccess>().single;
      expect(success.path, '/tmp/b.kdbx');
      expect(
        success.items.map((item) => item.canonicalPath),
        containsAll(['/tmp/a.kdbx', '/tmp/b.kdbx']),
      );

      await sub.cancel();
    });

    test(
      'CreateDatabaseStep wizard advances only with valid facts and never '
      'carries a password in state.toString()',
      () async {
        final states = <DatabaseSelectionState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const StartCreateDatabaseFlow());
        bloc.add(const AdvanceCreateDatabaseStep(fieldsNonEmpty: false));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final steps = states.whereType<DatabaseSelectionCreateStep>().toList();
        expect(steps.first.step, CreateDatabaseStep.nameAndStorage);
        // Empty fields must not advance the step.
        expect(steps.last.step, CreateDatabaseStep.nameAndStorage);

        bloc.add(const AdvanceCreateDatabaseStep(fieldsNonEmpty: true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          states.whereType<DatabaseSelectionCreateStep>().last.step,
          CreateDatabaseStep.masterPassword,
        );

        bloc.add(const GoBackCreateDatabaseStep());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          states.whereType<DatabaseSelectionCreateStep>().last.step,
          CreateDatabaseStep.nameAndStorage,
        );

        for (final state in states) {
          expect(state.toString(), isNot(contains('super-secret-password')));
        }

        await sub.cancel();
      },
    );
  });
}
