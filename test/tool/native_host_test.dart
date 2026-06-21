import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

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
    test('hello returns host metadata and safe-mode status', () {
      final response = handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'hello-1',
        'type': 'hello',
      });

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
      expect(data['supportedMessages'], contains('revealForFill'));
    });

    test('queryCredentials returns a safe app bridge error, never secrets', () {
      final response = handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'query-1',
        'type': 'queryCredentials',
        'payload': {'url': 'https://example.com', 'limit': 5},
      });

      expect(response['ok'], isFalse);
      expect(response['type'], 'queryCredentials');
      final error = response['error']! as Map<String, Object?>;
      expect(error['code'], 'app_bridge_unavailable');

      final encoded = jsonEncode(response);
      expect(encoded, isNot(contains('hunter2')));
      expect(encoded, isNot(contains('passwordValue')));
      expect(encoded, isNot(contains('credentials":[')));
    });

    test('revealForFill is schema-validated but not implemented', () {
      final response = handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'reveal-1',
        'type': 'revealForFill',
        'payload': {'entryId': 'entry-123'},
      });

      expect(response['ok'], isFalse);
      final error = response['error']! as Map<String, Object?>;
      expect(error['code'], 'not_implemented');
    });

    test('rejects legacy secret-bearing request fields', () {
      final response = handleNativeHostRequest({
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

    test('rejects unsupported message types', () {
      final response = handleNativeHostRequest({
        'version': nativeProtocolVersion,
        'id': 'bad-1',
        'type': 'findCredentials',
      });

      expect(response['ok'], isFalse);
      final error = response['error']! as Map<String, Object?>;
      expect(error['code'], 'unsupported_type');
    });
  });
}
