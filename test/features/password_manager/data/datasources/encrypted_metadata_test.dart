import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/database_registry_local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/database_security_local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/metadata_cipher.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'in_memory_secure_data_source.dart';

/// Spec 014 FR-4/FR-5 (T007–T009, AC-2, AC-5).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InMemorySecureDataSource secure;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('metadata_cipher_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues(const {});
    secure = InMemorySecureDataSource();
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<Uint8List?> metadataFileBytes(String name) async {
    final file = File(p.join(tempDir.path, 'metadata', name));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  group('MetadataCipher', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i));

    test('round-trips and hides the plaintext', () {
      final sealed = MetadataCipher.seal(
        key,
        Uint8List.fromList(utf8.encode('{"name":"Vault"}')),
      );
      expect(utf8.decode(MetadataCipher.open(key, sealed)), '{"name":"Vault"}');
      expect(
        latin1.decode(sealed, allowInvalid: true),
        isNot(contains('Vault')),
      );
    });

    test('a tampered byte fails loudly, not as garbage JSON', () {
      final sealed = MetadataCipher.seal(
        key,
        Uint8List.fromList(utf8.encode('{"a":1}')),
      );
      sealed[sealed.length - 1] ^= 0xFF;
      expect(() => MetadataCipher.open(key, sealed), throwsA(anything));
    });

    test('a fresh nonce per write: two seals of the same bytes differ', () {
      final plain = Uint8List.fromList(utf8.encode('same'));
      expect(
        MetadataCipher.seal(key, plain),
        isNot(MetadataCipher.seal(key, plain)),
      );
    });
  });

  group('AC-2 no plaintext in the three metadata files', () {
    test(
      'registry, security profiles and sync mappings are unreadable',
      () async {
        final registry = DatabaseRegistryLocalDataSourceImpl(
          sharedPreferences: await SharedPreferences.getInstance(),
          secureDataSource: secure,
        );
        await registry.saveRecords([
          {
            'databaseId': 'db_1',
            'canonicalPath': '/secret/place/vaultfile',
            'displayName': 'My Secret Vault.kdbx',
          },
        ]);

        final security = DatabaseSecurityLocalDataSourceImpl(
          secureDataSource: secure,
        );
        await security.saveProfile('db_1', {
          'keyFilePath': '/secret/place/keyfile',
          'biometricProtectionEnabled': true,
        });

        final sync = SyncMetadataDataSourceImpl(secureDataSource: secure);
        await sync.upsertMapping(
          'db_1',
          const DatabaseSyncMapping(
            databasePath: '/secret/place/vaultfile',
            providerId: 'google_drive',
            remoteFileId: 'remote-123',
            remoteFileName: 'My Secret Vault.kdbx',
          ),
        );

        for (final name in [
          'database_registry_records.json',
          'database_security_profiles.json',
          'sync_mappings.json',
        ]) {
          final bytes = await metadataFileBytes(name);
          expect(bytes, isNotNull, reason: '$name must exist');
          final text = latin1.decode(bytes!, allowInvalid: true);
          expect(text, isNot(contains('Secret')), reason: name);
          expect(text, isNot(contains('/secret/place')), reason: name);
          expect(text, isNot(contains('vaultfile')), reason: name);
          expect(text, isNot(contains('remote-123')), reason: name);
          expect(text, isNot(contains('db_1')), reason: name);
        }

        // And the content round-trips through the real read paths.
        expect(
          (await registry.getRecords()).single['displayName'],
          'My Secret Vault.kdbx',
        );
        expect(
          (await security.getProfile('db_1'))!['keyFilePath'],
          '/secret/place/keyfile',
        );
        expect((await sync.getAllMappings()).single.remoteFileId, 'remote-123');
      },
    );
  });

  group('AC-5 / FR-5 secure store unavailable', () {
    test('reads are empty, nothing crashes, no plaintext is written', () async {
      final registry = DatabaseRegistryLocalDataSourceImpl(
        sharedPreferences: await SharedPreferences.getInstance(),
        secureDataSource: secure,
      );
      await registry.saveRecords([
        {'databaseId': 'db_1', 'displayName': 'Mine.kdbx'},
      ]);
      expect(await registry.getRecords(), hasLength(1));

      secure.unavailable = true;
      expect(
        await registry.getRecords(),
        isEmpty,
        reason: 'FR-5: unavailable store shows an empty database list',
      );
      await expectLater(
        registry.saveRecords([
          {'databaseId': 'db_2', 'displayName': 'Other.kdbx'},
        ]),
        throwsA(isA<StateError>()),
        reason: 'a write must be refused, never fall back to plaintext',
      );

      final bytes = await metadataFileBytes('database_registry_records.json');
      expect(
        latin1.decode(bytes!, allowInvalid: true),
        isNot(contains('Mine.kdbx')),
      );
    });

    test(
      'an absent key over existing ciphertext is never regenerated',
      () async {
        final registry = DatabaseRegistryLocalDataSourceImpl(
          sharedPreferences: await SharedPreferences.getInstance(),
          secureDataSource: secure,
        );
        await registry.saveRecords([
          {'databaseId': 'db_1', 'displayName': 'Mine.kdbx'},
        ]);
        final originalKey = secure.entries['METADATA_ENCRYPTION_KEY'];

        // Key lost, ciphertext still on disk.
        secure.entries.remove('METADATA_ENCRYPTION_KEY');
        expect(await registry.getRecords(), isEmpty);

        await expectLater(
          registry.saveRecords([
            {'databaseId': 'db_2', 'displayName': 'Other.kdbx'},
          ]),
          throwsA(isA<MetadataStorageUnreadableFailure>()),
          reason: 'minting a new key over ciphertext would destroy it',
        );
        expect(secure.entries['METADATA_ENCRYPTION_KEY'], isNull);

        // Restoring the key restores the data — nothing was clobbered.
        secure.entries['METADATA_ENCRYPTION_KEY'] = originalKey!;
        expect(
          (await registry.getRecords()).single['displayName'],
          'Mine.kdbx',
        );
      },
    );
  });

  group('T015 / FR-9 no migration', () {
    test('a plaintext (non-conforming) metadata file is an explicit cipher '
        'error, never half-parsed and never repaired', () async {
      final metadataDir = await Directory(
        p.join(tempDir.path, 'metadata'),
      ).create(recursive: true);
      final file = File(
        p.join(metadataDir.path, 'database_registry_records.json'),
      );
      final plaintext = utf8.encode('[{"databaseId":"legacy"}]');
      await file.writeAsBytes(plaintext, flush: true);

      // The cipher refuses the bytes outright (version byte mismatch).
      final key = base64Decode(await secure.createMetadataKey());
      expect(
        () => MetadataCipher.open(key, Uint8List.fromList(plaintext)),
        throwsFormatException,
      );

      // The data source reads it as empty and does NOT rewrite, repair or
      // migrate the file: the bytes on disk stay exactly as found.
      final registry = DatabaseRegistryLocalDataSourceImpl(
        sharedPreferences: await SharedPreferences.getInstance(),
        secureDataSource: secure,
      );
      expect(await registry.getRecords(), isEmpty);
      expect(await file.readAsBytes(), plaintext);
    });
  });

  group('local_state.json is encrypted too', () {
    test('round-trips through LocalDataSourceImpl', () async {
      final local = LocalDataSourceImpl(secureDataSource: secure);
      await local.setAutofillPromptSeen(true);
      expect(await local.getAutofillPromptSeen(), isTrue);
      final bytes = await metadataFileBytes('local_state.json');
      expect(bytes, isNotNull);
      final text = latin1.decode(bytes!, allowInvalid: true);
      expect(text, isNot(contains('autofill')));
    });
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}
