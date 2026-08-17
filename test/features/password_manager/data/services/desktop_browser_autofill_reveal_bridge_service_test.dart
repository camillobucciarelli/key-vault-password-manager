import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/browser_exact_origin.dart';
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

    group('a written port keeps binding when the scheme is inferred', () {
      // The de-pin drops the *scheme* claim the user never made; it must not
      // drop the *port* claim they did make. Without this, a hostile service on
      // another port of the same host — the LAN/shared-host case the de-pin
      // exists to serve — would be authorized.
      for (final (storedUrl, origin) in const [
        ('bank.example:8443', 'https://bank.example:9999'),
        ('bank.example:8443', 'https://bank.example'),
        ('192.168.1.10:8443', 'http://192.168.1.10:9999'),
        ('192.168.1.10:8443', 'http://192.168.1.10'),
      ]) {
        test('denies $storedUrl on $origin', () async {
          _expectRevealRefused(
            await _reveal(
              entry: _entry(
                id: 'entry-1',
                username: 'alice',
                password: 'test-only-secret',
                url: storedUrl,
              ),
              origin: origin,
            ),
          );
        });
      }

      for (final (storedUrl, origin) in const [
        ('bank.example:8443', 'https://bank.example:8443'),
        ('192.168.1.10:8443', 'http://192.168.1.10:8443'),
        // No port written, no port asserted: unchanged from `main`.
        ('bank.example', 'https://bank.example:9999'),
        ('192.168.1.10', 'http://192.168.1.10:9999'),
        // A written default port must survive the inferred `https://` both
        // ways, or the assertion would depend on a scheme the user never wrote.
        ('bank.example:443', 'https://bank.example'),
        ('192.168.1.10:80', 'http://192.168.1.10'),
      ]) {
        test('allows $storedUrl on $origin', () async {
          final response = await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: storedUrl,
            ),
            origin: origin,
          );

          expect(response.statusCode, HttpStatus.ok);
          final data = response.json['data']! as Map<String, Object?>;
          expect(data['password'], 'test-only-secret');
        });
      }

      test('the port also binds through a domain custom field', () async {
        _expectRevealRefused(
          await _reveal(
            entry: _entry(
              id: 'entry-1',
              username: 'alice',
              password: 'test-only-secret',
              url: '',
              customFields: const [
                VaultCustomField(key: 'domain', value: '192.168.1.10:8443'),
              ],
            ),
            origin: 'http://192.168.1.10:8080',
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

  group('009 A012 — origin-bound overlay reveal', () {
    test('reveals for an exact origin and echoes the binding', () async {
      final bridge = await _startOverlayBridge();

      final response = await _postBridge(
        descriptor: bridge.descriptor,
        path: '/overlay-reveal',
        body: _overlayBody(bridge.descriptor),
      );

      expect(response.statusCode, HttpStatus.ok);
      final data = response.json['data']! as Map<String, Object?>;
      expect(data['password'], 'test-only-secret');
      expect(data['matchPolicy'], overlayMatchPolicy);
      expect(data['origin'], 'https://example.com');
      expect(data['databaseId'], bridge.descriptor.databaseId);
      expect(data['cacheGeneration'], bridge.descriptor.cacheGeneration);
      expect(data['bridgeGeneration'], bridge.descriptor.bridgeGeneration);
      expect(bridge.descriptor.cacheGeneration, isNotEmpty);
      expect(bridge.descriptor.bridgeGeneration, isNotEmpty);
    });

    test(
      'a domain-only entry is refused where the popup would allow it',
      () async {
        final entry = _entry(
          id: 'entry-1',
          username: 'alice',
          password: 'test-only-secret',
          // No scheme: the entry stays domain-only, which the popup policy
          // authorizes on an https page and the overlay policy never does.
          url: 'example.com',
        );
        final bridge = await _startOverlayBridge(entries: [entry]);

        final popup = await _postBridge(
          descriptor: bridge.descriptor,
          body: {
            'databaseId': bridge.descriptor.databaseId,
            'entryId': 'entry-1',
            'origin': 'https://example.com',
          },
        );
        expect(
          popup.statusCode,
          HttpStatus.ok,
          reason: 'popup policy unchanged',
        );

        final overlay = await _postBridge(
          descriptor: bridge.descriptor,
          path: '/overlay-reveal',
          body: _overlayBody(bridge.descriptor),
        );
        expect(overlay.statusCode, HttpStatus.forbidden);
        expect(
          (overlay.json['error']! as Map<String, Object?>)['code'],
          'forbidden',
        );
        expect(jsonEncode(overlay.json), isNot(contains('test-only-secret')));
      },
    );

    test('a www. entry does not authorize the bare host, end to end', () async {
      final bridge = await _startOverlayBridge(
        entries: [
          _entry(
            id: 'entry-1',
            username: 'alice',
            password: 'test-only-secret',
            url: 'https://www.example.com/login',
          ),
        ],
      );

      final onOwnOrigin = await _postBridge(
        descriptor: bridge.descriptor,
        path: '/overlay-reveal',
        body: _overlayBody(
          bridge.descriptor,
          origin: 'https://www.example.com',
        ),
      );
      expect(onOwnOrigin.statusCode, HttpStatus.ok);

      // `_cleanHost` collapses these two names for possible-match ranking. That
      // collapse must never reach the overlay authorization path.
      final onBareHost = await _postBridge(
        descriptor: bridge.descriptor,
        path: '/overlay-reveal',
        body: _overlayBody(bridge.descriptor, origin: 'https://example.com'),
      );
      expect(onBareHost.statusCode, HttpStatus.forbidden);
      expect(jsonEncode(onBareHost.json), isNot(contains('test-only-secret')));
    });

    test('an unknown entry and an unauthorized origin look alike', () async {
      final bridge = await _startOverlayBridge();

      final unknown = await _postBridge(
        descriptor: bridge.descriptor,
        path: '/overlay-reveal',
        body: _overlayBody(bridge.descriptor, entryId: 'no-such-entry'),
      );
      final unauthorized = await _postBridge(
        descriptor: bridge.descriptor,
        path: '/overlay-reveal',
        body: _overlayBody(
          bridge.descriptor,
          origin: 'https://www.example.com',
        ),
      );

      expect(unknown.statusCode, unauthorized.statusCode);
      expect(unknown.json, unauthorized.json);
    });

    for (final mismatch in const [
      'databaseId',
      'cacheGeneration',
      'bridgeGeneration',
    ]) {
      test('$mismatch mismatch is stale_session, not a secret', () async {
        final bridge = await _startOverlayBridge();
        // The hook runs after the credential lookup, so a stale request that
        // never reaches it proves the *first* check refused it before the
        // credential map was ever consulted (SR-4: before lookup, and again
        // before response).
        var reachedLookup = 0;
        bridge.service.debugBeforeOverlayRevealResponse = () async {
          reachedLookup += 1;
        };

        final response = await _postBridge(
          descriptor: bridge.descriptor,
          path: '/overlay-reveal',
          body: _overlayBody(
            bridge.descriptor,
            databaseId: mismatch == 'databaseId' ? 'db-other' : null,
            cacheGeneration: mismatch == 'cacheGeneration' ? 'other' : null,
            bridgeGeneration: mismatch == 'bridgeGeneration' ? 'other' : null,
          ),
        );

        expect(response.statusCode, HttpStatus.conflict);
        expect(
          (response.json['error']! as Map<String, Object?>)['code'],
          'stale_session',
        );
        expect(reachedLookup, 0);
        expect(jsonEncode(response.json), isNot(contains('test-only-secret')));
      });
    }

    test('a request without the strict policy is refused', () async {
      final bridge = await _startOverlayBridge();

      final response = await _postBridge(
        descriptor: bridge.descriptor,
        path: '/overlay-reveal',
        body: _overlayBody(bridge.descriptor, matchPolicy: 'host'),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        (response.json['error']! as Map<String, Object?>)['code'],
        'invalid_request',
      );
    });

    test('the overlay endpoint still requires the bearer token', () async {
      final bridge = await _startOverlayBridge();

      final response = await _postBridge(
        descriptor: bridge.descriptor,
        path: '/overlay-reveal',
        body: _overlayBody(bridge.descriptor),
        authorizationToken: 'wrong-token-wrong-token-wrong-token',
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(jsonEncode(response.json), isNot(contains('test-only-secret')));
    });

    test(
      'a vault switch between the lookup and the response is stale_session',
      () async {
        final bridge = await _startOverlayBridge();
        // The second check exists exactly for this window: everything was
        // current when the credential was found, and is not current any more
        // when the answer would be written.
        bridge.service.debugBeforeOverlayRevealResponse = () async {
          await bridge.store.writeBridgeDescriptor(
            DesktopBrowserAutofillBridgeDescriptor(
              version: desktopBrowserAutofillBridgeDescriptorVersion,
              port: bridge.descriptor.port,
              token: bridge.descriptor.token,
              databaseId: 'sha256:other-vault',
              cacheGeneration: 'other-cache-generation',
              bridgeGeneration: 'other-bridge-generation',
              createdAtEpochMs: 2,
            ),
          );
        };

        final response = await _postBridge(
          descriptor: bridge.descriptor,
          path: '/overlay-reveal',
          body: _overlayBody(bridge.descriptor),
        );

        expect(response.statusCode, HttpStatus.conflict);
        expect(
          (response.json['error']! as Map<String, Object?>)['code'],
          'stale_session',
        );
        final encoded = jsonEncode(response.json);
        expect(encoded, isNot(contains('test-only-secret')));
        expect(encoded, isNot(contains('other-vault-secret')));
      },
    );
  });
}

/// 009 / A012 — the origin-bound overlay endpoint on the app bridge.
///
/// Publishes a metadata cache first, exactly like the coordinator does, because
/// the bridge copies its `cacheGeneration` from the published cache.
Future<
  ({
    DesktopBrowserAutofillBridgeDescriptor descriptor,
    DesktopBrowserAutofillRevealBridgeService service,
    DesktopBrowserAutofillCacheStore store,
  })
>
_startOverlayBridge({List<VaultEntry>? entries}) async {
  final store = DesktopBrowserAutofillCacheStore(
    directory: await Directory.systemTemp.createTemp('kv-overlay-bridge-'),
  );
  const mapper = DesktopBrowserAutofillMetadataMapper();
  final vaultEntries =
      entries ??
      [
        _entry(
          id: 'entry-1',
          username: 'alice',
          password: 'test-only-secret',
          url: 'https://example.com/login',
        ),
      ];
  await store.writeMetadataCache(
    mapper.mapVault(
      databasePath: '/vaults/example.kdbx',
      entries: vaultEntries,
    ),
  );
  final service = DesktopBrowserAutofillRevealBridgeService(
    store: store,
    mapper: mapper,
  );
  addTearDown(service.stop);
  await service.start(
    databasePath: '/vaults/example.kdbx',
    entries: vaultEntries,
  );
  return (
    descriptor: (await store.readBridgeDescriptor())!,
    service: service,
    store: store,
  );
}

Map<String, Object?> _overlayBody(
  DesktopBrowserAutofillBridgeDescriptor descriptor, {
  String entryId = 'entry-1',
  String origin = 'https://example.com',
  String? databaseId,
  String? cacheGeneration,
  String? bridgeGeneration,
  String matchPolicy = overlayMatchPolicy,
}) {
  return {
    'entryId': entryId,
    'origin': origin,
    'matchPolicy': matchPolicy,
    'databaseId': databaseId ?? descriptor.databaseId,
    'cacheGeneration': cacheGeneration ?? descriptor.cacheGeneration,
    'bridgeGeneration': bridgeGeneration ?? descriptor.bridgeGeneration,
  };
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
