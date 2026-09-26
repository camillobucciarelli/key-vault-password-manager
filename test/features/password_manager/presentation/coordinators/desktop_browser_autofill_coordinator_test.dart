import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_passkey_approval_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_passkey.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/passkey_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';

import 'fake_database_ports.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_pending_generation_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/desktop_browser_autofill_coordinator.dart';

void main() {
  _passkeyWriteTests();

  group('DesktopBrowserAutofillCoordinator', () {
    test(
      'publish starts bridge and clear removes all desktop artifacts',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kv-desktop-coordinator-',
        );
        final store = DesktopBrowserAutofillCacheStore(directory: directory);
        final mapper = const DesktopBrowserAutofillMetadataMapper();
        final revealBridge = DesktopBrowserAutofillRevealBridgeService(
          store: store,
          mapper: mapper,
        );
        addTearDown(revealBridge.stop);

        final coordinator = DesktopBrowserAutofillCoordinator(
          store: store,
          mapper: mapper,
          revealBridge: revealBridge,
        );

        await coordinator.publishVault(
          databasePath: '/vaults/example.kdbx',
          entries: const [
            VaultEntry(
              id: 'entry-1',
              groupId: 'root',
              title: 'Example',
              username: 'alice',
              password: 'super-secret',
              url: 'https://example.com',
              notes: 'hidden',
            ),
          ],
        );

        expect(await store.readMetadataCache(), isNotNull);
        expect(await store.readBridgeDescriptor(), isNotNull);
        expect(await store.metadataFile!.exists(), isTrue);
        expect(await store.bridgeDescriptorFile!.exists(), isTrue);

        await coordinator.clearCredentials(
          databasePath: '/vaults/example.kdbx',
        );

        expect(await store.readMetadataCache(), isNull);
        expect(await store.readBridgeDescriptor(), isNull);
        expect(await store.metadataFile!.exists(), isFalse);
        expect(await store.bridgeDescriptorFile!.exists(), isFalse);
      },
    );

    test('failed metadata publish stops previous reveal bridge', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-desktop-coordinator-',
      );
      final store = _FailingWriteStore(directory: directory);
      final mapper = const DesktopBrowserAutofillMetadataMapper();
      final revealBridge = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: mapper,
      );
      addTearDown(revealBridge.stop);

      final coordinator = DesktopBrowserAutofillCoordinator(
        store: store,
        mapper: mapper,
        revealBridge: revealBridge,
      );

      await coordinator.publishVault(
        databasePath: '/vaults/example.kdbx',
        entries: const [
          VaultEntry(
            id: 'entry-1',
            groupId: 'root',
            title: 'Example',
            username: 'alice',
            password: 'old-secret',
            url: 'https://example.com',
            notes: 'hidden',
          ),
        ],
      );
      expect(await store.readBridgeDescriptor(), isNotNull);
      expect(await store.metadataFile!.exists(), isTrue);

      store.failWrites = true;
      await coordinator.publishVault(
        databasePath: '/vaults/example.kdbx',
        entries: const [
          VaultEntry(
            id: 'entry-1',
            groupId: 'root',
            title: 'Example',
            username: 'alice',
            password: 'new-secret',
            url: 'https://example.com',
            notes: 'hidden',
          ),
        ],
      );

      expect(await store.readBridgeDescriptor(), isNull);
      expect(await store.metadataFile!.exists(), isFalse);
    });

    // 009 / B009 — the order is the property, not a comment: lock, database
    // switch, and vault close all route through clearCredentials, and by the
    // time the durable descriptor removal *completes*, the pending generated
    // secrets must already be gone and the generate endpoint already dead.
    // Otherwise a native host holding the old descriptor could still reach a
    // live endpoint (or a live pending record) during the teardown window.
    test('clear paths drop pending secrets and stop the endpoint before the '
        'descriptor removal completes', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-desktop-coordinator-',
      );
      final store = _OrderPinningStore(directory: directory);
      final mapper = const DesktopBrowserAutofillMetadataMapper();
      final pendingGeneration = DesktopBrowserPendingGenerationService();
      final revealBridge = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: mapper,
      );
      addTearDown(revealBridge.stop);
      final coordinator = DesktopBrowserAutofillCoordinator(
        store: store,
        mapper: mapper,
        revealBridge: revealBridge,
        pendingGeneration: pendingGeneration,
      );

      await coordinator.publishVault(
        databasePath: '/vaults/example.kdbx',
        entries: const [
          VaultEntry(
            id: 'entry-1',
            groupId: 'root',
            title: 'Example',
            username: 'alice',
            password: 'super-secret',
            url: 'https://example.com',
            notes: 'hidden',
          ),
        ],
      );
      final descriptor = (await store.readBridgeDescriptor())!;
      pendingGeneration.create(
        databaseId: descriptor.databaseId,
        cacheGeneration: descriptor.cacheGeneration,
        bridgeGeneration: descriptor.bridgeGeneration,
        settingsRevision: 1,
        origin: 'https://example.com',
        password: ['kv', 'order', 'test', 'value'].join('-'),
      );
      expect(pendingGeneration.pendingCount, 1);

      // Arm the probe: it runs inside clearBridgeDescriptor, i.e. strictly
      // before the descriptor removal completes.
      store.probe = () async {
        store.pendingAtDescriptorRemoval = pendingGeneration.pendingCount;
        try {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            descriptor.port,
            timeout: const Duration(seconds: 2),
          );
          socket.destroy();
          store.endpointAliveAtDescriptorRemoval = true;
        } on SocketException {
          store.endpointAliveAtDescriptorRemoval = false;
        }
      };

      await coordinator.clearCredentials(databasePath: '/vaults/example.kdbx');

      expect(store.probeRan, isTrue);
      expect(store.pendingAtDescriptorRemoval, 0);
      expect(store.endpointAliveAtDescriptorRemoval, isFalse);
      expect(await store.readBridgeDescriptor(), isNull);
    });
  });
}

