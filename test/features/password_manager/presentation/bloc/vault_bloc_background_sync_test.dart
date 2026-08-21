import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_csv_import_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_duplicate_service.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_status.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_account_summary.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_conflict.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_state.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/apple_autofill_v2_coordinator.dart';

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

  group('Apple autofill lifecycle', () {
    test('publishes after vault is loaded', () async {
      final repo = _FakeSyncRepo()..mapping = _testMapping;
      final kdbx = _FakeVaultKdbxService();
      final appleAutofill = _FakeAppleAutofillV2Coordinator();
      final bloc = _makeBloc(
        repo,
        kdbx,
        appleAutofillV2Coordinator: appleAutofill,
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await _waitUntil(() => appleAutofill.publishCallCount > 0);

      expect(appleAutofill.lastDatabasePath, _kDbPath);
      expect(appleAutofill.lastEntries, _emptySnapshot.allEntries);
    });
  });

  group('Apple autofill pending associations', () {
    test('confirm empty URL sets URL and clears pending', () async {
      final entry = _entry(url: '');
      final kdbx = _FakeVaultKdbxService()
        ..snapshot = _snapshotWithEntry(entry);
      final pending = _pendingAssociation(
        serviceIdentifierType: 'url',
        serviceIdentifierValue: 'https://Example.com/login?x=1#frag',
      );
      final appleAutofill = _FakeAppleAutofillV2Coordinator()
        ..pendingAssociations = [pending];
      final bloc = _makeBloc(
        _FakeSyncRepo(),
        kdbx,
        appleAutofillV2Coordinator: appleAutofill,
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await _waitUntil(
        () => bloc.state.pendingAppleAutofillAssociations.length == 1,
      );

      bloc.add(ConfirmAppleAutofillPendingAssociation(pending.id));
      await _waitUntil(
        () =>
            kdbx.updateCallCount == 1 &&
            appleAutofill.clearPendingCallCount == 1 &&
            bloc.state.pendingAppleAutofillAssociations.isEmpty,
      );

      expect(kdbx.lastUpdatedEntryId, entry.id);
      expect(kdbx.lastUpdatedTitle, entry.title);
      expect(kdbx.lastUpdatedUsername, entry.username);
      expect(kdbx.lastUpdatedUrl, 'https://example.com');
      expect(kdbx.lastUpdatedNotes, entry.notes);
      expect(kdbx.lastUpdatedCustomFields, isEmpty);
      expect(appleAutofill.lastClearedPendingIds, [pending.id]);
    });

    test('confirm existing URL adds KPH URL and preserves URL', () async {
      final entry = _entry(
        url: 'https://existing.example/login',
        customFields: const [VaultCustomField(key: 'note', value: 'keep')],
      );
      final kdbx = _FakeVaultKdbxService()
        ..snapshot = _snapshotWithEntry(entry);
      final pending = _pendingAssociation(
        serviceIdentifierType: 'domain',
        serviceIdentifierValue: 'Example.com/path?x=1#frag',
      );
      final appleAutofill = _FakeAppleAutofillV2Coordinator()
        ..pendingAssociations = [pending];
      final bloc = _makeBloc(
        _FakeSyncRepo(),
        kdbx,
        appleAutofillV2Coordinator: appleAutofill,
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await _waitUntil(
        () => bloc.state.pendingAppleAutofillAssociations.length == 1,
      );

      bloc.add(ConfirmAppleAutofillPendingAssociation(pending.id));
      await _waitUntil(
        () =>
            kdbx.updateCallCount == 1 &&
            appleAutofill.clearPendingCallCount == 1 &&
            bloc.state.pendingAppleAutofillAssociations.isEmpty,
      );

      expect(kdbx.lastUpdatedUrl, entry.url);
      expect(kdbx.lastUpdatedCustomFields, [
        const VaultCustomField(key: 'note', value: 'keep'),
        const VaultCustomField(key: 'KPH: URL', value: 'example.com'),
      ]);
      expect(appleAutofill.lastClearedPendingIds, [pending.id]);
    });

    test('confirm Android package adds KPH androidPackage', () async {
      final entry = _entry(
        url: 'https://existing.example/login',
        customFields: const [VaultCustomField(key: 'note', value: 'keep')],
      );
      final kdbx = _FakeVaultKdbxService()
        ..snapshot = _snapshotWithEntry(entry);
      final pending = _pendingAssociation(
        serviceIdentifierType: 'androidPackage',
        serviceIdentifierValue:
            'androidapp://Com.Example.App/path?token=secret#frag',
      );
      final appleAutofill = _FakeAppleAutofillV2Coordinator()
        ..pendingAssociations = [pending];
      final bloc = _makeBloc(
        _FakeSyncRepo(),
        kdbx,
        appleAutofillV2Coordinator: appleAutofill,
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await _waitUntil(
        () => bloc.state.pendingAppleAutofillAssociations.length == 1,
      );

      bloc.add(ConfirmAppleAutofillPendingAssociation(pending.id));
      await _waitUntil(
        () =>
            kdbx.updateCallCount == 1 &&
            appleAutofill.clearPendingCallCount == 1 &&
            bloc.state.pendingAppleAutofillAssociations.isEmpty,
      );

      expect(kdbx.lastUpdatedUrl, entry.url);
      expect(kdbx.lastUpdatedCustomFields, [
        const VaultCustomField(key: 'note', value: 'keep'),
        const VaultCustomField(
          key: 'KPH: androidPackage',
          value: 'com.example.app',
        ),
      ]);
      expect(appleAutofill.lastClearedPendingIds, [pending.id]);
    });

    test('confirm iOS bundle adds sanitized KPH iosBundle', () async {
      final entry = _entry(
        url: 'https://existing.example/login',
        customFields: const [VaultCustomField(key: 'note', value: 'keep')],
      );
      final kdbx = _FakeVaultKdbxService()
        ..snapshot = _snapshotWithEntry(entry);
      final pending = _pendingAssociation(
        serviceIdentifierType: 'bundleId',
        serviceIdentifierValue:
            'iosbundleid://Com.Example.Ios/path?token=secret#frag',
        platform: 'ios',
      );
      final appleAutofill = _FakeAppleAutofillV2Coordinator()
        ..pendingAssociations = [pending];
      final bloc = _makeBloc(
        _FakeSyncRepo(),
        kdbx,
        appleAutofillV2Coordinator: appleAutofill,
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await _waitUntil(
        () => bloc.state.pendingAppleAutofillAssociations.length == 1,
      );

      bloc.add(ConfirmAppleAutofillPendingAssociation(pending.id));
      await _waitUntil(
        () =>
            kdbx.updateCallCount == 1 &&
            appleAutofill.clearPendingCallCount == 1 &&
            bloc.state.pendingAppleAutofillAssociations.isEmpty,
      );

      expect(kdbx.lastUpdatedUrl, entry.url);
      expect(kdbx.lastUpdatedCustomFields, [
        const VaultCustomField(key: 'note', value: 'keep'),
        const VaultCustomField(key: 'KPH: iosBundle', value: 'com.example.ios'),
      ]);
      expect(
        kdbx.lastUpdatedCustomFields.toString(),
        isNot(contains('token=secret')),
      );
      expect(appleAutofill.lastClearedPendingIds, [pending.id]);
    });

    test(
      'confirm duplicate platform association only clears pending',
      () async {
        final entry = _entry(
          url: 'https://existing.example/login',
          customFields: const [
            VaultCustomField(
              key: 'KPH: androidPackage',
              value: 'com.example.app',
            ),
          ],
        );
        final kdbx = _FakeVaultKdbxService()
          ..snapshot = _snapshotWithEntry(entry);
        final pending = _pendingAssociation(
          serviceIdentifierType: 'androidPackage',
          serviceIdentifierValue: 'Com.Example.App',
          platform: 'android',
        );
        final appleAutofill = _FakeAppleAutofillV2Coordinator()
          ..pendingAssociations = [pending];
        final bloc = _makeBloc(
          _FakeSyncRepo(),
          kdbx,
          appleAutofillV2Coordinator: appleAutofill,
        );
        addTearDown(bloc.close);

        bloc.add(const InitializeVault());
        await _waitUntil(
          () => bloc.state.pendingAppleAutofillAssociations.length == 1,
        );

        bloc.add(ConfirmAppleAutofillPendingAssociation(pending.id));
        await _waitUntil(
          () =>
              appleAutofill.clearPendingCallCount == 1 &&
              bloc.state.pendingAppleAutofillAssociations.isEmpty,
        );

        expect(kdbx.updateCallCount, 0);
        expect(appleAutofill.lastClearedPendingIds, [pending.id]);
      },
    );

    test('reject clears pending and does not update', () async {
      final entry = _entry(url: '');
      final kdbx = _FakeVaultKdbxService()
        ..snapshot = _snapshotWithEntry(entry);
      final pending = _pendingAssociation();
      final appleAutofill = _FakeAppleAutofillV2Coordinator()
        ..pendingAssociations = [pending];
      final bloc = _makeBloc(
        _FakeSyncRepo(),
        kdbx,
        appleAutofillV2Coordinator: appleAutofill,
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await _waitUntil(
        () => bloc.state.pendingAppleAutofillAssociations.length == 1,
      );

      bloc.add(RejectAppleAutofillPendingAssociation(pending.id));
      await _waitUntil(
        () =>
            appleAutofill.clearPendingCallCount == 1 &&
            bloc.state.pendingAppleAutofillAssociations.isEmpty,
      );

      expect(kdbx.updateCallCount, 0);
      expect(appleAutofill.lastClearedPendingIds, [pending.id]);
    });
  });

  group('InitializeVault — session secret (spec-011 FR-1/FR-2)', () {
    test('an absent session secret fails with the locked-state error and '
        'never opens the vault with an empty password', () async {
      final repo = _FakeSyncRepo();
      final kdbx = _FakeVaultKdbxService();
      // Holder deliberately left empty: session is locked.
      final bloc = _makeBloc(
        repo,
        kdbx,
        sessionSecretHolder: SessionSecretHolder(),
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(bloc.state.errorMessage, 'Unable to load vault credentials.');
      expect(bloc.state.isLoading, isFalse);
      expect(kdbx.loadCallCount, 0);
    });

    test('a populated session secret is used to load the vault', () async {
      final repo = _FakeSyncRepo();
      final kdbx = _FakeVaultKdbxService();
      final bloc = _makeBloc(
        repo,
        kdbx,
        sessionSecretHolder: SessionSecretHolder()..set('pw'),
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(bloc.state.errorMessage, isNull);
      expect(kdbx.loadCallCount, greaterThanOrEqualTo(1));
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
    late VaultBloc bloc;

    setUp(() {
      repo = _FakeSyncRepo()
        ..mapping = _testMapping
        ..isConnectedResult = true;
      kdbx = _FakeVaultKdbxService();
      bloc = _makeBloc(repo, kdbx);
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

    test('runs deferred sync reload after save completes', () async {
      final operations = <String>[];
      final repo = _FakeSyncRepo()
        ..mapping = _testMapping
        ..isConnectedResult = true;
      final kdbx = _FakeVaultKdbxService(operations: operations);
      final bloc = _makeBloc(repo, kdbx);
      addTearDown(bloc.close);

      bloc.add(const InitializeVault());
      await _waitUntil(() => bloc.state.currentGroupId == 'root');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      operations.clear();

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

      kdbx.createEntryCompleter!.complete('entry-1');
      await _waitUntil(
        () => !bloc.state.isSaving && !bloc.state.isSyncReloadPending,
      );

      expect(kdbx.loadCallCount, greaterThanOrEqualTo(2));
      expect(
        operations,
        containsAllInOrder(const ['createEntry', 'loadVault']),
      );
    });

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
    test('reloads vault after manual sync', () async {
      final repo = _FakeSyncRepo()
        ..mapping = _testMapping
        ..isConnectedResult = true;
      final kdbx = _FakeVaultKdbxService();
      final bloc = _makeBloc(repo, kdbx);
      addTearDown(bloc.close);

      bloc.add(const SyncCurrentDatabaseNow());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(kdbx.loadCallCount, greaterThanOrEqualTo(1));
    });

    // spec-005 T7 non-negotiable: offline is derived ONLY from a
    // connection-level failure, never from an HTTP error status.
    test(
      'SocketException sets isOffline, leaves syncStatus alone (not error)',
      () async {
        // autoSyncEnabled:false so InitializeVault's own BackgroundDriveSync
        // cycle never calls `_performSync` itself — otherwise it races the
        // explicit `SyncCurrentDatabaseNow` under test against this same
        // always-throwing fake.
        final repo = _FakeSyncRepo()
          ..mapping = _testMapping.copyWith(autoSyncEnabled: false)
          ..isConnectedResult = true
          ..syncNowError = const SocketException('Failed host lookup');
        final kdbx = _FakeVaultKdbxService();
        final bloc = _makeBloc(repo, kdbx);
        addTearDown(bloc.close);

        bloc.add(const InitializeVault());
        await _waitUntil(
          () => bloc.state.isDriveConnected && bloc.state.isDriveLinked,
        );

        bloc.add(const SyncCurrentDatabaseNow());
        await _waitUntil(() => bloc.state.isOffline);

        expect(bloc.state.isOffline, isTrue);
        expect(
          bloc.state.syncStatus,
          isNot(DatabaseSyncStatus.error),
          reason: 'offline must not be reported as the generic error status',
        );
      },
    );

    test(
      'a non-network error (HTTP-status-like) sets syncStatus.error, not isOffline',
      () async {
        final repo = _FakeSyncRepo()
          ..mapping = _testMapping.copyWith(autoSyncEnabled: false)
          ..isConnectedResult = true
          ..syncNowError = Exception('HTTP 500 Internal Server Error');
        final kdbx = _FakeVaultKdbxService();
        final bloc = _makeBloc(repo, kdbx);
        addTearDown(bloc.close);

        bloc.add(const InitializeVault());
        await _waitUntil(
          () => bloc.state.isDriveConnected && bloc.state.isDriveLinked,
        );

        bloc.add(const SyncCurrentDatabaseNow());
        await _waitUntil(
          () => bloc.state.syncStatus == DatabaseSyncStatus.error,
        );

        expect(bloc.state.syncStatus, DatabaseSyncStatus.error);
        expect(
          bloc.state.isOffline,
          isFalse,
          reason: 'a transient server error must never look like "offline"',
        );
      },
    );
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

VaultEntry _entry({
  String id = 'entry-1',
  String url = '',
  List<VaultCustomField> customFields = const [],
}) {
  return VaultEntry(
    id: id,
    groupId: 'root',
    title: 'Example',
    username: 'user',
    password: 'secret',
    url: url,
    notes: 'notes',
    customFields: customFields,
  );
}

VaultSnapshot _snapshotWithEntry(VaultEntry entry) {
  return VaultSnapshot(
    rootGroupId: 'root',
    currentGroupId: 'root',
    groups: const [],
    entries: [entry],
    allEntries: [entry],
  );
}

AppleAutofillV2PendingAssociation _pendingAssociation({
  String id = 'pending-1',
  String entryId = 'entry-1',
  String serviceIdentifierType = 'url',
  String serviceIdentifierValue = 'https://example.com',
  String? platform,
}) {
  return AppleAutofillV2PendingAssociation(
    id: id,
    databaseId: 'database-id',
    entryId: entryId,
    serviceIdentifierType: serviceIdentifierType,
    serviceIdentifierValue: serviceIdentifierValue,
    displayService: serviceIdentifierValue,
    createdAtEpochMs: 1,
    platform: platform,
  );
}

VaultSnapshot _snapshotReplacingEntry(
  VaultSnapshot snapshot, {
  required String entryId,
  required String title,
  required String username,
  required String password,
  required String url,
  required String notes,
  required List<VaultCustomField> customFields,
}) {
  VaultEntry replace(VaultEntry entry) {
    if (entry.id != entryId) {
      return entry;
    }
    return VaultEntry(
      id: entry.id,
      groupId: entry.groupId,
      title: title,
      username: username,
      password: password,
      url: url,
      notes: notes,
      customFields: List<VaultCustomField>.of(customFields),
      attachments: entry.attachments,
      otpUri: entry.otpUri,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
      lastPasswordChangedAt: entry.lastPasswordChangedAt,
    );
  }

  return VaultSnapshot(
    rootGroupId: snapshot.rootGroupId,
    currentGroupId: snapshot.currentGroupId,
    groups: snapshot.groups,
    entries: snapshot.entries.map(replace).toList(growable: false),
    allEntries: snapshot.allEntries.map(replace).toList(growable: false),
  );
}

// --- Fakes ---

class _FakeVaultKdbxService implements VaultKdbxService {
  _FakeVaultKdbxService({List<String>? operations})
    : operations = operations ?? <String>[];

  final List<String> operations;
  VaultSnapshot snapshot = _emptySnapshot;
  int loadCallCount = 0;
  int updateCallCount = 0;
  Completer<String>? createEntryCompleter;
  String? lastUpdatedEntryId;
  String? lastUpdatedTitle;
  String? lastUpdatedUsername;
  String? lastUpdatedUrl;
  String? lastUpdatedNotes;
  List<VaultCustomField>? lastUpdatedCustomFields;

  @override
  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async {
    operations.add('loadVault');
    loadCallCount++;
    return snapshot;
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
  Future<void> updateEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String title,
    required String username,
    required String entryPassword,
    required String url,
    required String notes,
    List<VaultCustomField> customFields = const [],
  }) async {
    operations.add('updateEntry');
    updateCallCount += 1;
    lastUpdatedEntryId = entryId;
    lastUpdatedTitle = title;
    lastUpdatedUsername = username;
    lastUpdatedUrl = url;
    lastUpdatedNotes = notes;
    lastUpdatedCustomFields = List<VaultCustomField>.of(customFields);
    snapshot = _snapshotReplacingEntry(
      snapshot,
      entryId: entryId,
      title: title,
      username: username,
      password: entryPassword,
      url: url,
      notes: notes,
      customFields: customFields,
    );
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

class _FakeSyncRepo implements DatabaseSyncRepository {
  DatabaseSyncMapping? mapping;
  bool isConnectedResult = false;
  SyncNowResult syncResult = const SyncNowSuccess();

  /// spec-005 T7: when set, `syncNow` throws this instead of returning
  /// [syncResult] — lets tests exercise `SocketException` (offline) vs any
  /// other error (HTTP-status-like) without a real network stack.
  Object? syncNowError;

  @override
  Future<bool> isConnected() async => isConnectedResult;

  @override
  Future<DatabaseSyncMapping?> getMapping(String path) async => mapping;

  @override
  Future<List<DatabaseSyncMapping>> getAllMappings() async =>
      mapping == null ? const [] : [mapping!];

  @override
  Future<SyncNowResult> syncNow(
    String path, {
    SyncConflictResolution? resolution,
  }) async {
    final error = syncNowError;
    if (error != null) {
      throw error;
    }
    return syncResult;
  }

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

  @override
  Future<DriveAccountSummary> getConnectedAccount() async =>
      DriveAccountSummary.fallback;
}

VaultBloc _makeBloc(
  _FakeSyncRepo repo,
  _FakeVaultKdbxService kdbx, {
  AppleAutofillV2CoordinatorContract appleAutofillV2Coordinator =
      const NoopAppleAutofillV2Coordinator(),
  SessionSecretHolder? sessionSecretHolder,
}) {
  return VaultBloc(
    databasePath: _kDbPath,
    getSelectedKeyFilePath: () async => null,
    sessionSecretHolder:
        sessionSecretHolder ?? (SessionSecretHolder()..set('')),
    vaultKdbxService: kdbx,
    vaultCsvImportService: VaultCsvImportService(),
    vaultDuplicateService: VaultDuplicateService(),
    databaseSyncRepository: repo,
    appleAutofillV2Coordinator: appleAutofillV2Coordinator,
  );
}

class _FakeAppleAutofillV2Coordinator
    implements AppleAutofillV2CoordinatorContract {
  List<AppleAutofillV2PendingAssociation> pendingAssociations = [];
  int publishCallCount = 0;
  int clearCallCount = 0;
  int readPendingCallCount = 0;
  int clearPendingCallCount = 0;
  String? lastDatabasePath;
  List<VaultEntry>? lastEntries;
  List<String>? lastClearedPendingIds;

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    publishCallCount += 1;
    lastDatabasePath = databasePath;
    lastEntries = entries;
  }

  @override
  Future<void> clearCredentials({String? databasePath}) async {
    clearCallCount += 1;
  }

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async {
    readPendingCallCount += 1;
    return List<AppleAutofillV2PendingAssociation>.of(pendingAssociations);
  }

  @override
  Future<void> clearPendingAssociations({List<String>? ids}) async {
    clearPendingCallCount += 1;
    lastClearedPendingIds = ids == null ? null : List<String>.of(ids);
    if (ids == null) {
      pendingAssociations = [];
      return;
    }

    final idSet = ids.toSet();
    pendingAssociations = pendingAssociations
        .where((association) => !idSet.contains(association.id))
        .toList(growable: false);
  }
}
