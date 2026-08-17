import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/browser_exact_origin.dart';
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

    test(
      'revealForFill returns one-shot credentials via local bridge',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kv-native-host-',
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
                id: 'entry-123',
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
        final bridge = await _FakeRevealBridge.start(
          responseData: const {
            'entryId': 'entry-123',
            'username': 'alice',
            'password': 'super-secret',
          },
        );
        addTearDown(bridge.close);
        await store.writeBridgeDescriptor(
          bridge.descriptor(databaseId: 'db-1'),
        );

        final response = await handleNativeHostRequest({
          'version': nativeProtocolVersion,
          'id': 'reveal-1',
          'type': 'revealForFill',
          'payload': {'entryId': 'entry-123', 'origin': 'https://example.com'},
        }, store: store);

        expect(response['ok'], isTrue);
        final data = response['data']! as Map<String, Object?>;
        expect(data['entryId'], 'entry-123');
        expect(data['username'], 'alice');
        expect(data['password'], 'super-secret');
        expect(bridge.requestCount, 1);
        expect(bridge.lastPayload?['origin'], 'https://example.com');
        final descriptorJson = await store.bridgeDescriptorFile!.readAsString();
        expect(descriptorJson, isNot(contains('super-secret')));
      },
    );

    test('revealForFill denies possible/manual non-exact match', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-native-host-',
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
      final bridge = await _FakeRevealBridge.start(
        responseData: const {
          'entryId': 'bank',
          'username': 'alice',
          'password': 'super-secret',
        },
      );
      addTearDown(bridge.close);
      await store.writeBridgeDescriptor(bridge.descriptor(databaseId: 'db-1'));

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'reveal-possible',
        'type': 'revealForFill',
        'payload': {'entryId': 'bank', 'origin': 'https://bank-login.test'},
      }, store: store);

      expect(response['ok'], isFalse);
      final error = response['error']! as Map<String, Object?>;
      expect(error['code'], 'strong_match_required');
      expect(bridge.requestCount, 0);
      expect(jsonEncode(response), isNot(contains('super-secret')));
    });

    test(
      'revealForFill denies example.com credential on phishing host',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'kv-native-host-',
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
                id: 'example',
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
        final bridge = await _FakeRevealBridge.start(
          responseData: const {
            'entryId': 'example',
            'username': 'alice',
            'password': 'super-secret',
          },
        );
        addTearDown(bridge.close);
        await store.writeBridgeDescriptor(
          bridge.descriptor(databaseId: 'db-1'),
        );

        final response = await handleNativeHostRequest({
          'version': nativeProtocolVersion,
          'id': 'reveal-phish',
          'type': 'revealForFill',
          'payload': {
            'entryId': 'example',
            'origin': 'https://example.com.evil.com',
          },
        }, store: store);

        expect(response['ok'], isFalse);
        final error = response['error']! as Map<String, Object?>;
        expect(error['code'], 'strong_match_required');
        expect(bridge.requestCount, 0);
        expect(jsonEncode(response), isNot(contains('super-secret')));
      },
    );

    group('revealForFill origin scheme and port binding', () {
      const httpsEntry = [
        DesktopBrowserAutofillServiceIdentifier(
          type: 'url',
          value: 'https://example.test',
        ),
        DesktopBrowserAutofillServiceIdentifier(
          type: 'domain',
          value: 'example.test',
        ),
      ];

      test('denies https entry on a downgraded http page', () async {
        _expectRevealRefused(
          await _revealForFill(
            identifiers: httpsEntry,
            origin: 'http://example.test',
          ),
        );
      });

      test('still allows the matching https page', () async {
        final result = await _revealForFill(
          identifiers: httpsEntry,
          origin: 'https://example.test',
        );

        expect(result.response['ok'], isTrue);
        final data = result.response['data']! as Map<String, Object?>;
        expect(data['password'], 'test-only-secret');
        expect(result.bridgeCalls, 1);
      });

      test('denies a port mismatch on the same host', () async {
        _expectRevealRefused(
          await _revealForFill(
            identifiers: const [
              DesktopBrowserAutofillServiceIdentifier(
                type: 'url',
                value: 'https://example.test:8443',
              ),
              DesktopBrowserAutofillServiceIdentifier(
                type: 'domain',
                value: 'example.test',
              ),
            ],
            origin: 'https://example.test',
          ),
        );
      });

      test(
        'denies an unexpected port on a pinned default-port entry',
        () async {
          _expectRevealRefused(
            await _revealForFill(
              identifiers: httpsEntry,
              origin: 'https://example.test:8443',
            ),
          );
        },
      );

      test('allows a domain-only entry on an https page', () async {
        final result = await _revealForFill(
          identifiers: const [
            DesktopBrowserAutofillServiceIdentifier(
              type: 'domain',
              value: 'example.test',
            ),
          ],
          origin: 'https://example.test',
        );

        expect(result.response['ok'], isTrue);
        expect(result.bridgeCalls, 1);
      });

      test('denies a domain-only entry on an http page', () async {
        _expectRevealRefused(
          await _revealForFill(
            identifiers: const [
              DesktopBrowserAutofillServiceIdentifier(
                type: 'domain',
                value: 'example.test',
              ),
            ],
            origin: 'http://example.test',
          ),
        );
      });

      test('allows the http entry / https page upgrade', () async {
        final result = await _revealForFill(
          identifiers: const [
            DesktopBrowserAutofillServiceIdentifier(
              type: 'url',
              value: 'http://example.test',
            ),
            DesktopBrowserAutofillServiceIdentifier(
              type: 'domain',
              value: 'example.test',
            ),
          ],
          origin: 'https://example.test',
        );

        expect(result.response['ok'], isTrue);
        expect(result.bridgeCalls, 1);
      });

      test('denies the upgrade when the port differs', () async {
        _expectRevealRefused(
          await _revealForFill(
            identifiers: const [
              DesktopBrowserAutofillServiceIdentifier(
                type: 'url',
                value: 'http://example.test:8080',
              ),
              DesktopBrowserAutofillServiceIdentifier(
                type: 'domain',
                value: 'example.test',
              ),
            ],
            origin: 'https://example.test',
          ),
        );
      });

      group('hosts that cannot obtain a WebPKI certificate', () {
        // A URL stored without a scheme emits a `domain` identifier and no
        // `url` pin, so the page scheme is decided here.
        for (final host in const [
          '192.168.1.10',
          '10.4.0.7',
          '172.16.9.9',
          '127.0.0.1',
          '169.254.10.10',
          'nas',
          'router.local',
          'printer.home.arpa',
          'wiki.internal',
          'vault.lan',
        ]) {
          test('allows $host over http', () async {
            final result = await _revealForFill(
              identifiers: [
                DesktopBrowserAutofillServiceIdentifier(
                  type: 'domain',
                  value: host,
                ),
              ],
              origin: 'http://$host',
            );

            expect(result.response['ok'], isTrue);
            expect(result.bridgeCalls, 1);
          });
        }

        for (final host in const ['bank.example', '1.1.1.1', 'example.test']) {
          test('denies $host over http', () async {
            _expectRevealRefused(
              await _revealForFill(
                identifiers: [
                  DesktopBrowserAutofillServiceIdentifier(
                    type: 'domain',
                    value: host,
                  ),
                ],
                origin: 'http://$host',
              ),
            );
          });
        }

        test('denies an http page when the entry pins https', () async {
          _expectRevealRefused(
            await _revealForFill(
              identifiers: const [
                DesktopBrowserAutofillServiceIdentifier(
                  type: 'url',
                  value: 'https://192.168.1.10',
                ),
                DesktopBrowserAutofillServiceIdentifier(
                  type: 'domain',
                  value: '192.168.1.10',
                ),
              ],
              origin: 'http://192.168.1.10',
            ),
          );
        });

        // This layer canonicalizes the page origin itself before handing it to
        // the policy. Collapsing `m.`/`www.`/`mobile.` there would make `m.me`
        // arrive as the single-label `me` and pass as non-public.
        for (final host in const ['m.me', 'www.com', 'mobile.io']) {
          test('denies $host over http', () async {
            _expectRevealRefused(
              await _revealForFill(
                identifiers: [
                  DesktopBrowserAutofillServiceIdentifier(
                    type: 'domain',
                    value: host,
                  ),
                ],
                origin: 'http://$host',
              ),
            );
          });
        }
      });

      group('a written port binds without a scheme pin', () {
        for (final (domain, origin) in const [
          ('bank.example:8443', 'https://bank.example:9999'),
          ('bank.example:8443', 'https://bank.example'),
          ('192.168.1.10:8443', 'http://192.168.1.10:9999'),
          ('192.168.1.10:8443', 'http://192.168.1.10'),
        ]) {
          test('denies $domain on $origin', () async {
            _expectRevealRefused(
              await _revealForFill(
                identifiers: [
                  DesktopBrowserAutofillServiceIdentifier(
                    type: 'domain',
                    value: domain,
                  ),
                ],
                origin: origin,
              ),
            );
          });
        }

        for (final (domain, origin) in const [
          ('bank.example:8443', 'https://bank.example:8443'),
          ('192.168.1.10:8443', 'http://192.168.1.10:8443'),
        ]) {
          test('allows $domain on $origin', () async {
            final result = await _revealForFill(
              identifiers: [
                DesktopBrowserAutofillServiceIdentifier(
                  type: 'domain',
                  value: domain,
                ),
              ],
              origin: origin,
            );

            expect(result.response['ok'], isTrue);
            expect(result.bridgeCalls, 1);
          });
        }
      });
    });

    test('revealForFill denies descriptor/database mismatch', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-native-host-',
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
              id: 'entry-123',
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
      final bridge = await _FakeRevealBridge.start(
        responseData: const {
          'entryId': 'entry-123',
          'username': 'alice',
          'password': 'super-secret',
        },
      );
      addTearDown(bridge.close);
      await store.writeBridgeDescriptor(bridge.descriptor(databaseId: 'db-2'));

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'reveal-mismatch',
        'type': 'revealForFill',
        'payload': {'entryId': 'entry-123', 'origin': 'https://example.com'},
      }, store: store);

      expect(response['ok'], isFalse);
      final error = response['error']! as Map<String, Object?>;
      expect(error['code'], 'database_mismatch');
      expect(bridge.requestCount, 0);
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
          cacheGeneration: 'cache-gen-1',
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
          cacheGeneration: 'cache-gen-1',
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
            cacheGeneration: 'cache-gen-1',
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

  group('009 A014 — popup fill eligibility', () {
    test('a host-level strong match the reveal policy would refuse is not '
        'presented as fillable', () async {
      final store = await _overlayStore(
        databaseId: 'db-a',
        cacheGeneration: 'cache-a',
        entries: [
          // Stored as https, so the popup policy refuses it on an http page
          // even though the host matches.
          _overlayEntry(id: 'https-only', exactOrigin: 'https://example.com'),
        ],
      );
      final bridge = await _FakeOverlayBridge.start();
      addTearDown(bridge.close);
      await store.writeBridgeDescriptor(
        bridge.descriptor(
          databaseId: 'db-a',
          cacheGeneration: 'cache-a',
          bridgeGeneration: 'bridge-a',
        ),
      );

      Future<Map<String, Object?>> queryAt(String url) async {
        final response = await handleNativeHostRequest({
          'version': nativeProtocolVersion,
          'id': 'popup-query',
          'type': 'queryCredentials',
          'payload': {'url': url, 'limit': 10},
        }, store: store);
        final data = response['data']! as Map<String, Object?>;
        return (data['strongMatches']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .single;
      }

      expect((await queryAt('https://example.com'))['fillEligible'], isTrue);
      expect((await queryAt('http://example.com'))['fillEligible'], isFalse);
    });

    test('nothing is fillable while the reveal bridge is absent', () async {
      final store = await _overlayStore(
        databaseId: 'db-a',
        cacheGeneration: 'cache-a',
        entries: [_overlayEntry()],
      );

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'popup-query-2',
        'type': 'queryCredentials',
        'payload': {'url': 'https://example.com'},
      }, store: store);

      final data = response['data']! as Map<String, Object?>;
      expect(data['fillAvailable'], isFalse);
      final strong = (data['strongMatches']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(strong.single['fillEligible'], isFalse);
    });
  });

  group('009 A008 — overlay capability negotiation', () {
    test('hello advertises the exact-origin capability and types', () async {
      final store = DesktopBrowserAutofillCacheStore(
        directory: await Directory.systemTemp.createTemp('kv-overlay-host-'),
      );
      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'hello-cap',
        'type': 'hello',
      }, store: store);

      final data = response['data']! as Map<String, Object?>;
      expect(data['capabilities'], contains('overlayExactOriginV1'));
      expect(data['supportedMessages'], contains('overlayQueryCredentials'));
      expect(data['supportedMessages'], contains('overlayRevealForFill'));
    });

    test('an old host cannot serve overlay requests at all', () async {
      // The overlay request types did not exist before this slice, so an old
      // host classifies them as unknown and refuses. Had the strict policy been
      // a new field on `revealForFill`, that same old host would have ignored
      // the field and revealed under the lenient rule.
      expect(
        _preSlice009MessageTypes,
        isNot(contains('overlayQueryCredentials')),
      );
      expect(_preSlice009MessageTypes, isNot(contains('overlayRevealForFill')));

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'old-host',
        'type': 'overlayRevealForFill',
        'payload': {'entryId': 'entry-1', 'origin': 'https://example.com'},
      }, store: DesktopBrowserAutofillCacheStore(directory: Directory.current));
      // Sanity: this host does support it, so the refusal above comes from the
      // frozen list, not from the current binary.
      expect(response['ok'], isFalse);
      expect(
        (response['error']! as Map<String, Object?>)['code'],
        isNot('unsupported_type'),
      );
    });
  });

  group('009 A010 — overlayQueryCredentials', () {
    test('returns bounded metadata with no username or password', () async {
      final store = await _overlayStore(
        databaseId: 'db-a',
        cacheGeneration: 'cache-a',
        entries: [
          _overlayEntry(),
          _overlayEntry(
            id: 'domain-only',
            domain: 'example.com',
            withExactOrigin: false,
          ),
          _overlayEntry(
            id: 'elsewhere',
            domain: 'other.example',
            exactOrigin: 'https://other.example',
          ),
        ],
      );
      final bridge = await _FakeOverlayBridge.start();
      addTearDown(bridge.close);
      await store.writeBridgeDescriptor(
        bridge.descriptor(
          databaseId: 'db-a',
          cacheGeneration: 'cache-a',
          bridgeGeneration: 'bridge-a',
        ),
      );

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'overlay-query-1',
        'type': 'overlayQueryCredentials',
        'payload': {
          'url': 'https://example.com/login?token=x#frag',
          'matchPolicy': overlayMatchPolicy,
          'limit': 10,
        },
      }, store: store);

      expect(response['ok'], isTrue);
      final data = response['data']! as Map<String, Object?>;
      expect(data['matchPolicy'], overlayMatchPolicy);
      expect(data['target'], 'https://example.com');
      expect(data['sessionBinding'], {
        'databaseId': 'db-a',
        'cacheGeneration': 'cache-a',
        'bridgeGeneration': 'bridge-a',
      });

      final items = (data['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(items, hasLength(2));
      final exact = items.firstWhere((i) => i['entryId'] == 'entry-1');
      expect(exact['matchType'], 'exact-origin');
      expect(exact['fillEligible'], isTrue);
      expect(exact.keys, [
        'entryId',
        'title',
        'displayService',
        'matchType',
        'fillEligible',
      ]);

      final possible = items.firstWhere((i) => i['entryId'] == 'domain-only');
      expect(possible['matchType'], 'possible');
      expect(possible['fillEligible'], isFalse);

      final encoded = jsonEncode(response);
      expect(encoded, isNot(contains('alice')));
      expect(encoded, isNot(contains('username')));
      expect(encoded, isNot(contains('password')));
      expect(encoded, isNot(contains('elsewhere')));
    });

    test('rejects a request that does not declare the strict policy', () async {
      final store = await _overlayStore(
        databaseId: 'db-a',
        cacheGeneration: 'cache-a',
        entries: [_overlayEntry()],
      );

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'overlay-query-2',
        'type': 'overlayQueryCredentials',
        'payload': {'url': 'https://example.com'},
      }, store: store);

      expect(response['ok'], isFalse);
      expect(
        (response['error']! as Map<String, Object?>)['code'],
        'invalid_request',
      );
    });

    test('nothing is fillable while the bridge is not current', () async {
      final store = await _overlayStore(
        databaseId: 'db-a',
        cacheGeneration: 'cache-a',
        entries: [_overlayEntry()],
      );

      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'overlay-query-3',
        'type': 'overlayQueryCredentials',
        'payload': {
          'url': 'https://example.com',
          'matchPolicy': overlayMatchPolicy,
        },
      }, store: store);

      final data = response['data']! as Map<String, Object?>;
      expect(data['fillAvailable'], isFalse);
      expect(data['sessionBinding'], isNull);
      final items = (data['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(items.single['fillEligible'], isFalse);
    });

    test('a republish during the query returns stale_session', () async {
      final store = await _overlayStore(
        databaseId: 'db-a',
        cacheGeneration: 'cache-a',
        entries: [_overlayEntry()],
      );
      final bridge = await _FakeOverlayBridge.start();
      addTearDown(bridge.close);
      await store.writeBridgeDescriptor(
        bridge.descriptor(
          databaseId: 'db-a',
          cacheGeneration: 'cache-a',
          bridgeGeneration: 'bridge-a',
        ),
      );

      // The re-read before responding is what catches this: the vault is
      // republished after the snapshot was taken but before the answer is
      // written. `_RepublishingStore` fires that republish deterministically on
      // the re-read.
      final response = await handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'overlay-query-4',
        'type': 'overlayQueryCredentials',
        'payload': {
          'url': 'https://example.com',
          'matchPolicy': overlayMatchPolicy,
        },
      }, store: _RepublishingStore(store));
      expect(response['ok'], isFalse);
      expect(
        (response['error']! as Map<String, Object?>)['code'],
        'stale_session',
      );
    });
  });

  group('009 A011 — overlayRevealForFill', () {
    late DesktopBrowserAutofillCacheStore store;
    late _FakeOverlayBridge bridge;

    Future<void> publish({
      String databaseId = 'db-a',
      String cacheGeneration = 'cache-a',
      String bridgeGeneration = 'bridge-a',
      List<DesktopBrowserAutofillCredentialMetadata>? entries,
    }) async {
      await store.writeMetadataCache(
        DesktopBrowserAutofillMetadataCache(
          version: desktopBrowserAutofillCacheVersion,
          databaseId: databaseId,
          cacheGeneration: cacheGeneration,
          generatedAtEpochMs: 1,
          entries: entries ?? [_overlayEntry()],
        ),
      );
      await store.writeBridgeDescriptor(
        bridge.descriptor(
          databaseId: databaseId,
          cacheGeneration: cacheGeneration,
          bridgeGeneration: bridgeGeneration,
        ),
      );
    }

    setUp(() async {
      store = DesktopBrowserAutofillCacheStore(
        directory: await Directory.systemTemp.createTemp('kv-overlay-host-'),
      );
      bridge = await _FakeOverlayBridge.start();
      addTearDown(bridge.close);
      await publish();
    });

    test('reveals for an exact origin and echoes the binding', () async {
      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
      );

      expect(response['ok'], isTrue);
      final data = response['data']! as Map<String, Object?>;
      expect(data['password'], _overlaySecret);
      expect(data['matchPolicy'], overlayMatchPolicy);
      expect(data['sessionBinding'], {
        'databaseId': 'db-a',
        'cacheGeneration': 'cache-a',
        'bridgeGeneration': 'bridge-a',
      });
      expect(bridge.lastPayload?['matchPolicy'], overlayMatchPolicy);
      expect(bridge.lastPayload?['origin'], 'https://example.com');
    });

    test('an implicit default port matches an explicit one', () async {
      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com:443',
      );
      expect(response['ok'], isTrue);
    });

    test('a domain-only entry can never reveal', () async {
      await publish(entries: [_overlayEntry(withExactOrigin: false)]);

      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
      );

      expect(response['ok'], isFalse);
      expect((response['error']! as Map<String, Object?>)['code'], 'forbidden');
      expect(bridge.requestCount, 0);
      _expectNoSecret(response);
    });

    for (final entry in const {
      'scheme': 'http://example.com',
      'non-default port': 'https://example.com:8443',
      'phishing suffix': 'https://example.com.evil.test',
      'www label': 'https://www.example.com',
      'm label': 'https://m.example.com',
      'mobile label': 'https://mobile.example.com',
    }.entries) {
      test('${entry.key} differs and is refused', () async {
        final response = await _overlayReveal(
          store: store,
          origin: entry.value,
        );

        expect(response['ok'], isFalse);
        final error = response['error']! as Map<String, Object?>;
        expect(error['code'], 'forbidden');
        expect(bridge.requestCount, 0, reason: 'the app is never contacted');
        _expectNoSecret(response);
        // The refusal must not disclose which rule rejected it.
        final message = (error['message']! as String).toLowerCase();
        for (final leak in const ['scheme', 'port', 'host', 'label', 'http']) {
          expect(message, isNot(contains(leak)));
        }
      });
    }

    for (final mismatch in const [
      ('databaseId', 'db-b', 'cache-a', 'bridge-a'),
      ('cacheGeneration', 'db-a', 'cache-b', 'bridge-a'),
      ('bridgeGeneration', 'db-a', 'cache-a', 'bridge-b'),
    ]) {
      test('${mismatch.$1} mismatch is stale_session before the app', () async {
        final response = await _overlayReveal(
          store: store,
          origin: 'https://example.com',
          databaseId: mismatch.$2,
          cacheGeneration: mismatch.$3,
          bridgeGeneration: mismatch.$4,
        );

        expect(response['ok'], isFalse);
        expect(
          (response['error']! as Map<String, Object?>)['code'],
          'stale_session',
        );
        expect(bridge.requestCount, 0);
        _expectNoSecret(response);
      });
    }

    test('a republish of the same vault invalidates an older grant', () async {
      // Same database, same entry, same origin — only the cache generation
      // moved. The grant minted before the republish must be dead anyway.
      await publish(cacheGeneration: 'cache-a2');

      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
        cacheGeneration: 'cache-a',
      );

      expect(
        (response['error']! as Map<String, Object?>)['code'],
        'stale_session',
      );
      expect(bridge.requestCount, 0);
      _expectNoSecret(response);
    });

    test('a bridge restart invalidates an older grant', () async {
      await publish(bridgeGeneration: 'bridge-a2');

      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
        bridgeGeneration: 'bridge-a',
      );

      expect(
        (response['error']! as Map<String, Object?>)['code'],
        'stale_session',
      );
      expect(bridge.requestCount, 0);
      _expectNoSecret(response);
    });

    test(
      'a delayed response is stale after a same-vault republish too',
      () async {
        // Weaker signal than a vault switch — the database id never changes —
        // so the post-response re-read has to compare the generations, not just
        // the database.
        bridge.onRequest = () async {
          await publish(cacheGeneration: 'cache-a2');
        };

        final response = await _overlayReveal(
          store: store,
          origin: 'https://example.com',
        );

        expect(
          (response['error']! as Map<String, Object?>)['code'],
          'stale_session',
        );
        _expectNoSecret(response);
      },
    );

    test('a request without the strict policy is refused', () async {
      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
        matchPolicy: 'host',
      );

      expect(response['ok'], isFalse);
      expect(
        (response['error']! as Map<String, Object?>)['code'],
        'invalid_request',
      );
      expect(bridge.requestCount, 0);
    });

    test('an app response that does not echo the binding is dropped', () async {
      bridge.overrideData = {
        'entryId': 'entry-1',
        'matchPolicy': overlayMatchPolicy,
        'origin': 'https://example.com',
        'databaseId': 'db-a',
        'cacheGeneration': 'cache-b',
        'bridgeGeneration': 'bridge-a',
        'username': 'alice',
        'password': _overlaySecret,
      };

      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
      );

      expect(response['ok'], isFalse);
      expect(
        (response['error']! as Map<String, Object?>)['code'],
        'app_bridge_invalid_response',
      );
      _expectNoSecret(response);
    });

    test('A013 — a delayed vault A response after a switch to vault B with the '
        'same entry UUID and origin is stale_session', () async {
      // The app answers under vault A's binding, but by the time it answers,
      // vault B — same entry UUID, same origin, different secret — is the
      // published one. Only the post-response re-read catches this.
      bridge.onRequest = () async {
        await publish(
          databaseId: 'db-b',
          cacheGeneration: 'cache-b',
          bridgeGeneration: 'bridge-b',
          entries: [_overlayEntry()],
        );
      };

      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
      );

      expect(response['ok'], isFalse);
      expect(
        (response['error']! as Map<String, Object?>)['code'],
        'stale_session',
      );
      _expectNoSecret(response);

      // And the old grant cannot be replayed against vault B either.
      final replay = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
      );
      expect(
        (replay['error']! as Map<String, Object?>)['code'],
        'stale_session',
      );
    });

    test('an app without the overlay endpoint fails closed', () async {
      // A pre-009 app bridge has no `/overlay-reveal`; it answers `not_found`
      // and the host must not retry on the lenient `/reveal`.
      await bridge.close();
      final legacy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => legacy.close(force: true));
      var revealCalls = 0;
      legacy.listen((request) async {
        if (request.uri.path == '/reveal') {
          revealCalls += 1;
        }
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(
          jsonEncode({
            'ok': false,
            'error': {'code': 'not_found'},
          }),
        );
        await request.response.close();
      });
      await store.writeBridgeDescriptor(
        DesktopBrowserAutofillBridgeDescriptor(
          version: desktopBrowserAutofillBridgeDescriptorVersion,
          port: legacy.port,
          token: bridge.token,
          databaseId: 'db-a',
          cacheGeneration: 'cache-a',
          bridgeGeneration: 'bridge-a',
          createdAtEpochMs: 1,
        ),
      );

      final response = await _overlayReveal(
        store: store,
        origin: 'https://example.com',
      );

      expect(response['ok'], isFalse);
      expect(revealCalls, 0);
      _expectNoSecret(response);
    });
  });
}