/// Observes the exact moment the durable descriptor is removed and records
/// what is still alive at that point.
class _OrderPinningStore extends DesktopBrowserAutofillCacheStore {
  _OrderPinningStore({required Directory directory})
    : super(directory: directory);

  Future<void> Function()? probe;
  bool probeRan = false;
  int? pendingAtDescriptorRemoval;
  bool? endpointAliveAtDescriptorRemoval;

  @override
  Future<void> clearBridgeDescriptor() async {
    final probe = this.probe;
    if (probe != null) {
      probeRan = true;
      await probe();
    }
    await super.clearBridgeDescriptor();
  }
}

/// Records what the vault write was actually asked to do. The two fields this
/// covers were both dropped on the way in: a key-file vault could not be
/// opened at all, and the relying party's own account identifier was replaced
/// by one of ours.
class _RecordingKdbxService implements VaultKdbxService {
  String? lastKeyFilePath;
  VaultPasskey? lastPasskey;
  Object? error;

  @override
  Future<void> createPasskey({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required VaultPasskey passkey,
    bool replaceExisting = false,
  }) async {
    lastKeyFilePath = keyFilePath;
    lastPasskey = passkey;
    if (error != null) throw error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _passkeyWriteTests() {
  group('spec 023 US3 — the bound passkey writer', () {
    late Directory directory;
    late DesktopBrowserAutofillCacheStore store;
    late DesktopBrowserAutofillRevealBridgeService revealBridge;
    late _RecordingKdbxService kdbx;
    late DesktopPasskeyApprovalService approvals;
    late String databasePath;

    Future<void> publish({Future<String?> Function()? keyFilePath}) async {
      final holder = SessionSecretHolder()..set('secret');
      final coordinator = DesktopBrowserAutofillCoordinator(
        store: store,
        mapper: const DesktopBrowserAutofillMetadataMapper(),
        revealBridge: revealBridge,
        passkeyApprovals: approvals,
        passkeyCoordinator: PasskeyCoordinator(
          vaultKdbxService: kdbx,
          sessionSecretHolder: holder,
          databaseFileRepository: FakeDatabaseFileRepository(),
        ),
        currentKeyFilePath: keyFilePath,
      );
      await coordinator.publishVault(
        databasePath: databasePath,
        entries: const [
          VaultEntry(
            id: 'entry-1',
            groupId: 'root',
            title: 'Example',
            username: 'alice',
            password: 'pw',
            url: 'https://example.com',
            notes: '',
          ),
        ],
      );
    }

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('kv-pk-write-');
      databasePath = '${directory.path}/vault.kdbx';
      await File(databasePath).writeAsBytes(const [1, 2, 3], flush: true);
      store = DesktopBrowserAutofillCacheStore(directory: directory);
      revealBridge = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: const DesktopBrowserAutofillMetadataMapper(),
      );
      kdbx = _RecordingKdbxService();
      approvals = DesktopPasskeyApprovalService();
      addTearDown(revealBridge.stop);
      addTearDown(approvals.dispose);
      addTearDown(() => directory.delete(recursive: true));
    });

    test('forwards the key file path of the open database', () async {
      await publish(keyFilePath: () async => '/keys/example.key');

      final outcome = await revealBridge.writePasskey!(
        entryId: 'entry-1',
        relyingPartyId: 'example.com',
        username: 'ada',
        userHandle: null,
        replaceExisting: false,
      );

      expect(outcome.ok, isTrue);
      // Without this a key-file-protected vault cannot be opened, and the
      // write fails after the user has already confirmed.
      expect(kdbx.lastKeyFilePath, '/keys/example.key');
    });

    test('a vault with no key file forwards null, not an empty path', () async {
      await publish(keyFilePath: () async => null);

      await revealBridge.writePasskey!(
        entryId: 'entry-1',
        relyingPartyId: 'example.com',
        username: 'ada',
        userHandle: null,
        replaceExisting: false,
      );

      expect(kdbx.lastKeyFilePath, isNull);
    });

    test("stores the relying party's own user handle", () async {
      await publish();
      final handle = Uint8List.fromList([7, 7, 7]);

      await revealBridge.writePasskey!(
        entryId: 'entry-1',
        relyingPartyId: 'example.com',
        username: 'ada',
        userHandle: handle,
        replaceExisting: false,
      );

      // Not the credential id: a handle we minted ourselves is one the site
      // cannot resolve back to an account, and it never matches on a
      // replacement either.
      expect(kdbx.lastPasskey!.userHandle, handle);
      expect(
        kdbx.lastPasskey!.userHandle,
        isNot(kdbx.lastPasskey!.credentialId),
      );
    });

    test('a write with no handle falls back to one of our own', () async {
      await publish();

      await revealBridge.writePasskey!(
        entryId: 'entry-1',
        relyingPartyId: 'example.com',
        username: 'ada',
        userHandle: null,
        replaceExisting: false,
      );

      expect(kdbx.lastPasskey!.userHandle, kdbx.lastPasskey!.credentialId);
    });

    test(
      'a successful write announces itself, a failed one does not',
      () async {
        await publish();
        var announcements = 0;
        approvals.writtenListenable.addListener(() => announcements++);

        await revealBridge.writePasskey!(
          entryId: 'entry-1',
          relyingPartyId: 'example.com',
          username: 'ada',
          userHandle: null,
          replaceExisting: false,
        );
        expect(
          announcements,
          1,
          reason: 'the app window has to reload: the vault is ahead of it',
        );

        kdbx.error = StateError('write failed');
        final failed = await revealBridge.writePasskey!(
          entryId: 'entry-1',
          relyingPartyId: 'example.com',
          username: 'ada',
          userHandle: null,
          replaceExisting: false,
        );
        expect(failed.ok, isFalse);
        expect(announcements, 1);
      },
    );
  });
}

class _FailingWriteStore extends DesktopBrowserAutofillCacheStore {
  _FailingWriteStore({required Directory directory})
    : super(directory: directory);

  bool failWrites = false;

  @override
  Future<void> writeMetadataCache(
    DesktopBrowserAutofillMetadataCache cache,
  ) async {
    if (failWrites) {
      throw StateError('metadata write failed');
    }
    await super.writeMetadataCache(cache);
  }
}
