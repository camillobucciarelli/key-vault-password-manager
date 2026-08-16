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