/// The v2 request types that existed before spec 009 Slice A1.
///
/// Frozen on purpose: it is the shape of a native host the user may still have
/// installed. The overlay types must be absent from it, because that absence is
/// what makes an old host answer `unsupported_type` instead of silently
/// applying the lenient host-only policy to an overlay request.
const _preSlice009MessageTypes = <String>[
  'hello',
  'status',
  'queryCredentials',
  'searchCredentials',
  'createPendingAssociation',
  'revealForFill',
];

const _overlaySecret = 'overlay-only-secret';

/// Republishes the vault the second time the metadata cache is read, i.e.
/// exactly on the "re-read immediately before responding" step of SR-4.
///
/// A subclass rather than a mock so that the production handler, the production
/// store and the production comparison all run unmodified.
class _RepublishingStore extends DesktopBrowserAutofillCacheStore {
  _RepublishingStore(this.delegate) : super(directory: delegate.directory);

  final DesktopBrowserAutofillCacheStore delegate;
  int reads = 0;

  @override
  Future<DesktopBrowserAutofillMetadataCache?> readMetadataCache() async {
    reads += 1;
    if (reads == 2) {
      await delegate.writeMetadataCache(
        DesktopBrowserAutofillMetadataCache(
          version: desktopBrowserAutofillCacheVersion,
          databaseId: 'db-a',
          cacheGeneration: 'cache-a2',
          generatedAtEpochMs: 2,
          entries: [_overlayEntry()],
        ),
      );
    }
    return super.readMetadataCache();
  }
}

