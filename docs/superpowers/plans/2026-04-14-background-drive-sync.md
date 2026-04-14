# Background Drive Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vault opens immediately from local file; all Google Drive activity (connection check, token refresh, sync) happens fully in the background after vault entries are visible.

**Architecture:** Remove `_refreshSyncState` from the `InitializeVault` path. Preload Drive state from local metadata (zero network). Add a `BackgroundDriveSync` event that fires after vault is ready, runs the Drive check and sync silently, and reloads vault entries only when no write is in progress.

**Tech Stack:** Flutter BLoC (`flutter_bloc`), `VaultBloc` / `VaultState` / `VaultEvent`, `DatabaseSyncRepository`, `SyncDatabaseNowUseCase`, `GetDriveConnectionStatusUseCase`

---

## File Map

| File | Change |
|---|---|
| `lib/features/password_manager/presentation/bloc/vault/vault_state.dart` | Add `isSyncing`, `isSyncReloadPending` fields + `clearSyncReloadPending` to `copyWith` |
| `lib/features/password_manager/presentation/bloc/vault/vault_event.dart` | Add `BackgroundDriveSync` event class |
| `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart` | Refactor `_onInitializeVault`, add `_preloadDriveStateFromLocalMapping`, `_onBackgroundDriveSync`, `emitSyncingStatus` param to `_performSync`, `clearSyncReloadPending` in `_reload` |
| `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart` | Update `isSyncInProgress` in `_SyncStatusStrip` to include `state.isSyncing` |
| `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart` | Add `isSyncing` to `_syncStatusStripBuildWhen` |
| `test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart` | New test file |

---

## Task 1: Add `isSyncing` and `isSyncReloadPending` to `VaultState`

**Files:**
- Modify: `lib/features/password_manager/presentation/bloc/vault/vault_state.dart`
- Test: `test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
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
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
```

Expected: compile error — `isSyncing` not defined on `VaultState`.

- [ ] **Step 3: Add fields to `VaultState`**

In `lib/features/password_manager/presentation/bloc/vault/vault_state.dart`:

**Constructor** — add after `isLoadingRemoteDriveFiles`:
```dart
this.isSyncing = false,
this.isSyncReloadPending = false,
```

**Field declarations** — add after `final bool isLoadingRemoteDriveFiles;`:
```dart
final bool isSyncing;
final bool isSyncReloadPending;
```

**`copyWith` parameters** — add after `bool? isLoadingRemoteDriveFiles,`:
```dart
bool? isSyncing,
bool? isSyncReloadPending,
bool clearSyncReloadPending = false,
```

**`copyWith` return** — add after `isLoadingRemoteDriveFiles: isLoadingRemoteDriveFiles ?? this.isLoadingRemoteDriveFiles,`:
```dart
isSyncing: isSyncing ?? this.isSyncing,
isSyncReloadPending: clearSyncReloadPending
    ? false
    : isSyncReloadPending ?? this.isSyncReloadPending,
```

**`props` list** — add after `isLoadingRemoteDriveFiles,`:
```dart
isSyncing,
isSyncReloadPending,
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/password_manager/presentation/bloc/vault/vault_state.dart \
        test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
git commit -m "feat: add isSyncing and isSyncReloadPending to VaultState"
```

---

## Task 2: Add `BackgroundDriveSync` event

**Files:**
- Modify: `lib/features/password_manager/presentation/bloc/vault/vault_event.dart`
- Test: `test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart`

- [ ] **Step 1: Write the failing test**

Add to the test file inside `main()`:

```dart
group('BackgroundDriveSync event', () {
  test('two instances are equal', () {
    expect(
      const BackgroundDriveSync(),
      equals(const BackgroundDriveSync()),
    );
  });
});
```

Add the missing import at the top of the test file:

```dart
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
```

Expected: compile error — `BackgroundDriveSync` not defined.

- [ ] **Step 3: Add event class**

Append to `lib/features/password_manager/presentation/bloc/vault/vault_event.dart`:

```dart
class BackgroundDriveSync extends VaultEvent {
  const BackgroundDriveSync();
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/password_manager/presentation/bloc/vault/vault_event.dart \
        test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
git commit -m "feat: add BackgroundDriveSync vault event"
```

---

## Task 3: Add `emitSyncingStatus` parameter to `_performSync`

**Files:**
- Modify: `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart` (`_performSync` only)

- [ ] **Step 1: Update `_performSync` signature**

In `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart`, find `_performSync`. Change:

