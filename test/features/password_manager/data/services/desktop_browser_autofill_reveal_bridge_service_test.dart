import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';

void main() {
  group('DesktopBrowserAutofillRevealBridgeService', () {
    test('returns credentials only from authenticated exact reveal', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-reveal-bridge-',
      );
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      final service = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: const DesktopBrowserAutofillMetadataMapper(),
      );
      addTearDown(service.stop);

      await service.start(
        databasePath: '/vaults/example.kdbx',
        entries: [
          _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'super-secret',
            url: 'https://example.com/login',
          ),
        ],
      );

      final descriptor = await store.readBridgeDescriptor();
      expect(descriptor, isNotNull);
      final descriptorJson = await store.bridgeDescriptorFile!.readAsString();
      expect(descriptorJson, isNot(contains('super-secret')));
      expect(descriptorJson, isNot(contains('alice')));

      final response = await _postBridge(
        descriptor: descriptor!,
        body: {
          'databaseId': descriptor.databaseId,
          'entryId': 'entry-1',
          'origin': 'https://example.com',
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.json['ok'], isTrue);
      final data = response.json['data']! as Map<String, Object?>;
      expect(data['entryId'], 'entry-1');
      expect(data['username'], 'alice');
      expect(data['password'], 'super-secret');
    });

    test('returns authenticated status without credential data', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-reveal-bridge-',
      );
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      final service = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: const DesktopBrowserAutofillMetadataMapper(),
      );
      addTearDown(service.stop);
      await service.start(
        databasePath: '/vaults/example.kdbx',
        entries: [
          _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'super-secret',
            url: 'https://example.com/login',
          ),
        ],
      );
      final descriptor = (await store.readBridgeDescriptor())!;

      final response = await _postBridge(
        descriptor: descriptor,
        path: '/status',
        body: const {},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.json, {
        'ok': true,
        'data': {'databaseId': descriptor.databaseId},
      });
      expect(jsonEncode(response.json), isNot(contains('alice')));
      expect(jsonEncode(response.json), isNot(contains('super-secret')));
    });

    test('rejects reveal without valid bearer token', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-reveal-bridge-',
      );
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      final service = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: const DesktopBrowserAutofillMetadataMapper(),
      );
      addTearDown(service.stop);

      await service.start(
        databasePath: '/vaults/example.kdbx',
        entries: [
          _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'super-secret',
            url: 'https://example.com/login',
          ),
        ],
      );

      final descriptor = (await store.readBridgeDescriptor())!;
      final response = await _postBridge(
        descriptor: descriptor,
        authorizationToken: 'wrong-token',
        body: {
          'databaseId': descriptor.databaseId,
          'entryId': 'entry-1',
          'origin': 'https://example.com',
        },
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      final error = response.json['error']! as Map<String, Object?>;
      expect(error['code'], 'unauthorized');
      expect(jsonEncode(response.json), isNot(contains('super-secret')));
    });

    test('denies phishing host that only contains credential host', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-reveal-bridge-',
      );
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      final service = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: const DesktopBrowserAutofillMetadataMapper(),
      );
      addTearDown(service.stop);

      await service.start(
        databasePath: '/vaults/example.kdbx',
        entries: [
          _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'super-secret',
            url: 'https://example.com',
          ),
        ],
      );

      final descriptor = (await store.readBridgeDescriptor())!;
      final response = await _postBridge(
        descriptor: descriptor,
        body: {
          'databaseId': descriptor.databaseId,
          'entryId': 'entry-1',
          'origin': 'https://example.com.evil.com',
        },
      );

      expect(response.statusCode, HttpStatus.forbidden);
      expect(jsonEncode(response.json), isNot(contains('super-secret')));
      final error = response.json['error']! as Map<String, Object?>;
      expect(error['code'], 'strong_match_required');
    });

    group('origin scheme and port binding', () {
      test('denies https entry on a downgraded http page', () async {
        _expectRevealRefused(
          await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: 'https://example.test/login',
            ),
            origin: 'http://example.test',
          ),
        );
      });

      test('still allows the matching https page', () async {
        final response = await _reveal(
          entry: _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'test-only-secret',
            url: 'https://example.test/login',
          ),
          origin: 'https://example.test',
        );

        expect(response.statusCode, HttpStatus.ok);
        final data = response.json['data']! as Map<String, Object?>;
        expect(data['password'], 'test-only-secret');
      });

      test('denies a port mismatch on the same host', () async {
        _expectRevealRefused(
          await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: 'https://example.test:8443/login',
            ),
            origin: 'https://example.test',
          ),
        );
      });

      test('allows a domain-only entry on an https page', () async {
        final response = await _reveal(
          entry: _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'test-only-secret',
            url: '',
            customFields: const [
              VaultCustomField(key: 'domain', value: 'example.test'),
            ],
          ),
          origin: 'https://example.test',
        );

        expect(response.statusCode, HttpStatus.ok);
        final data = response.json['data']! as Map<String, Object?>;
        expect(data['password'], 'test-only-secret');
      });

      test('denies a domain-only entry on an http page', () async {
        _expectRevealRefused(
          await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: '',
              customFields: const [
                VaultCustomField(key: 'domain', value: 'example.test'),
              ],
            ),
            origin: 'http://example.test',
          ),
        );
      });

      test('allows the http entry / https page upgrade', () async {
        final response = await _reveal(
          entry: _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'test-only-secret',
            url: 'http://example.test/login',
          ),
          origin: 'https://example.test',
        );

        expect(response.statusCode, HttpStatus.ok);
        final data = response.json['data']! as Map<String, Object?>;
        expect(data['password'], 'test-only-secret');
      });
    });

    test('stop removes descriptor and closes bridge', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-reveal-bridge-',
      );
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      final service = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: const DesktopBrowserAutofillMetadataMapper(),
      );

      await service.start(
        databasePath: '/vaults/example.kdbx',
        entries: [
          _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'super-secret',
            url: 'https://example.com',
          ),
        ],
      );
      final descriptor = await store.readBridgeDescriptor();
      expect(descriptor, isNotNull);
      expect(await store.bridgeDescriptorFile!.exists(), isTrue);

      await service.stop();

      expect(await store.readBridgeDescriptor(), isNull);
      expect(await store.bridgeDescriptorFile!.exists(), isFalse);
      await expectLater(
        _postBridge(
          descriptor: descriptor!,
          body: {
            'databaseId': descriptor.databaseId,
            'entryId': 'entry-1',
            'origin': 'https://example.com',
          },
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });
}