Future<DesktopBrowserAutofillCacheStore> _overlayStore({
  required String databaseId,
  required String cacheGeneration,
  required List<DesktopBrowserAutofillCredentialMetadata> entries,
}) async {
  final store = DesktopBrowserAutofillCacheStore(
    directory: await Directory.systemTemp.createTemp('kv-overlay-host-'),
  );
  await store.writeMetadataCache(
    DesktopBrowserAutofillMetadataCache(
      version: desktopBrowserAutofillCacheVersion,
      databaseId: databaseId,
      cacheGeneration: cacheGeneration,
      generatedAtEpochMs: 1,
      entries: entries,
    ),
  );
  return store;
}

DesktopBrowserAutofillCredentialMetadata _overlayEntry({
  String id = 'entry-1',
  String exactOrigin = 'https://example.com',
  String domain = 'example.com',
  bool withExactOrigin = true,
}) {
  return DesktopBrowserAutofillCredentialMetadata(
    id: id,
    title: 'Example',
    username: 'alice',
    displayService: domain,
    serviceIdentifiers: [
      DesktopBrowserAutofillServiceIdentifier(type: 'domain', value: domain),
      if (withExactOrigin)
        DesktopBrowserAutofillServiceIdentifier(
          type: exactOriginServiceIdentifierType,
          value: exactOrigin,
        ),
    ],
    updatedAtEpochMs: 1,
  );
}