```dart
Future<void> _performSync(
  Emitter<VaultState> emit, {
  SyncConflictResolution? resolution,
  bool silentIfConflict = false,
}) async {
  if (!state.isDriveConnected || !state.isDriveLinked) {
    return;
  }

  _safeEmit(
    emit,
    state.copyWith(
      syncStatus: DatabaseSyncStatus.syncing,
      clearSyncError: true,
    ),
  );
```

To:

```dart
Future<void> _performSync(
  Emitter<VaultState> emit, {
  SyncConflictResolution? resolution,
  bool silentIfConflict = false,
  bool emitSyncingStatus = true,
}) async {
  if (!state.isDriveConnected || !state.isDriveLinked) {
    return;
  }

  if (emitSyncingStatus) {
    _safeEmit(
      emit,
      state.copyWith(
        syncStatus: DatabaseSyncStatus.syncing,
        clearSyncError: true,
      ),
    );
  }
```

- [ ] **Step 2: Run analyzer**

```bash
flutter analyze lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart
```

Expected: no errors.

- [ ] **Step 3: Run full test suite**

```bash
flutter test
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart
git commit -m "refactor: add emitSyncingStatus param to _performSync"
```

---

## Task 4: Refactor init and add `_onBackgroundDriveSync`

**Files:**
- Modify: `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart`
- Test: `test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart`

- [ ] **Step 1: Write the failing BLoC tests**

Add the following imports at the top of the test file (after existing imports):

```dart
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_csv_import_service.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_status.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/connect_google_account_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/disconnect_google_account_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_drive_connection_status_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_selected_key_file_path_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/link_database_to_drive_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/list_drive_remote_files_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/set_database_auto_sync_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/sync_database_now_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'dart:typed_data';
```

Add fakes and helpers **at the bottom of the file** (outside `main()`):

```dart
const _kDbPath = '/vault/test.kdbx';

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
  int loadCallCount = 0;

  @override
  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async {
    loadCallCount++;
    return _emptySnapshot;
  }

  @override
  Future<List<dynamic>> loadRecycleBinEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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

VaultBloc _makeBloc(_FakeSyncRepo repo, _FakeVaultKdbxService kdbx) {
  return VaultBloc(
    databasePath: _kDbPath,
    secureDataSource: _FakeSecureDataSource(),
    getSelectedKeyFilePathUseCase: GetSelectedKeyFilePathUseCase(
      _FakeDatabaseRepository(),
    ),
    vaultKdbxService: kdbx,
    vaultCsvImportService: VaultCsvImportService(),
    getDriveConnectionStatusUseCase: GetDriveConnectionStatusUseCase(repo),
    connectGoogleAccountUseCase: ConnectGoogleAccountUseCase(repo),
    disconnectGoogleAccountUseCase: DisconnectGoogleAccountUseCase(repo),
    linkDatabaseToDriveUseCase: LinkDatabaseToDriveUseCase(repo),
    listDriveRemoteFilesUseCase: ListDriveRemoteFilesUseCase(repo),
    syncDatabaseNowUseCase: SyncDatabaseNowUseCase(repo),
    setDatabaseAutoSyncUseCase: SetDatabaseAutoSyncUseCase(repo),
    databaseSyncRepository: repo,
  );
}
```

Add the BLoC behaviour tests inside `main()`:

```dart
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

  test('vault loads (loadVault called) without network Drive check during init', () async {
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
  });
});

group('BackgroundDriveSync', () {
  late _FakeSyncRepo repo;
  late _FakeVaultKdbxService kdbx;
  late VaultBloc bloc;

  setUp(() {
    repo = _FakeSyncRepo()
      ..mapping = _testMapping
      ..isConnectedResult = true;
    kdbx = _FakeVaultKdbxService();
    bloc = _makeBloc(repo, kdbx);
  });

  tearDown(() async => bloc.close());

  test('emits isSyncing: true then false when connected and linked', () async {
    final states = <VaultState>[];
    final sub = bloc.stream.listen(states.add);

    bloc.add(const BackgroundDriveSync());
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sub.cancel();

    expect(states.any((s) => s.isSyncing), isTrue);
    expect(states.last.isSyncing, isFalse);
  });

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

  test('sets isDriveConnected: false silently when auth fails', () async {
    repo
      ..isConnectedResult = true
      ..syncResult = const SyncNowSuccess();
    // Simulate isConnected throwing (e.g. token expired)
    // We test the disconnected path via isConnectedResult = false
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
```

Expected: compile errors or test failures — `_onBackgroundDriveSync` and `_preloadDriveStateFromLocalMapping` not yet implemented.

- [ ] **Step 3: Register the `BackgroundDriveSync` handler in the constructor**

In `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart`, inside the constructor after `on<ClearVaultSyncFeedback>(_onClearVaultSyncFeedback);`, add:

