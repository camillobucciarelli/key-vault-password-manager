import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/ios_autofill_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_csv_import_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_duplicate_service.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_status.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_conflict.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/connect_google_account_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/disconnect_google_account_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_drive_connection_status_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_selected_key_file_path_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/link_database_to_drive_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/list_drive_remote_files_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/set_database_auto_sync_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/sync_database_now_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_state.dart';

void main() {
  group('VaultState background sync fields', () {
    test('isSyncing defaults to false', () {
      final state = VaultState(databasePath: '/db.kdbx');
      expect(state.isSyncing, isFalse);
    });

    test('isSyncReloadPending defaults to false', () {
      final state = VaultState(databasePath: '/db.kdbx');
      expect(state.isSyncReloadPending, isFalse);
    });

    test('copyWith sets isSyncing', () {
      final state = VaultState(databasePath: '/db.kdbx');
      expect(state.copyWith(isSyncing: true).isSyncing, isTrue);
    });

    test('copyWith sets isSyncReloadPending', () {
      final state = VaultState(databasePath: '/db.kdbx');
      expect(
        state.copyWith(isSyncReloadPending: true).isSyncReloadPending,
        isTrue,
      );
    });

    test('clearSyncReloadPending resets isSyncReloadPending to false', () {
      final state = VaultState(
        databasePath: '/db.kdbx',
        isSyncReloadPending: true,
      );
      expect(
        state.copyWith(clearSyncReloadPending: true).isSyncReloadPending,
        isFalse,
      );
    });

    test('isSyncing change makes states non-equal', () {
      final a = VaultState(databasePath: '/db.kdbx', isSyncing: true);
      final b = VaultState(databasePath: '/db.kdbx', isSyncing: false);
      expect(a, isNot(equals(b)));
    });

    test('isSyncReloadPending change makes states non-equal', () {
      final a = VaultState(databasePath: '/db.kdbx', isSyncReloadPending: true);
      final b = VaultState(
        databasePath: '/db.kdbx',
        isSyncReloadPending: false,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('BackgroundDriveSync event', () {
    test('two instances are equal', () {
      expect(const BackgroundDriveSync(), equals(const BackgroundDriveSync()));
    });
  });

  group('InitializeVault — Drive check deferred', () {
    late _FakeSyncRepo repo;
    late _FakeVaultKdbxService kdbx;
    late VaultBloc bloc;

    setUp(() {
      repo = _FakeSyncRepo()..mapping = _testMapping;
      kdbx = _FakeVaultKdbxService();
      bloc = _makeBloc(repo, kdbx);
    });

    tearDown(() async => bloc.close());

    test(
      'vault loads (loadVault called) without network Drive check during init',
      () async {
        // isConnectedResult is false, but mapping exists.
        // InitializeVault must NOT call isConnected() — if it did,
        // isDriveConnected would be set to false and syncStatus to disconnected.
        // Instead, preload from local mapping sets isDriveLinked: true, syncStatus: idle.
        bloc.add(const InitializeVault());
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(kdbx.loadCallCount, greaterThanOrEqualTo(1));
        expect(bloc.state.isDriveLinked, isTrue);
        expect(bloc.state.syncStatus, equals(DatabaseSyncStatus.idle));
        expect(bloc.state.isLoading, isFalse);
      },
    );
  });

  group('BackgroundDriveSync', () {
    late _FakeSyncRepo repo;
    late _FakeVaultKdbxService kdbx;
    late _FakeIosAutofillSnapshotCoordinator iosAutofill;
    late VaultBloc bloc;

    setUp(() {
      repo = _FakeSyncRepo()
        ..mapping = _testMapping
        ..isConnectedResult = true;
      kdbx = _FakeVaultKdbxService();
      iosAutofill = _FakeIosAutofillSnapshotCoordinator();
      bloc = _makeBloc(repo, kdbx, iosAutofill: iosAutofill);
    });

    tearDown(() async => bloc.close());

    test(
      'emits isSyncing: true then false when connected and linked',
      () async {
        final states = <VaultState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const BackgroundDriveSync());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await sub.cancel();

        expect(states.any((s) => s.isSyncing), isTrue);
        expect(states.last.isSyncing, isFalse);
      },
    );

    test('never emits syncStatus: syncing during background sync', () async {
      final states = <VaultState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const BackgroundDriveSync());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      expect(
        states.any((s) => s.syncStatus == DatabaseSyncStatus.syncing),
        isFalse,
      );
    });

    test('does not emit isSyncing when not connected', () async {
      repo.isConnectedResult = false;
      final states = <VaultState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const BackgroundDriveSync());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      expect(states.any((s) => s.isSyncing), isFalse);
    });

    test('reloads vault after successful sync when not saving', () async {
      // kdbx.loadCallCount starts at 0 (no InitializeVault fired)
      bloc.add(const BackgroundDriveSync());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // _reload is called: loadVault must have been called at least once
      expect(kdbx.loadCallCount, greaterThanOrEqualTo(1));
      expect(bloc.state.isSyncReloadPending, isFalse);
    });

    test('refreshes iOS autofill snapshot after sync reload', () async {
      bloc.add(const BackgroundDriveSync());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(kdbx.loadCallCount, greaterThanOrEqualTo(1));
      expect(iosAutofill.syncCallCount, 1);
    });

    test(
      'refreshes iOS autofill snapshot after deferred sync reload completes',
      () async {
        final operations = <String>[];
        final repo = _FakeSyncRepo()
          ..mapping = _testMapping
          ..isConnectedResult = true;
        final kdbx = _FakeVaultKdbxService(operations: operations);
        final iosAutofill = _FakeIosAutofillSnapshotCoordinator(
          operations: operations,
        );
        final bloc = _makeBloc(repo, kdbx, iosAutofill: iosAutofill);
        addTearDown(bloc.close);

        bloc.add(const InitializeVault());
        await _waitUntil(() => bloc.state.currentGroupId == 'root');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        operations.clear();
        iosAutofill.syncCallCount = 0;

        kdbx.createEntryCompleter = Completer<String>();
        bloc.add(
          const CreateVaultEntry(
            title: 'Example',
            username: 'user',
            password: 'pass',
            url: 'https://example.com',
            notes: '',
          ),
        );
        await _waitUntil(() => bloc.state.isSaving);

        bloc.add(const BackgroundDriveSync());
        await _waitUntil(() => bloc.state.isSyncReloadPending);

        expect(iosAutofill.syncCallCount, 0);

        kdbx.createEntryCompleter!.complete('entry-1');
        await _waitUntil(
          () => !bloc.state.isSaving && !bloc.state.isSyncReloadPending,
        );

        expect(kdbx.loadCallCount, greaterThanOrEqualTo(2));
        expect(iosAutofill.syncCallCount, 1);
        expect(
          operations,
          containsAllInOrder(const [
            'createEntry',
            'loadVault',
            'syncSnapshot',
          ]),
        );
      },
    );

    test('sets isDriveConnected: false silently when auth fails', () async {
      repo.isConnectedResult = false;

      final states = <VaultState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const BackgroundDriveSync());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      // With isConnectedResult: false, refreshSyncState sets isDriveConnected: false
      // No exception, no error message, no popup
      expect(bloc.state.errorMessage, isNull);
      expect(states.any((s) => s.isSyncing), isFalse);
    });
  });

  group('SyncCurrentDatabaseNow', () {
    test('refreshes iOS autofill snapshot after manual sync reload', () async {
      final repo = _FakeSyncRepo()
        ..mapping = _testMapping
        ..isConnectedResult = true;
      final kdbx = _FakeVaultKdbxService();
      final iosAutofill = _FakeIosAutofillSnapshotCoordinator();
      final bloc = _makeBloc(repo, kdbx, iosAutofill: iosAutofill);
      addTearDown(bloc.close);

      bloc.add(const SyncCurrentDatabaseNow());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(kdbx.loadCallCount, greaterThanOrEqualTo(1));
      expect(iosAutofill.syncCallCount, 1);
    });
  });
}

const _kDbPath = '/vault/test.kdbx';

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

final _emptySnapshot = VaultSnapshot(
  rootGroupId: 'root',
  currentGroupId: 'root',
  groups: const [],
  entries: const [],
  allEntries: const [],
);

const _testMapping = DatabaseSyncMapping(
  databasePath: _kDbPath,
  driveFileId: 'file-123',
  driveFileName: 'test.kdbx',
  autoSyncEnabled: true,
);

// --- Fakes ---

class _FakeSecureDataSource implements SecureDataSource {
  @override
  Future<String?> getMasterPassword() async => '';
  @override
  Future<void> saveMasterPassword(String p) async {}
  @override
  Future<void> clearMasterPassword() async {}
}

class _FakeDatabaseRepository implements DatabaseRepository {
  @override
  Future<String?> getSelectedKeyFilePath() async => null;
  @override
  Future<void> saveSelectedDatabasePath(String path) async {}
  @override
  Future<void> saveSelectedKeyFilePath(String? path) async {}
}

class _FakeVaultKdbxService implements VaultKdbxService {
  _FakeVaultKdbxService({List<String>? operations})
    : operations = operations ?? <String>[];

  final List<String> operations;
  int loadCallCount = 0;
  Completer<String>? createEntryCompleter;

  @override
  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async {
    operations.add('loadVault');
    loadCallCount++;
    return _emptySnapshot;
  }

  @override
  Future<String> createEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
    required String title,
    required String username,
    required String entryPassword,
    required String url,
    required String notes,
    List<VaultCustomField> customFields = const [],
  }) async {
    operations.add('createEntry');
    final completer = createEntryCompleter;
    if (completer != null) {
      return completer.future;
    }
    return 'entry-1';
  }

  @override
  Future<List<VaultEntry>> loadRecycleBinEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeIosAutofillSnapshotCoordinator
    extends IosAutofillSnapshotCoordinator {
  _FakeIosAutofillSnapshotCoordinator({List<String>? operations})
    : operations = operations ?? <String>[],
      super(
        getActiveDatabaseUseCase: GetActiveDatabaseUseCase(
          _FakeDatabaseRegistryRepository(),
        ),
        getSelectedKeyFilePathUseCase: GetSelectedKeyFilePathUseCase(
          _FakeDatabaseRepository(),
        ),
        secureDataSource: _FakeSecureDataSource(),
        vaultKdbxService: VaultKdbxService(),
        iosAutofillDataSource: _FakeIosAutofillDataSource(),
      );

  final List<String> operations;
  int syncCallCount = 0;

  @override
  Future<void> syncSnapshot() async {
    operations.add('syncSnapshot');
    syncCallCount++;
  }
}

