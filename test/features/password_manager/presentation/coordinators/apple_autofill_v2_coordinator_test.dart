import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/repositories/autofill_ports.dart';
import 'package:password_manager/features/password_manager/domain/services/apple_autofill_v2_payload_mapper.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/apple_autofill_v2_coordinator.dart';

void main() {
  group('AppleAutofillV2Coordinator', () {
    test(
      'publishes mapped vault entries without exposing raw database path',
      () async {
        final client = _FakeAppleAutofillV2Client();
        final coordinator = AppleAutofillV2Coordinator(
          client: client,
          mapper: const AppleAutofillV2PayloadMapper(),
        );

        await coordinator.publishVault(
          databasePath: '/private/vaults/main.kdbx',
          entries: [_entry()],
        );

        expect(client.publishedCredentials.single.id, 'entry-1');
        expect(client.publishedCredentials.single.password, 'pw');
        expect(client.publishedDatabaseId, startsWith('sha256:'));
        expect(client.publishedDatabaseId, isNot(contains('/private/vaults')));
      },
    );

    test('clearCredentials delegates to client on Apple platforms', () async {
      final client = _FakeAppleAutofillV2Client();
      final coordinator = AppleAutofillV2Coordinator(
        client: client,
        mapper: const AppleAutofillV2PayloadMapper(),
      );

      await coordinator.clearCredentials();

      expect(client.clearCallCount, 1);
      expect(client.clearedDatabaseId, isNull);
    });

    test('unsupported platforms skip publish and clear', () async {
      final client = _FakeAppleAutofillV2Client(isSupported: false);
      final coordinator = AppleAutofillV2Coordinator(
        client: client,
        mapper: const AppleAutofillV2PayloadMapper(),
      );

      await coordinator.publishVault(
        databasePath: '/db.kdbx',
        entries: [_entry()],
      );
      await coordinator.clearCredentials();

      expect(client.publishCallCount, 0);
      expect(client.clearCallCount, 0);
    });
  });
}

VaultEntry _entry() {
  return const VaultEntry(
    id: 'entry-1',
    groupId: 'root',
    title: 'Example',
    username: 'alice',
    password: 'pw',
    url: 'example.com',
    notes: '',
  );
}

class _FakeAppleAutofillV2Client implements AppleAutofillV2Client {
  _FakeAppleAutofillV2Client({this.isSupported = true});

  @override
  final bool isSupported;

  int publishCallCount = 0;
  int clearCallCount = 0;
  String? publishedDatabaseId;
  String? clearedDatabaseId;
  List<AppleAutofillV2Credential> publishedCredentials = const [];

  @override
  Future<AppleAutofillV2PublishResult> publishCredentials({
    required String databaseId,
    required List<AppleAutofillV2Credential> credentials,
  }) async {
    publishCallCount += 1;
    publishedDatabaseId = databaseId;
    publishedCredentials = credentials;
    return AppleAutofillV2PublishResult(
      publishedCount: credentials.length,
      skippedCount: 0,
      identityCount: credentials.length,
      identityStoreSynced: true,
    );
  }

  @override
  Future<AppleAutofillV2ClearResult> clearCredentials({
    String? databaseId,
  }) async {
    clearCallCount += 1;
    clearedDatabaseId = databaseId;
    return const AppleAutofillV2ClearResult(
      cleared: true,
      identityStoreCleared: true,
      keychainKeyCleared: true,
    );
  }

  @override
  Future<AppleAutofillV2Status> getStatus() async {
    return const AppleAutofillV2Status(
      supported: true,
      version: 2,
      appGroupAvailable: true,
      keychainAccessGroupAvailable: true,
      metadataCount: 0,
      encryptedCacheAvailable: false,
      cacheAvailable: false,
    );
  }
}