```dart
on<BackgroundDriveSync>(_onBackgroundDriveSync);
```

- [ ] **Step 4: Add `_preloadDriveStateFromLocalMapping`**

Add this private method immediately before `_onInitializeVault`:

```dart
Future<void> _preloadDriveStateFromLocalMapping(
  Emitter<VaultState> emit,
) async {
  final mapping = await databaseSyncRepository.getMapping(state.databasePath);
  if (mapping != null) {
    _safeEmit(
      emit,
      state.copyWith(
        isDriveLinked: true,
        linkedDriveFileName: mapping.driveFileName,
        autoSyncEnabled: mapping.autoSyncEnabled,
        lastSyncAt: mapping.lastSyncAt,
        syncStatus: DatabaseSyncStatus.idle,
      ),
    );
  }
}
```

- [ ] **Step 5: Replace `_onInitializeVault` body**

Find the entire `_onInitializeVault` method and replace it with:

```dart
Future<void> _onInitializeVault(
  InitializeVault event,
  Emitter<VaultState> emit,
) async {
  _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
  try {
    _password = await secureDataSource.getMasterPassword() ?? '';
    _keyFilePath = await getSelectedKeyFilePathUseCase();
    await _preloadDriveStateFromLocalMapping(emit);
    await _reload(emit);
    await _loadRecycleBinEntries(emit, isInitialLoad: true);
    add(const BackgroundDriveSync());
    unawaited(androidAutofillCoordinator?.onVaultReady());
  } catch (e, st) {
    logError('Failed to initialize vault.', e, st);
    _safeEmit(
      emit,
      state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to load vault credentials.',
      ),
    );
  }
}
```

- [ ] **Step 6: Add `_onBackgroundDriveSync`**

Add this method after `_onConnectGoogleDrive`:

```dart
Future<void> _onBackgroundDriveSync(
  BackgroundDriveSync event,
  Emitter<VaultState> emit,
) async {
  await _refreshSyncState(emit);

  if (!state.isDriveConnected || !state.isDriveLinked || !state.autoSyncEnabled) {
    return;
  }

  _safeEmit(emit, state.copyWith(isSyncing: true));
  try {
    await _performSync(
      emit,
      silentIfConflict: true,
      emitSyncingStatus: false,
    );

    if (state.syncStatus != DatabaseSyncStatus.conflict) {
      if (!state.isSaving) {
        await _reload(
          emit,
          currentGroupId: state.currentGroupId,
          keepLoadingFlag: false,
        );
      } else {
        _safeEmit(emit, state.copyWith(isSyncReloadPending: true));
      }
    }
  } catch (e, st) {
    logError('Background Drive sync failed.', e, st);
    _safeEmit(emit, state.copyWith(isDriveConnected: false));
  } finally {
    _safeEmit(emit, state.copyWith(isSyncing: false));
  }
}
```

- [ ] **Step 7: Run tests**

```bash
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
```

Expected: all BLoC tests pass.

- [ ] **Step 8: Run full test suite**

```bash
flutter test
```

Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart \
        test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
