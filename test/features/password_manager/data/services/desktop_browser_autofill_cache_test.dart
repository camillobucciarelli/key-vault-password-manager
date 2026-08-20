import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/browser_exact_origin.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';

void main() {
  group('DesktopBrowserAutofillCacheStore', () {
    test(
      'uses the dedicated Team-ID-prefixed macOS app group for browser cache',
      () {
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
          'A8QUU5F9G3.dev.camillobucciarelli.kdbxKeyVault.browser/browser_v2',
        );
      },
    );

    test('legacy macOS directory points at the old shared group store', () {
      if (!Platform.isMacOS) return;

      final directory = DesktopBrowserAutofillCacheStore.legacyMacosDirectory(
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

    Directory fakeLegacyStore(Directory root) {
      final legacy = Directory('${root.path}/legacy')
        ..createSync(recursive: true);
      File(
        '${legacy.path}/bridge.json',
      ).writeAsStringSync('{"token":"stale-bearer"}');
      File('${legacy.path}/metadata.json').writeAsStringSync('{}');
      return legacy;
    }

    test('cleanupLegacyStore deletes the old store, bearer included', () async {
      final root = await Directory.systemTemp.createTemp('kv-desktop-cache-');
      final legacyDirectory = fakeLegacyStore(root);
      // No injected directory: only a store on the default location cleans up.
      final store = DesktopBrowserAutofillCacheStore(
        legacyDirectoryOverride: legacyDirectory,
      );

      await store.cleanupLegacyStore();

      expect(legacyDirectory.existsSync(), isFalse);
    });

    test('cleanupLegacyStore is a no-op when the old store is gone', () async {
      final root = await Directory.systemTemp.createTemp('kv-desktop-cache-');
      final store = DesktopBrowserAutofillCacheStore(
        legacyDirectoryOverride: Directory('${root.path}/legacy-missing'),
      );

      await expectLater(store.cleanupLegacyStore(), completes);
    });

    test('cleanupLegacyStore never touches the legacy store when the directory '
        'is injected', () async {
      // Load-bearing guard pin: without the `_directory != null` early
      // return in cleanupLegacyStore, every test that starts a bridge
      // against a temp store would delete the developer's REAL legacy
      // container during `flutter test`. This test must fail if that guard
      // is removed — on every platform, which is why it pins the guard via
      // the override seam rather than the macOS-only path derivation.
      final root = await Directory.systemTemp.createTemp('kv-desktop-cache-');
      final legacyDirectory = fakeLegacyStore(root);
      final store = DesktopBrowserAutofillCacheStore(
        directory: Directory('${root.path}/new'),
        legacyDirectoryOverride: legacyDirectory,
      );

      await store.cleanupLegacyStore();

      expect(legacyDirectory.existsSync(), isTrue);
      expect(File('${legacyDirectory.path}/bridge.json').existsSync(), isTrue);
    });

    test(
      'cleanupLegacyStore on macOS derives the legacy path from the injected '
      'environment and removes it',
      () async {
        if (!Platform.isMacOS) return;

        final root = await Directory.systemTemp.createTemp('kv-desktop-cache-');
        final legacyDirectory = Directory(
          '${root.path}/Library/Group Containers/'
          'group.dev.camillobucciarelli.kdbxKeyVault/browser_v2',
        )..createSync(recursive: true);
        File(
          '${legacyDirectory.path}/bridge.json',
        ).writeAsStringSync('{"token":"stale-bearer"}');
        final store = DesktopBrowserAutofillCacheStore();

        await store.cleanupLegacyStore(environment: {'HOME': root.path});

        expect(legacyDirectory.existsSync(), isFalse);
      },
    );

    test('cleanupLegacyStore on macOS leaves the environment-derived legacy '
        'store alone when the directory is injected', () async {
      if (!Platform.isMacOS) return;

      final root = await Directory.systemTemp.createTemp('kv-desktop-cache-');
      final legacyDirectory = Directory(
        '${root.path}/Library/Group Containers/'
        'group.dev.camillobucciarelli.kdbxKeyVault/browser_v2',
      )..createSync(recursive: true);
      File(
        '${legacyDirectory.path}/bridge.json',
      ).writeAsStringSync('{"token":"stale-bearer"}');
      final store = DesktopBrowserAutofillCacheStore(
        directory: Directory('${root.path}/new'),
      );

      await store.cleanupLegacyStore(environment: {'HOME': root.path});

      expect(legacyDirectory.existsSync(), isTrue);
    });

    test('writes store directory 0700 and files 0600 on POSIX', () async {
      if (Platform.isWindows) return;

      final root = await Directory.systemTemp.createTemp('kv-desktop-cache-');
      final directory = Directory('${root.path}/store');
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      await store.writeBridgeDescriptor(
        DesktopBrowserAutofillBridgeDescriptor(
          version: desktopBrowserAutofillBridgeDescriptorVersion,
          port: 12345,
          token: 'a' * 64,
          databaseId: 'sha256:test',
          cacheGeneration: 'cache-gen',
          bridgeGeneration: 'bridge-gen',
          createdAtEpochMs: 1,
        ),
      );

      String modeOf(String path) {
        final stat = FileStat.statSync(path);
        return (stat.mode & 0xFFF).toRadixString(8);
      }

      expect(modeOf(directory.path), '700');
      expect(modeOf(store.bridgeDescriptorFile!.path), '600');
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
            cacheGeneration: 'cache-gen-1',
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
            cacheGeneration: 'cache-gen-1',
            bridgeGeneration: 'bridge-gen-1',
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
          cacheGeneration: 'cache-gen-1',
          bridgeGeneration: 'bridge-gen-1',
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
            cacheGeneration: 'cache-gen-1',
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

  group('service identifiers only pin a declared scheme', () {
    const mapper = DesktopBrowserAutofillMetadataMapper();

    List<DesktopBrowserAutofillServiceIdentifier> identifiersFor(
      String url, {
      List<VaultCustomField> customFields = const [],
    }) {
      return mapper
          .mapEntry(
            _entry(
              id: 'entry-1',
              title: 'Example',
              username: 'alice',
              password: 'secret',
              url: url,
              customFields: customFields,
            ),
            updatedAtEpochMs: 1,
          )!
          .serviceIdentifiers;
    }

    test('a bare host emits no url identifier', () {
      expect(identifiersFor('bank.example'), const [
        DesktopBrowserAutofillServiceIdentifier(
          type: 'domain',
          value: 'bank.example',
        ),
      ]);
    });

    test('a protocol-relative url declares no scheme either', () {
      expect(
        identifiersFor(
          '//bank.example/login',
        ).where((identifier) => identifier.type == 'url'),
        isEmpty,
      );
    });

    test('a declared scheme is still pinned', () {
      expect(identifiersFor('https://bank.example/login'), const [
        DesktopBrowserAutofillServiceIdentifier(
          type: 'url',
          value: 'https://bank.example',
        ),
        DesktopBrowserAutofillServiceIdentifier(
          type: 'domain',
          value: 'bank.example',
        ),
        // 009 / A011. The `url` value above has already been through
        // `_cleanHost`, so it cannot authorize an exact-origin fill; the
        // overlay policy reads this third identifier instead.
        DesktopBrowserAutofillServiceIdentifier(
          type: exactOriginServiceIdentifierType,
          value: 'https://bank.example',
        ),
      ]);
    });

    test('the exact-origin identifier keeps every hostname label', () {
      // The `url` and `domain` values below have been through `_cleanHost` and
      // no longer say `www.`; the exact-origin one must.
      final identifiers = identifiersFor('https://www.bank.example/login');
      expect(
        identifiers.singleWhere(
          (i) => i.type == exactOriginServiceIdentifierType,
        ),
        const DesktopBrowserAutofillServiceIdentifier(
          type: exactOriginServiceIdentifierType,
          value: 'https://www.bank.example',
        ),
      );
      expect(
        identifiers.where((i) => i.type != exactOriginServiceIdentifierType),
        everyElement(
          isA<DesktopBrowserAutofillServiceIdentifier>().having(
            (i) => i.value,
            'value',
            isNot(contains('www.')),
          ),
        ),
      );
    });

    test('a non-http scheme silently declasses the entry to domain-only', () {
      expect(identifiersFor('ftp://files.example/pub'), const [
        DesktopBrowserAutofillServiceIdentifier(
          type: 'domain',
          value: 'files.example',
        ),
      ]);
    });

    test('the same rule applies to url custom fields', () {
      final identifiers = identifiersFor(
        '',
        customFields: const [
          VaultCustomField(key: 'loginUrl', value: 'nas.local'),
        ],
      );

      expect(identifiers.where((i) => i.type == 'url'), isEmpty);
      expect(identifiers.single.value, 'nas.local');
    });
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