Future<Map<String, Object?>> _overlayReveal({
  required DesktopBrowserAutofillCacheStore store,
  required String origin,
  String entryId = 'entry-1',
  String databaseId = 'db-a',
  String cacheGeneration = 'cache-a',
  String bridgeGeneration = 'bridge-a',
  String matchPolicy = overlayMatchPolicy,
}) {
  return handleNativeHostRequest({
    'version': nativeProtocolVersion,
    'id': 'overlay-reveal-1',
    'type': 'overlayRevealForFill',
    'payload': {
      'entryId': entryId,
      'origin': origin,
      'matchPolicy': matchPolicy,
      'expectedDatabaseId': databaseId,
      'expectedCacheGeneration': cacheGeneration,
      'expectedBridgeGeneration': bridgeGeneration,
    },
  }, store: store);
}

void _expectNoSecret(Map<String, Object?> response) {
  final encoded = jsonEncode(response);
  expect(encoded, isNot(contains(_overlaySecret)));
  expect(encoded, isNot(contains('alice')));
}

/// Fake app bridge implementing `/overlay-reveal`.
///
/// Echoes the SR-4 binding exactly as the real app does, so the native host's
/// own echo validation is exercised rather than bypassed. [onRequest] runs
/// before the response is written and is how the delayed vault A -> B
/// regression swaps the published vault mid-flight.
class _FakeOverlayBridge {
  _FakeOverlayBridge._({required this.server, required this.token}) {
    server.listen(_handleRequest);
  }