git commit -m "feat: defer Drive sync to background after vault init"
```

---

## Task 5: Clear `isSyncReloadPending` on every `_reload`

**Files:**
- Modify: `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart` (`_reload` only)

When `isSyncReloadPending` is `true` (set when background sync updated the file while `isSaving` was true), the flag must clear as soon as the next `_reload` runs — triggered naturally by the user's own save completing.

- [ ] **Step 1: Write the failing test**

Add to the test file inside `main()`:

```dart
group('isSyncReloadPending cleared on reload', () {
  test('clearSyncReloadPending: true in copyWith resets flag (VaultState unit)', () {
    // _reload calls copyWith(clearSyncReloadPending: true).
    // This test verifies the copyWith logic produces the correct transition.
    final pending = VaultState(
      databasePath: '/db.kdbx',
      isSyncReloadPending: true,
    );
    final cleared = pending.copyWith(
      clearSyncReloadPending: true,
      isLoading: false,
    );
    expect(cleared.isSyncReloadPending, isFalse);
    // Passing clearSyncReloadPending: false preserves the flag
    expect(
      pending.copyWith(clearSyncReloadPending: false).isSyncReloadPending,
      isTrue,
    );
  });
});
```

- [ ] **Step 2: Run test**

```bash
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
```

Expected: passes (Task 1 already added the `clearSyncReloadPending` logic to `copyWith`). Confirms the VaultState logic is correct before wiring it into `_reload`.

- [ ] **Step 3: Add `clearSyncReloadPending: true` to `_reload`**

In `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart`, find the `_safeEmit` inside `_reload` that emits the loaded snapshot (lines ~816–835). It currently reads:

```dart
_safeEmit(
  emit,
  state.copyWith(
    isLoading: false,
    isSaving: false,
    rootGroupId: snapshot.rootGroupId,
    currentGroupId: snapshot.currentGroupId,
    groups: snapshot.groups,
    entries: snapshot.entries,
    allEntries: snapshot.allEntries,
    visibleEntries: _computeVisibleEntries(
      entries: snapshot.allEntries,
      searchQuery: state.searchQuery,
      sortBy: state.sortBy,
    ),
    expandedGroupIds: normalizedExpanded,
    clearError: true,
    clearInfo: true,
  ),
);
```

Add `clearSyncReloadPending: true,` before `clearError: true,`:

```dart
_safeEmit(
  emit,
  state.copyWith(
    isLoading: false,
    isSaving: false,
    rootGroupId: snapshot.rootGroupId,
    currentGroupId: snapshot.currentGroupId,
    groups: snapshot.groups,
    entries: snapshot.entries,
    allEntries: snapshot.allEntries,
    visibleEntries: _computeVisibleEntries(
      entries: snapshot.allEntries,
      searchQuery: state.searchQuery,
      sortBy: state.sortBy,
    ),
    expandedGroupIds: normalizedExpanded,
    clearSyncReloadPending: true,
    clearError: true,
    clearInfo: true,
  ),
);
```

- [ ] **Step 4: Run full test suite**

```bash
flutter test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart \
        test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
git commit -m "feat: clear isSyncReloadPending on vault reload"
```

---

## Task 6: Update `_SyncStatusStrip` UI

**Files:**
- Modify: `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart`
- Modify: `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart`

Background sync never sets `syncStatus: syncing`, so the existing "sync in progress" indicator in the strip would not fire. This task wires `state.isSyncing` into the same indicator.

- [ ] **Step 1: Update `isSyncInProgress` in `_SyncStatusStrip`**

In `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart`, find:

```dart
final isSyncInProgress = state.syncStatus == DatabaseSyncStatus.syncing;
```

Replace with:

```dart
final isSyncInProgress =
    state.syncStatus == DatabaseSyncStatus.syncing || state.isSyncing;
```

- [ ] **Step 2: Add `isSyncing` to `_syncStatusStripBuildWhen`**

In `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart`, find:

```dart
bool _syncStatusStripBuildWhen(VaultState previous, VaultState current) {
  return previous.databasePath != current.databasePath ||
      previous.isDriveConnected != current.isDriveConnected ||
      previous.isDriveLinked != current.isDriveLinked ||
      previous.linkedDriveFileName != current.linkedDriveFileName ||
      previous.syncStatus != current.syncStatus ||
      previous.lastSyncAt != current.lastSyncAt ||
      previous.autoSyncEnabled != current.autoSyncEnabled;
}
```

Replace with:

```dart
bool _syncStatusStripBuildWhen(VaultState previous, VaultState current) {
  return previous.databasePath != current.databasePath ||
      previous.isDriveConnected != current.isDriveConnected ||
      previous.isDriveLinked != current.isDriveLinked ||
      previous.linkedDriveFileName != current.linkedDriveFileName ||
      previous.syncStatus != current.syncStatus ||
      previous.lastSyncAt != current.lastSyncAt ||
      previous.autoSyncEnabled != current.autoSyncEnabled ||
      previous.isSyncing != current.isSyncing;
}
```

- [ ] **Step 3: Run analyzer**

```bash
flutter analyze lib/features/password_manager/presentation/screens/vault/
```

Expected: no errors.

- [ ] **Step 4: Run full test suite**

```bash
flutter test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart \
        lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart
git commit -m "feat: show background sync activity in Drive strip UI"
```

---

## Task 7: Smoke test on device

- [ ] **Run app**

```bash
flutter run
```

- [ ] **Vault opens immediately**

1. Open app with a vault that has Google Drive linked and autoSync enabled.
2. After entering master password, vault entries appear without any loading delay from Drive.
3. A moment later the sync icon in the Drive strip briefly shows "in progress" (`isSyncing: true`).
4. Icon settles to idle/synced state — no `syncStatus: syncing` banner flashes.

- [ ] **Manual sync still works**

Tap the sync button → `syncStatus: syncing` indicator appears (old behaviour preserved).

- [ ] **Network off scenario**

Disable device network, open vault → entries appear immediately, Drive icon shows disconnected, no error popup.

- [ ] **Final test run**

```bash
flutter test
```

Expected: all pass.
