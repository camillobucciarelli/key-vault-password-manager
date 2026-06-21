import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/apple_autofill_v2_method_channel_client.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleAutofillV2MethodChannelClient', () {
    const channel = MethodChannel(
      AppleAutofillV2MethodChannelClient.channelName,
    );
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'publishCredentials':
                final args = call.arguments as Map<dynamic, dynamic>;
                final entries = args['entries'] as List<dynamic>;
                return {
                  'publishedCount': entries.length,
                  'skippedCount': 0,
                  'identityCount': entries.length,
                  'identityStoreSynced': true,
                  'warnings': <String>[],
                };
              case 'clearCredentials':
                return {
                  'cleared': true,
                  'identityStoreCleared': true,
                  'keychainKeyCleared': true,
                  'warnings': <String>[],
                };
              case 'getStatus':
                return {
                  'version': 2,
                  'appGroupAvailable': true,
                  'keychainAccessGroupAvailable': true,
                  'metadataCount': 1,
                  'encryptedCacheAvailable': true,
                  'cacheAvailable': true,
                  'databaseId': 'db-1',
                  'generatedAtEpochMs': 123,
                };
            }
            fail('Unexpected method ${call.method}');
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('publishCredentials sends the native v2 payload', () async {
      final client = AppleAutofillV2MethodChannelClient(
        channel: channel,
        isSupportedOverride: true,
      );

      final result = await client.publishCredentials(
        databaseId: 'db-1',
        credentials: const [
          AppleAutofillV2Credential(
            id: 'entry-1',
            title: 'Example',
            username: 'alice',
            password: 'super-secret',
            url: 'https://example.com',
            serviceIdentifiers: [
              AppleAutofillV2ServiceIdentifier.domain('example.com'),
              AppleAutofillV2ServiceIdentifier.url('https://example.com'),
              AppleAutofillV2ServiceIdentifier.bundleId('com.example.app'),
            ],
          ),
        ],
      );

      expect(result.publishedCount, 1);
      expect(calls.single.method, 'publishCredentials');
      final args = calls.single.arguments as Map<dynamic, dynamic>;
      expect(args['databaseId'], 'db-1');
      final entries = args['entries'] as List<dynamic>;
      final entry = entries.single as Map<dynamic, dynamic>;
      expect(entry['id'], 'entry-1');
      expect(entry['title'], 'Example');
      expect(entry['username'], 'alice');
      expect(entry['password'], 'super-secret');
      expect(entry['url'], 'https://example.com');
      expect(entry['serviceIdentifiers'], [
        {'type': 'domain', 'value': 'example.com'},
        {'type': 'url', 'value': 'https://example.com'},
        {'type': 'bundleId', 'value': 'com.example.app'},
      ]);
    });

    test('clearCredentials passes optional databaseId', () async {
      final client = AppleAutofillV2MethodChannelClient(
        channel: channel,
        isSupportedOverride: true,
      );

      final result = await client.clearCredentials(databaseId: 'db-1');

      expect(result.cleared, isTrue);
      expect(calls.single.method, 'clearCredentials');
      expect(calls.single.arguments, {'databaseId': 'db-1'});
    });

    test('getStatus marks supported native status', () async {
      final client = AppleAutofillV2MethodChannelClient(
        channel: channel,
        isSupportedOverride: true,
      );

      final status = await client.getStatus();

      expect(status.supported, isTrue);
      expect(status.version, 2);
      expect(status.metadataCount, 1);
      expect(status.databaseId, 'db-1');
    });

    test(
      'unsupported platforms are no-op and do not call MethodChannel',
      () async {
        final client = AppleAutofillV2MethodChannelClient(
          channel: channel,
          isSupportedOverride: false,
        );

        final publish = await client.publishCredentials(
          databaseId: 'db-1',
          credentials: const [],
        );
        final clear = await client.clearCredentials();
        final status = await client.getStatus();

        expect(publish.warnings, contains('unsupported_platform'));
        expect(clear.warnings, contains('unsupported_platform'));
        expect(status.supported, isFalse);
        expect(calls, isEmpty);
      },
    );
  });
}