  static Future<_FakeOverlayBridge> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeOverlayBridge._(
      server: server,
      token: 'fake-token-fake-token-fake-token-fake-token',
    );
  }

  final HttpServer server;
  final String token;
  int requestCount = 0;
  Map<String, Object?>? lastPayload;
  Future<void> Function()? onRequest;
  Map<String, Object?>? overrideData;

  DesktopBrowserAutofillBridgeDescriptor descriptor({
    required String databaseId,
    required String cacheGeneration,
    required String bridgeGeneration,
  }) {
    return DesktopBrowserAutofillBridgeDescriptor(
      version: desktopBrowserAutofillBridgeDescriptorVersion,
      port: server.port,
      token: token,
      databaseId: databaseId,
      cacheGeneration: cacheGeneration,
      bridgeGeneration: bridgeGeneration,
      createdAtEpochMs: 1,
    );
  }

  Future<void> close() async {
    await server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    requestCount += 1;
    request.response.headers.contentType = ContentType.json;
    if (request.method != 'POST' || request.uri.path != '/overlay-reveal') {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(
        jsonEncode({
          'ok': false,
          'error': {'code': 'not_found'},
        }),
      );
      await request.response.close();
      return;
    }
    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer $token') {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(
        jsonEncode({
          'ok': false,
          'error': {'code': 'unauthorized'},
        }),
      );
      await request.response.close();
      return;
    }

    final payload =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, Object?>;
    lastPayload = payload;
    await onRequest?.call();

    request.response.statusCode = HttpStatus.ok;
    request.response.write(
      jsonEncode({
        'ok': true,
        'data':
            overrideData ??
            {
              'entryId': payload['entryId'],
              'matchPolicy': payload['matchPolicy'],
              'origin': payload['origin'],
              'databaseId': payload['databaseId'],
              'cacheGeneration': payload['cacheGeneration'],
              'bridgeGeneration': payload['bridgeGeneration'],
              'username': 'alice',
              'password': _overlaySecret,
            },
      }),
    );
    await request.response.close();
  }
}