Future<_RevealHttpResponse> _postBridge({
  required DesktopBrowserAutofillBridgeDescriptor descriptor,
  required Map<String, Object?> body,
  String path = '/reveal',
  String? authorizationToken,
}) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.postUrl(
      Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: descriptor.port,
        path: path,
      ),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${authorizationToken ?? descriptor.token}',
    );
    request.write(jsonEncode(body));
    final response = await request.close();
    final payload = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(payload) as Map<String, Object?>;
    return _RevealHttpResponse(statusCode: response.statusCode, json: decoded);
  } finally {
    client.close(force: true);
  }
}

class _RevealHttpResponse {
  const _RevealHttpResponse({required this.statusCode, required this.json});

  final int statusCode;
  final Map<String, Object?> json;
}

Future<_RevealHttpResponse> _reveal({
  required VaultEntry entry,
  required String origin,
}) async {
  final directory = await Directory.systemTemp.createTemp('kv-reveal-bridge-');
  final store = DesktopBrowserAutofillCacheStore(directory: directory);
  final service = DesktopBrowserAutofillRevealBridgeService(
    store: store,
    mapper: const DesktopBrowserAutofillMetadataMapper(),
  );
  addTearDown(service.stop);

  await service.start(databasePath: '/vaults/example.kdbx', entries: [entry]);
  final descriptor = (await store.readBridgeDescriptor())!;

  return _postBridge(
    descriptor: descriptor,
    body: {
      'databaseId': descriptor.databaseId,
      'entryId': entry.id,
      'origin': origin,
    },
  );
}

void _expectRevealRefused(_RevealHttpResponse response) {
  expect(response.statusCode, HttpStatus.forbidden);
  final error = response.json['error']! as Map<String, Object?>;
  expect(error['code'], 'strong_match_required');
  final encoded = jsonEncode(response.json);
  expect(encoded, isNot(contains('test-only-secret')));
  expect(encoded, isNot(contains('alice')));
  // The refusal must not tell the caller which rule rejected it.
  final message = (error['message']! as String).toLowerCase();
  expect(message, isNot(contains('scheme')));
  expect(message, isNot(contains('http')));
  expect(message, isNot(contains('port')));
}

VaultEntry _entry({
  required String id,
  required String username,
  required String password,
  required String url,
  List<VaultCustomField> customFields = const [],
}) {
  return VaultEntry(
    id: id,
    groupId: 'root',
    title: 'Example',
    username: username,
    password: password,
    url: url,
    notes: 'hidden',
    customFields: customFields,
  );
}
