import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';

void main() {
  group('DesktopBrowserAutofillCacheStore', () {
    test('uses macOS app group for browser cache', () {
      if (!Platform.isMacOS) return;

      final directory = DesktopBrowserAutofillCacheStore.defaultDirectory(
        environment: const {
          'HOME':
              '/Users/alice/Library/Containers/'
              'dev.camillobucciarelli.kdbxKeyVault/Data',
        },
      );

      expect(
        directory?.path,
        '/Users/alice/Library/Group Containers/'
        'group.dev.camillobucciarelli.kdbxKeyVault/browser_v2',
      );
    });

    test('publishes metadata without passwords or URL paths', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-desktop-cache-',
      );
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      const mapper = DesktopBrowserAutofillMetadataMapper();

      final cache = mapper.mapVault(
        databasePath: '/vaults/example.kdbx',
        generatedAtEpochMs: 1,
        entries: [
          _entry(
            id: 'entry-1',
            title: 'Example',
            username: 'alice',
            password: 'super-secret',
            url: 'https://www.Example.com/login?token=secret#frag',
            customFields: const [
              VaultCustomField(
                key: 'KPH: URL',
                value: 'https://accounts.example.org/path?q=ignored',
              ),
            ],
          ),
        ],
      );

      await store.writeMetadataCache(cache);
      final encoded = await store.metadataFile!.readAsString();
      final reloaded = await store.readMetadataCache();

      expect(reloaded, isNotNull);
      expect(reloaded!.entries.single.displayService, 'example.com');
      expect(encoded, contains('https://example.com'));
      expect(encoded, contains('https://accounts.example.org'));
      expect(encoded, isNot(contains('super-secret')));
      expect(encoded, isNot(contains('/login')));
      expect(encoded, isNot(contains('token=secret')));
      expect(encoded, isNot(contains('frag')));
      expect(encoded, isNot(contains('/path')));
      expect(encoded, isNot(contains('q=ignored')));
    });

    test(
      'clearCredentials removes metadata and pending association files',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kv-desktop-cache-',
        );
        final store = DesktopBrowserAutofillCacheStore(directory: directory);
        await store.writeMetadataCache(
          const DesktopBrowserAutofillMetadataCache(
            version: desktopBrowserAutofillCacheVersion,
            databaseId: 'db-1',
            generatedAtEpochMs: 1,
            entries: [
              DesktopBrowserAutofillCredentialMetadata(
                id: 'entry-1',
                title: 'Example',
                username: 'alice',
                displayService: 'example.com',
                serviceIdentifiers: [
                  DesktopBrowserAutofillServiceIdentifier(
                    type: 'domain',
                    value: 'example.com',
                  ),
                ],
                updatedAtEpochMs: 1,
              ),
            ],
          ),
        );
        await store.savePendingAssociation(
          entryId: 'entry-1',
          target: const DesktopBrowserAutofillAssociationTarget(
            type: 'domain',
            value: 'example.org',
            displayService: 'example.org',
          ),
        );
        await store.writeBridgeDescriptor(
          const DesktopBrowserAutofillBridgeDescriptor(
            version: desktopBrowserAutofillBridgeDescriptorVersion,
            port: 49152,
            token: 'test-token-test-token-test-token-test-token',
            databaseId: 'db-1',
            createdAtEpochMs: 1,
          ),
        );

        expect(await store.metadataFile!.exists(), isTrue);
        expect(await store.pendingAssociationsFile!.exists(), isTrue);
        expect(await store.bridgeDescriptorFile!.exists(), isTrue);

        await store.clearCredentials();

        expect(await store.metadataFile!.exists(), isFalse);
        expect(await store.pendingAssociationsFile!.exists(), isFalse);
        expect(await store.bridgeDescriptorFile!.exists(), isFalse);
      },
    );

    test('bridge descriptor contains token metadata only', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-desktop-cache-',
      );
      final store = DesktopBrowserAutofillCacheStore(directory: directory);

      await store.writeBridgeDescriptor(
        const DesktopBrowserAutofillBridgeDescriptor(
          version: desktopBrowserAutofillBridgeDescriptorVersion,
          port: 49152,
          token: 'test-token-test-token-test-token-test-token',
          databaseId: 'db-1',
          createdAtEpochMs: 1,
        ),
      );

      final encoded = await store.bridgeDescriptorFile!.readAsString();
      final descriptor = await store.readBridgeDescriptor();

      expect(descriptor, isNotNull);
      expect(descriptor!.databaseId, 'db-1');
      expect(encoded, contains('test-token'));
      expect(encoded, isNot(contains('super-secret')));
      expect(encoded, isNot(contains('password')));
      expect(encoded, isNot(contains('username')));
    });

    test(
      'savePendingAssociation strips URL path from direct targets',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kv-desktop-cache-',
        );
        final store = DesktopBrowserAutofillCacheStore(directory: directory);
        await store.writeMetadataCache(
          const DesktopBrowserAutofillMetadataCache(
            version: desktopBrowserAutofillCacheVersion,
            databaseId: 'db-1',
            generatedAtEpochMs: 1,
            entries: [
              DesktopBrowserAutofillCredentialMetadata(
                id: 'entry-1',
                title: 'Example',
                username: 'alice',
                displayService: 'example.com',
                serviceIdentifiers: [
                  DesktopBrowserAutofillServiceIdentifier(
                    type: 'domain',
                    value: 'example.com',
                  ),
                ],
                updatedAtEpochMs: 1,
              ),
            ],
          ),
        );

        final pending = await store.savePendingAssociation(
          entryId: 'entry-1',
          target: const DesktopBrowserAutofillAssociationTarget(
            type: 'domain',
            value: 'https://Example.org/login?token=secret#frag',
            displayService: 'https://Example.org/login?token=secret#frag',
          ),
        );

        expect(pending, isNotNull);
        expect(pending!.serviceIdentifierValue, 'example.org');
        expect(pending.displayService, 'example.org');
        final encoded = await store.pendingAssociationsFile!.readAsString();
        expect(encoded, isNot(contains('/login')));
        expect(encoded, isNot(contains('token=secret')));
        expect(encoded, isNot(contains('frag')));
      },
    );
  });
}

VaultEntry _entry({
  required String id,
  required String title,
  required String username,
  required String password,
  required String url,
  List<VaultCustomField> customFields = const [],
}) {
  return VaultEntry(
    id: id,
    groupId: 'root',
    title: title,
    username: username,
    password: password,
    url: url,
    notes: 'not published',
    customFields: customFields,
  );
}
