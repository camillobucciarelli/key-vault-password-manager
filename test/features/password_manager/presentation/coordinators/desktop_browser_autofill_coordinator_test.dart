import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_pending_generation_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/desktop_browser_autofill_coordinator.dart';

void main() {
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