class _FakeIosAutofillDataSource implements IosAutofillDataSource {
  @override
  Future<void> clearSnapshot() async {}

  @override
  Future<List<Map<String, dynamic>>> readAndClearPendingSaves() async => [];

  @override
  Future<void> saveSnapshot(List<VaultEntry> entries) async {}
}

class _FakeDatabaseRegistryRepository implements DatabaseRegistryRepository {
  @override
  Future<List<DatabaseRecord>> list() async => [];

  @override
  Future<DatabaseRecord?> getById(String databaseId) async => null;

  @override
  Future<DatabaseRecord?> findBySource({
    required DatabaseSourceType sourceType,
    required String sourceRef,
  }) async => null;

  @override
  Future<DatabaseRecord?> findByHash(String fileHash) async => null;

  @override
  Future<void> upsert(DatabaseRecord record) async {}

  @override
  Future<void> remove(String databaseId) async {}

  @override
  Future<void> setActive(String? databaseId) async {}

  @override
  Future<String?> getActive() async => null;
}

class _FakeSyncRepo implements DatabaseSyncRepository {
  DatabaseSyncMapping? mapping;
  bool isConnectedResult = false;
  SyncNowResult syncResult = const SyncNowSuccess();

  @override
  Future<bool> isConnected() async => isConnectedResult;

