import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';

import '../../tool/native_host_protocol.dart';

void main() {
  group('Native Messaging frame codec', () {
    test('encodes and decodes little-endian JSON frames', () {
      final frame = encodeNativeMessage({
        'version': nativeProtocolVersion,
        'id': 'hello-1',
        'type': 'hello',
        'payload': <String, Object?>{},
      });

      final payloadLength = ByteData.sublistView(
        frame,
        0,
        4,
      ).getUint32(0, Endian.little);
      expect(payloadLength, frame.length - 4);

      final decoded = decodeNativeMessageFrame(frame);
      expect(decoded['version'], nativeProtocolVersion);
      expect(decoded['id'], 'hello-1');
      expect(decoded['type'], 'hello');
    });

    test('rejects oversized payloads before JSON decoding', () {
      final header = ByteData(4)
        ..setUint32(0, maxNativeMessagePayloadBytes + 1, Endian.little);
      final frame = Uint8List.fromList(header.buffer.asUint8List());

      expect(
        () => decodeNativeMessageFrame(frame),
        throwsA(
          isA<NativeHostProtocolException>().having(
            (error) => error.code,
            'code',
            'payload_too_large',
          ),
        ),
      );
    });

    test('reads multiple frames from chunked stream', () async {
      final hello = encodeNativeMessage({
        'version': nativeProtocolVersion,
        'id': 'one',
        'type': 'hello',
      });
      final status = encodeNativeMessage({
        'version': nativeProtocolVersion,
        'id': 'two',
        'type': 'status',
      });
      final combined = Uint8List.fromList([...hello, ...status]);
      final reader = NativeMessageStreamReader(
        Stream<List<int>>.fromIterable([
          combined.sublist(0, 3),
          combined.sublist(3, 11),
          combined.sublist(11),
        ]),
      );

      expect((await reader.readMessage())?['id'], 'one');
      expect((await reader.readMessage())?['id'], 'two');
      expect(await reader.readMessage(), isNull);
    });
  });

  group('Native Messaging v2 protocol', () {
    test('hello returns host metadata and safe-mode status', () async {
      final store = DesktopBrowserAutofillCacheStore(
        directory: await Directory.systemTemp.createTemp('kv-native-host-'),
      );
      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'hello-1',
        'type': 'hello',
      }, store: store);

      expect(response['ok'], isTrue);
      expect(response['id'], 'hello-1');
      expect(response['type'], 'hello');

      final data = response['data']! as Map<String, Object?>;
      final host = data['host']! as Map<String, Object?>;
      final appBridge = data['appBridge']! as Map<String, Object?>;

      expect(host['name'], nativeHostName);
      expect(host['protocolVersion'], nativeProtocolVersion);
      expect(appBridge['connected'], isFalse);
      expect(data['supportedMessages'], contains('queryCredentials'));
      expect(data['supportedMessages'], contains('searchCredentials'));
      expect(data['supportedMessages'], contains('createPendingAssociation'));
      expect(data['supportedMessages'], contains('revealForFill'));
    });

    test(
      'queryCredentials returns a safe app bridge error, never secrets',
      () async {
        final store = DesktopBrowserAutofillCacheStore(
          directory: await Directory.systemTemp.createTemp('kv-native-host-'),
        );
        final response = await handleNativeHostRequest({
          'version': nativeProtocolVersion,
          'id': 'query-1',
          'type': 'queryCredentials',
          'payload': {'url': 'https://example.com', 'limit': 5},
        }, store: store);

        expect(response['ok'], isFalse);
        expect(response['type'], 'queryCredentials');
        final error = response['error']! as Map<String, Object?>;
        expect(error['code'], 'app_bridge_unavailable');

        final encoded = jsonEncode(response);
        expect(encoded, isNot(contains('hunter2')));
        expect(encoded, isNot(contains('passwordValue')));
        expect(encoded, isNot(contains('credentials":[')));
      },
    );

    test('revealForFill is schema-validated but not implemented', () async {
      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'reveal-1',
        'type': 'revealForFill',
        'payload': {'entryId': 'entry-123'},
      });

      expect(response['ok'], isFalse);
      final error = response['error']! as Map<String, Object?>;
      expect(error['code'], 'not_implemented');
    });

    test('rejects legacy secret-bearing request fields', () async {
      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'legacy-1',
        'type': 'queryCredentials',
        'masterPassword': 'hunter2',
        'payload': {'url': 'https://example.com'},
      });

      expect(response['ok'], isFalse);
      final error = response['error']! as Map<String, Object?>;
      expect(error['code'], 'legacy_fields_rejected');
      expect(jsonEncode(response), isNot(contains('hunter2')));
    });

    test('rejects unsupported message types', () async {
      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'bad-1',
        'type': 'findCredentials',
      });

      expect(response['ok'], isFalse);
      final error = response['error']! as Map<String, Object?>;
      expect(error['code'], 'unsupported_type');
    });

    test('queryCredentials returns exact host strong matches only', () async {
      final store = DesktopBrowserAutofillCacheStore(
        directory: await Directory.systemTemp.createTemp('kv-native-host-'),
      );
      await store.writeMetadataCache(
        const DesktopBrowserAutofillMetadataCache(
          version: desktopBrowserAutofillCacheVersion,
          databaseId: 'db-1',
          generatedAtEpochMs: 1,
          entries: [
            DesktopBrowserAutofillCredentialMetadata(
              id: 'exact',
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
            DesktopBrowserAutofillCredentialMetadata(
              id: 'phishing',
              title: 'Phishing',
              username: 'mallory',
              displayService: 'example.com.evil.com',
              serviceIdentifiers: [
                DesktopBrowserAutofillServiceIdentifier(
                  type: 'domain',
                  value: 'example.com.evil.com',
                ),
              ],
              updatedAtEpochMs: 1,
            ),
          ],
        ),
      );

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'query-strong',
        'type': 'queryCredentials',
        'payload': {'url': 'https://example.com', 'limit': 10},
      }, store: store);

      expect(response['ok'], isTrue);
      final data = response['data']! as Map<String, Object?>;
      final strongMatches = data['strongMatches']! as List<Object?>;
      final possibleMatches = data['possibleMatches']! as List<Object?>;
      expect(strongMatches, hasLength(1));
      expect(
        (strongMatches.single as Map<String, Object?>)['entryId'],
        'exact',
      );
      expect(jsonEncode(strongMatches), isNot(contains('phishing')));
      expect(jsonEncode(possibleMatches), isNot(contains('phishing')));
    });

    test('partial target token is possible match only', () async {
      final store = DesktopBrowserAutofillCacheStore(
        directory: await Directory.systemTemp.createTemp('kv-native-host-'),
      );
      await store.writeMetadataCache(
        const DesktopBrowserAutofillMetadataCache(
          version: desktopBrowserAutofillCacheVersion,
          databaseId: 'db-1',
          generatedAtEpochMs: 1,
          entries: [
            DesktopBrowserAutofillCredentialMetadata(
              id: 'bank',
              title: 'Example Bank',
              username: 'alice',
              displayService: 'examplebank.com',
              serviceIdentifiers: [
                DesktopBrowserAutofillServiceIdentifier(
                  type: 'domain',
                  value: 'examplebank.com',
                ),
              ],
              updatedAtEpochMs: 1,
            ),
          ],
        ),
      );

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'query-possible',
        'type': 'queryCredentials',
        'payload': {
          'url': 'https://bank-login.test',
          'title': 'Bank login',
          'limit': 10,
        },
      }, store: store);

      expect(response['ok'], isTrue);
      final data = response['data']! as Map<String, Object?>;
      expect(data['strongMatches'], isEmpty);
      final possibleMatches = data['possibleMatches']! as List<Object?>;
      expect(possibleMatches, hasLength(1));
      final match = possibleMatches.single as Map<String, Object?>;
      expect(match['entryId'], 'bank');
      expect(match['matchType'], 'possible');
    });

    test(
      'createPendingAssociation stores sanitized desktop target only',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kv-native-host-',
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
                displayService: 'old.example',
                serviceIdentifiers: [
                  DesktopBrowserAutofillServiceIdentifier(
                    type: 'domain',
                    value: 'old.example',
                  ),
                ],
                updatedAtEpochMs: 1,
              ),
            ],
          ),
        );

        final response = await handleNativeHostRequest({
          'version': nativeProtocolVersion,
          'id': 'pending-1',
          'type': 'createPendingAssociation',
          'payload': {
            'entryId': 'entry-1',
            'url': 'https://Example.com/login?token=secret#frag',
          },
        }, store: store);

        expect(response['ok'], isTrue);
        final pending = await store.readPendingAssociations();
        expect(pending, hasLength(1));
        expect(pending.single.databaseId, 'db-1');
        expect(pending.single.entryId, 'entry-1');
        expect(pending.single.serviceIdentifierType, 'domain');
        expect(pending.single.serviceIdentifierValue, 'example.com');
        expect(pending.single.displayService, 'example.com');
        expect(pending.single.platform, desktopBrowserAutofillPlatform);
        final encoded = await store.pendingAssociationsFile!.readAsString();
        expect(encoded, isNot(contains('/login')));
        expect(encoded, isNot(contains('token=secret')));
        expect(encoded, isNot(contains('frag')));
        expect(encoded, isNot(contains('password')));
      },
    );
  });
}