typedef _RevealAttempt = ({Map<String, Object?> response, int bridgeCalls});

Future<_RevealAttempt> _revealForFill({
  required List<DesktopBrowserAutofillServiceIdentifier> identifiers,
  required String origin,
}) async {
  final directory = await Directory.systemTemp.createTemp('kv-native-host-');
  final store = DesktopBrowserAutofillCacheStore(directory: directory);
  await store.writeMetadataCache(
    DesktopBrowserAutofillMetadataCache(
      version: desktopBrowserAutofillCacheVersion,
      databaseId: 'db-1',
      cacheGeneration: 'cache-gen-1',
      generatedAtEpochMs: 1,
      entries: [
        DesktopBrowserAutofillCredentialMetadata(
          id: 'entry-1',
          title: 'Example',
          username: 'alice',
          displayService: 'example.test',
          serviceIdentifiers: identifiers,
          updatedAtEpochMs: 1,
        ),
      ],
    ),
  );

  final bridge = await _FakeRevealBridge.start(
    responseData: const {
      'entryId': 'entry-1',
      'username': 'alice',
      'password': 'test-only-secret',
    },
  );
  addTearDown(bridge.close);
  await store.writeBridgeDescriptor(bridge.descriptor(databaseId: 'db-1'));

  final response = await handleNativeHostRequest({
    'version': nativeProtocolVersion,
    'id': 'reveal-origin',
    'type': 'revealForFill',
    'payload': {'entryId': 'entry-1', 'origin': origin},
  }, store: store);

  return (response: response, bridgeCalls: bridge.requestCount);
}

