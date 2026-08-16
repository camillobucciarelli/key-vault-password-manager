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

    group('hosts that cannot obtain a WebPKI certificate', () {
      // A URL stored without a scheme declares no origin, so it must not be
      // pinned to an inferred `https://`. On these hosts `https` is not
      // obtainable at all, so `http` is the only origin they can ever have.
      for (final host in const [
        '192.168.1.10', // RFC 1918
        '10.4.0.7', // RFC 1918
        '172.16.9.9', // RFC 1918
        '127.0.0.1', // RFC 1122 loopback
        '169.254.10.10', // RFC 3927 link-local
        'nas', // single label
        'router.local', // RFC 6762
        'printer.home.arpa', // RFC 8375
        'wiki.internal',
        'vault.lan',
      ]) {
        test('allows $host over http when stored without a scheme', () async {
          final response = await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: host,
            ),
            origin: 'http://$host',
          );

          expect(response.statusCode, HttpStatus.ok);
          final data = response.json['data']! as Map<String, Object?>;
          expect(data['password'], 'test-only-secret');
        });
      }

      // The other side of the same criterion: on these hosts `https` *is*
      // obtainable, so a bare host stays denied over cleartext http.
      for (final host in const [
        'bank.example', // bare public domain: the most common entry shape
        '1.1.1.1', // a public IP literal can hold a WebPKI certificate
        'example.test', // RFC 2606, deliberately kept out of the allow set
      ]) {
        test('denies $host over http when stored without a scheme', () async {
          _expectRevealRefused(
            await _reveal(
              entry: _entry(
                id: 'entry-1',
                username: 'alice',
                password: 'test-only-secret',
                url: host,
              ),
              origin: 'http://$host',
            ),
          );
        });

        test('still allows $host over https', () async {
          final response = await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: host,
            ),
            origin: 'https://$host',
          );

          expect(response.statusCode, HttpStatus.ok);
        });
      }

      test('denies an explicit https entry on a private-IP http page', () async {
        // The de-pin only covers inferred schemes: a declared origin still wins.
        _expectRevealRefused(
          await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: 'https://192.168.1.10',
            ),
            origin: 'http://192.168.1.10',
          ),
        );
      });
    });

    group('default ports written explicitly', () {
      // Guards a `dart:core` Uri property, not our own code: Uri drops a port
      // equal to the scheme default, so `https://h:443` and `https://h` share
      // one normalized origin. An SDK upgrade that changed it would otherwise
      // start denying these silently.
      for (final (entryUrl, origin) in const [
        ('https://example.test:443/login', 'https://example.test'),
        ('https://example.test/login', 'https://example.test:443'),
        ('http://example.test:80/login', 'http://example.test'),
        ('http://example.test/login', 'http://example.test:80'),
      ]) {
        test('allows $entryUrl on $origin', () async {
          final response = await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: entryUrl,
            ),
            origin: origin,
          );

          expect(response.statusCode, HttpStatus.ok);
          final data = response.json['data']! as Map<String, Object?>;
          expect(data['password'], 'test-only-secret');
        });
      }

      test('denies a non-default port against a default-port entry', () async {
        _expectRevealRefused(
          await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: 'https://example.test:443/login',
            ),
            origin: 'https://example.test:8443',
          ),
        );
      });
    });

    group('the host collapse must not widen the non-WebPKI set', () {
      // `_cleanHost` strips `www.`/`m.`/`mobile.` for *matching*. Asking the
      // WebPKI question of the stripped host turned every `www.X`/`m.X` into a
      // single-label name, which is the one shape the set admits — `m.me` is a
      // real Meta host with a public certificate.
      for (final host in const ['m.me', 'www.com', 'mobile.io']) {
        test('denies $host over http when stored without a scheme', () async {
          _expectRevealRefused(
            await _reveal(
              entry: _entry(
                id: 'entry-1',
                username: 'alice',
                password: 'test-only-secret',
                url: host,
              ),
              origin: 'http://$host',
            ),
          );
        });

        test('still allows $host over https', () async {
          final response = await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: host,
            ),
            origin: 'https://$host',
          );

          expect(response.statusCode, HttpStatus.ok);
          final data = response.json['data']! as Map<String, Object?>;
          expect(data['password'], 'test-only-secret');
        });
      }

      // The genuinely single-label hosts must keep their http allowance: they
      // have no public parent zone, so `https` really is unobtainable there.
      for (final host in const ['router', 'nas']) {
        test('still allows $host over http', () async {
          final response = await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: host,
            ),
            origin: 'http://$host',
          );

          expect(response.statusCode, HttpStatus.ok);
          final data = response.json['data']! as Map<String, Object?>;
          expect(data['password'], 'test-only-secret');
        });
      }

      test('denies a bare www. public host over http', () async {
        _expectRevealRefused(
          await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: 'www.bank.example',
            ),
            origin: 'http://www.bank.example',
          ),
        );
      });
    });

    test('denies a www-stripped https entry on an http page', () async {
      // `_cleanHost` still collapses `www.`/`m.`/`mobile.` onto the bare host,
      // so `https://www.bank.example` and `http://bank.example` compare on the
      // same host. Freezing the case here: the strip must never turn into a
      // downgrade until it is removed.
      _expectRevealRefused(
        await _reveal(
          entry: _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'test-only-secret',
            url: 'https://www.bank.example/login',
          ),
          origin: 'http://bank.example',
        ),
      );
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
