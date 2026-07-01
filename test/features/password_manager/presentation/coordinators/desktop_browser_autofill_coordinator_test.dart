import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart';
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
