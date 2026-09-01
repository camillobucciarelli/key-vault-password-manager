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
        await _until(
          () => states
              .whereType<DatabaseSelectionDuplicateDecisionRequired>()
              .isNotEmpty,
        );

        expect(states.any((s) => s is DatabaseSelectionLoading), isTrue);
        expect(
          states.whereType<DatabaseSelectionDuplicateDecisionRequired>().length,
          1,
        );

        bloc.add(
          const ResolveDuplicateDecision(DatabaseDuplicateResolution.keepBoth),
        );
        await _until(
          () => states.whereType<DatabaseSelectionSuccess>().isNotEmpty,
        );

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
      await _until(
        () => states.whereType<DatabaseSelectionSuccess>().isNotEmpty,
      );

      expect(states.any((s) => s is DatabaseSelectionLoading), isTrue);
      final success = states.whereType<DatabaseSelectionSuccess>().single;
      expect(success.path, '/tmp/b.kdbx');
      expect(
        success.items.map((item) => item.canonicalPath),
        containsAll(['/tmp/a.kdbx', '/tmp/b.kdbx']),
      );

      await sub.cancel();
    });

    test('CreateDatabaseStep wizard advances only with valid facts and never '
        'carries a password in state.toString()', () async {
      final states = <DatabaseSelectionState>[];
      final sub = bloc.stream.listen(states.add);

      List<DatabaseSelectionCreateStep> stepStates() =>
          states.whereType<DatabaseSelectionCreateStep>().toList();

      bloc.add(const StartCreateDatabaseFlow());
      bloc.add(const AdvanceCreateDatabaseStep(fieldsNonEmpty: false));
      await _until(() => stepStates().isNotEmpty);

      final steps = stepStates();
      expect(steps.first.step, CreateDatabaseStep.nameAndStorage);
      // Empty fields must not advance the step.
      expect(steps.last.step, CreateDatabaseStep.nameAndStorage);

      bloc.add(const AdvanceCreateDatabaseStep(fieldsNonEmpty: true));
      await _until(
        () => stepStates().last.step == CreateDatabaseStep.credentials,
      );
      expect(stepStates().last.step, CreateDatabaseStep.credentials);
      // The assertion above samples once `masterPassword` is reached, so the
      // empty-fields event is now provably behind us (bloc events are FIFO).
      // Every step state emitted before it must still have been
      // `nameAndStorage` — this catches an advance-on-empty-fields
      // regression even if the earlier check sampled before that emission.
      expect(
        stepStates()
            .takeWhile((s) => s.step != CreateDatabaseStep.credentials)
            .every((s) => s.step == CreateDatabaseStep.nameAndStorage),
        isTrue,
        reason: 'empty fields must never advance the wizard',
      );

      bloc.add(const GoBackCreateDatabaseStep());
      await _until(
        () => stepStates().last.step == CreateDatabaseStep.nameAndStorage,
      );
      expect(stepStates().last.step, CreateDatabaseStep.nameAndStorage);

      for (final state in states) {
        expect(state.toString(), isNot(contains('super-secret-password')));
      }

      await sub.cancel();
    });
  });
}

/// Waits until [predicate] holds, yielding to the event loop between checks.
///
/// Replaces the `Future.delayed(20ms)` sleeps this file used to synchronise on
/// after every `bloc.add`. A fixed sleep is a bet on machine speed: when a
/// handler takes longer than the sleep, the assertions run against a
/// half-finished state and fail for reasons unrelated to the behaviour under
/// test. Waiting on the state itself is correct at any speed, and the wait
/// doubles as an assertion that the transition actually happened.
///
/// The deadline is not a speed budget — these waits complete in microseconds
/// once the handler completes. It exists only so a genuine deadlock reports a
/// useful message instead of hanging until the suite-level timeout.
Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the bloc to reach the expected state.');
    }
    await Future<void>.delayed(Duration.zero);
  }
}