  @override
  Future<DatabaseSyncMapping?> getMapping(String path) async => mapping;

  @override
  Future<SyncNowResult> syncNow(
    String path, {
    SyncConflictResolution? resolution,
  }) async => syncResult;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> removeMapping(String p) async {}

  @override
  Future<void> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  }) async {}

  @override
  Future<void> setAutoSync(String p, bool e) async {}

  @override
  Future<List<DriveRemoteFile>> listRemoteFiles({String? query}) async => [];

  @override
  Future<Uint8List> downloadRemoteFile(String id) async =>
      throw UnimplementedError();

  @override
  Future<DatabaseSyncMapping> linkDatabaseToDrive({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
  }) async => throw UnimplementedError();
}

VaultBloc _makeBloc(
  _FakeSyncRepo repo,
  _FakeVaultKdbxService kdbx, {
  IosAutofillSnapshotCoordinator? iosAutofill,
}) {
  return VaultBloc(
    databasePath: _kDbPath,
    secureDataSource: _FakeSecureDataSource(),
    getSelectedKeyFilePathUseCase: GetSelectedKeyFilePathUseCase(
      _FakeDatabaseRepository(),
    ),
    vaultKdbxService: kdbx,
    vaultCsvImportService: VaultCsvImportService(),
    vaultDuplicateService: VaultDuplicateService(),
    getDriveConnectionStatusUseCase: GetDriveConnectionStatusUseCase(repo),
    connectGoogleAccountUseCase: ConnectGoogleAccountUseCase(repo),
    disconnectGoogleAccountUseCase: DisconnectGoogleAccountUseCase(repo),
    linkDatabaseToDriveUseCase: LinkDatabaseToDriveUseCase(repo),
    listDriveRemoteFilesUseCase: ListDriveRemoteFilesUseCase(repo),
    syncDatabaseNowUseCase: SyncDatabaseNowUseCase(repo),
    setDatabaseAutoSyncUseCase: SetDatabaseAutoSyncUseCase(repo),
    databaseSyncRepository: repo,
    iosAutofillSnapshotCoordinator: iosAutofill,
  );
}