void _expectRevealRefused(_RevealAttempt attempt) {
  expect(attempt.response['ok'], isFalse);
  final error = attempt.response['error']! as Map<String, Object?>;
  expect(error['code'], 'strong_match_required');
  // The bridge must never be asked for the secret in the first place.
  expect(attempt.bridgeCalls, 0);
  final encoded = jsonEncode(attempt.response);
  expect(encoded, isNot(contains('test-only-secret')));
  expect(encoded, isNot(contains('alice')));
  // The refusal must not tell the caller which rule rejected it.
  final message = (error['message']! as String).toLowerCase();
  expect(message, isNot(contains('scheme')));
  expect(message, isNot(contains('http')));
  expect(message, isNot(contains('port')));
}

class _FakeRevealBridge {
  _FakeRevealBridge._({
    required this.server,
    required this.token,
    required this.responseData,
  }) {
    server.listen(_handleRequest);
  }

  static Future<_FakeRevealBridge> start({
    required Map<String, Object?> responseData,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeRevealBridge._(
      server: server,
      token: 'fake-token-fake-token-fake-token-fake-token',
      responseData: responseData,
    );
  }

  final HttpServer server;
  final String token;
  final Map<String, Object?> responseData;
  int requestCount = 0;
  Map<String, Object?>? lastPayload;

  DesktopBrowserAutofillBridgeDescriptor descriptor({
    required String databaseId,
  }) {
    return DesktopBrowserAutofillBridgeDescriptor(
      version: desktopBrowserAutofillBridgeDescriptorVersion,
      port: server.port,
      token: token,
      databaseId: databaseId,
      cacheGeneration: 'cache-gen-1',
      bridgeGeneration: 'bridge-gen-1',
      createdAtEpochMs: 1,
    );
  }

  Future<void> close() async {
    await server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    requestCount += 1;
    request.response.headers.contentType = ContentType.json;
    if (request.method != 'POST' || request.uri.path != '/reveal') {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(
        jsonEncode({
          'ok': false,
          'error': {'code': 'not_found'},
        }),
      );
      await request.response.close();
      return;
    }

    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer $token') {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(
        jsonEncode({
          'ok': false,
          'error': {'code': 'unauthorized'},
        }),
      );
      await request.response.close();
      return;
    }

    final payload = await utf8.decoder.bind(request).join();
    lastPayload = jsonDecode(payload) as Map<String, Object?>;
    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({'ok': true, 'data': responseData}));
    await request.response.close();
  }
}
