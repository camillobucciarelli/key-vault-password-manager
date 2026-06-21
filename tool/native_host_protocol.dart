import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

const nativeHostName = 'dev.camillobucciarelli.keyvault_native_host';
const nativeProtocolVersion = 2;
const maxNativeMessagePayloadBytes = 64 * 1024;

const supportedNativeMessageTypes = <String>[
  'hello',
  'status',
  'queryCredentials',
  'revealForFill',
];

const _sensitiveRequestKeys = <String>{
  'credential',
  'credentials',
  'databasepath',
  'keyfilepath',
  'masterpassword',
  'password',
  'secret',
  'secrets',
};

class NativeHostProtocolException implements Exception {
  const NativeHostProtocolException(
    this.code,
    this.publicMessage, {
    this.canContinue = false,
  });

  final String code;
  final String publicMessage;
  final bool canContinue;

  @override
  String toString() => 'NativeHostProtocolException($code)';
}

class NativeMessageStreamReader {
  NativeMessageStreamReader(
    Stream<List<int>> input, {
    this.maxPayloadBytes = maxNativeMessagePayloadBytes,
  }) : _iterator = StreamIterator<List<int>>(input);

  final int maxPayloadBytes;
  final StreamIterator<List<int>> _iterator;

  List<int>? _currentChunk;
  int _currentOffset = 0;

  Future<Map<String, Object?>?> readMessage() async {
    final header = await _readExactly(4, allowCleanEof: true);
    if (header == null) {
      return null;
    }

    final length = ByteData.sublistView(header).getUint32(0, Endian.little);
    if (length == 0) {
      throw const NativeHostProtocolException(
        'empty_payload',
        'Native message payload is empty.',
        canContinue: true,
      );
    }
    if (length > maxPayloadBytes) {
      throw NativeHostProtocolException(
        'payload_too_large',
        'Native message payload exceeds the v2 size limit.',
      );
    }

    final payload = await _readExactly(length);
    return decodeNativeMessagePayload(
      payload!,
      maxPayloadBytes: maxPayloadBytes,
    );
  }

  Future<Uint8List?> _readExactly(
    int byteCount, {
    bool allowCleanEof = false,
  }) async {
    final builder = BytesBuilder(copy: false);
    var remaining = byteCount;

    while (remaining > 0) {
      if (_currentChunk == null || _currentOffset >= _currentChunk!.length) {
        if (!await _iterator.moveNext()) {
          if (allowCleanEof && builder.length == 0) {
            return null;
          }
          throw const NativeHostProtocolException(
            'incomplete_frame',
            'Native message frame ended before all bytes were read.',
          );
        }
        _currentChunk = _iterator.current;
        _currentOffset = 0;
        if (_currentChunk!.isEmpty) {
          continue;
        }
      }

      final available = _currentChunk!.length - _currentOffset;
      final take = math.min(remaining, available);
      builder.add(
        _currentChunk!.sublist(_currentOffset, _currentOffset + take),
      );
      _currentOffset += take;
      remaining -= take;
    }

    return builder.takeBytes();
  }
}

Uint8List encodeNativeMessage(Map<String, Object?> message) {
  final jsonBytes = utf8.encode(jsonEncode(message));
  final header = ByteData(4)..setUint32(0, jsonBytes.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(jsonBytes))
      .toBytes();
}

Map<String, Object?> decodeNativeMessageFrame(
  Uint8List frame, {
  int maxPayloadBytes = maxNativeMessagePayloadBytes,
}) {
  if (frame.length < 4) {
    throw const NativeHostProtocolException(
      'incomplete_frame',
      'Native message frame is missing its length header.',
    );
  }
  final length = ByteData.sublistView(frame, 0, 4).getUint32(0, Endian.little);
  if (length == 0) {
    throw const NativeHostProtocolException(
      'empty_payload',
      'Native message payload is empty.',
      canContinue: true,
    );
  }
  if (length > maxPayloadBytes) {
    throw const NativeHostProtocolException(
      'payload_too_large',
      'Native message payload exceeds the v2 size limit.',
    );
  }
  if (frame.length - 4 < length) {
    throw const NativeHostProtocolException(
      'incomplete_frame',
      'Native message frame ended before all bytes were read.',
    );
  }
  return decodeNativeMessagePayload(
    Uint8List.sublistView(frame, 4, 4 + length),
    maxPayloadBytes: maxPayloadBytes,
  );
}

Map<String, Object?> decodeNativeMessagePayload(
  Uint8List payload, {
  int maxPayloadBytes = maxNativeMessagePayloadBytes,
}) {
  if (payload.isEmpty) {
    throw const NativeHostProtocolException(
      'empty_payload',
      'Native message payload is empty.',
      canContinue: true,
    );
  }
  if (payload.length > maxPayloadBytes) {
    throw const NativeHostProtocolException(
      'payload_too_large',
      'Native message payload exceeds the v2 size limit.',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(payload));
  } on FormatException {
    throw const NativeHostProtocolException(
      'invalid_json',
      'Native message payload is not valid JSON.',
      canContinue: true,
    );
  }

  final message = _asStringObjectMap(decoded);
  if (message == null) {
    throw const NativeHostProtocolException(
      'invalid_request',
      'Native message payload must be a JSON object.',
      canContinue: true,
    );
  }
  return message;
}

Map<String, Object?> handleNativeHostRequest(Map<String, Object?> request) {
  final id = _safeRequestId(request['id']);
  final type = _safeRequestType(request['type']);

  if (_containsSensitiveRequestKey(request)) {
    return nativeHostErrorResponse(
      id: id,
      type: type ?? 'error',
      code: 'legacy_fields_rejected',
      message:
          'Native Messaging v2 rejects legacy secret-bearing fields. Open and unlock KeyVault in the desktop app instead.',
    );
  }

  final version = request['version'] ?? request['v'];
  if (version != nativeProtocolVersion) {
    return nativeHostErrorResponse(
      id: id,
      type: type ?? 'error',
      code: 'unsupported_version',
      message: 'Unsupported Native Messaging protocol version.',
    );
  }

  if (type == null) {
    return nativeHostErrorResponse(
      id: id,
      type: 'error',
      code: 'invalid_request',
      message: 'Native Messaging v2 request type is missing or invalid.',
    );
  }

  if (!supportedNativeMessageTypes.contains(type)) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'unsupported_type',
      message: 'Unsupported Native Messaging v2 request type.',
    );
  }

  final payload = _readPayload(request);
  if (payload == null) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message:
          'Native Messaging v2 payload must be a JSON object when present.',
    );
  }

  return switch (type) {
    'hello' => _helloResponse(id: id, type: type),
    'status' => _statusResponse(id: id, type: type),
    'queryCredentials' => _queryCredentialsResponse(
      id: id,
      type: type,
      payload: payload,
    ),
    'revealForFill' => _revealForFillResponse(
      id: id,
      type: type,
      payload: payload,
    ),
    _ => nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'unsupported_type',
      message: 'Unsupported Native Messaging v2 request type.',
    ),
  };
}

Map<String, Object?> nativeHostErrorResponse({
  required String type,
  required String code,
  required String message,
  String? id,
}) {
  final response = <String, Object?>{
    'version': nativeProtocolVersion,
    'type': type,
    'ok': false,
    'error': {'code': code, 'message': message},
  };
  if (id != null) {
    response['id'] = id;
  }
  return response;
}

Map<String, Object?> _helloResponse({
  required String? id,
  required String type,
}) {
  return _successResponse(
    id: id,
    type: type,
    data: {..._statusData(), 'supportedMessages': supportedNativeMessageTypes},
  );
}

Map<String, Object?> _statusResponse({
  required String? id,
  required String type,
}) {
  return _successResponse(id: id, type: type, data: _statusData());
}

Map<String, Object?> _queryCredentialsResponse({
  required String? id,
  required String type,
  required Map<String, Object?> payload,
}) {
  final url = payload['url'];
  if (url is! String || url.trim().isEmpty || url.length > 4096) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'queryCredentials requires a non-empty url string.',
    );
  }

  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'queryCredentials only accepts http(s) page origins.',
    );
  }

  final limit = payload['limit'];
  if (limit != null && (limit is! int || limit < 1 || limit > 10)) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'queryCredentials limit must be an integer between 1 and 10.',
    );
  }

  return nativeHostErrorResponse(
    id: id,
    type: type,
    code: 'app_bridge_unavailable',
    message:
        'Native Messaging v2 is available, but the KeyVault app/vault bridge is not connected yet.',
  );
}

Map<String, Object?> _revealForFillResponse({
  required String? id,
  required String type,
  required Map<String, Object?> payload,
}) {
  final entryId = payload['entryId'];
  if (entryId is! String || entryId.trim().isEmpty || entryId.length > 256) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'revealForFill requires a non-empty entryId string.',
    );
  }

  return nativeHostErrorResponse(
    id: id,
    type: type,
    code: 'not_implemented',
    message:
        'Credential reveal/fill is intentionally disabled until the desktop app bridge and user-presence flow are implemented.',
  );
}

Map<String, Object?> _successResponse({
  required String? id,
  required String type,
  required Map<String, Object?> data,
}) {
  final response = <String, Object?>{
    'version': nativeProtocolVersion,
    'type': type,
    'ok': true,
    'data': data,
  };
  if (id != null) {
    response['id'] = id;
  }
  return response;
}

Map<String, Object?> _statusData() {
  return {
    'host': {
      'name': nativeHostName,
      'protocolVersion': nativeProtocolVersion,
      'status': 'available',
    },
    'appBridge': {
      'connected': false,
      'status': 'unavailable',
      'reason': 'app_bridge_unavailable',
    },
    'vault': {'connected': false, 'unlocked': false, 'status': 'not_connected'},
    'safeMode': true,
    'message':
        'Native Messaging v2 is running; it is not connected to the KeyVault vault yet.',
  };
}

Map<String, Object?>? _readPayload(Map<String, Object?> request) {
  if (!request.containsKey('payload') || request['payload'] == null) {
    return const <String, Object?>{};
  }
  return _asStringObjectMap(request['payload']);
}

Map<String, Object?>? _asStringObjectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      return null;
    }
    result[key] = entry.value as Object?;
  }
  return result;
}

String? _safeRequestId(Object? value) {
  if (value is! String || value.isEmpty || value.length > 128) {
    return null;
  }
  final isSafe = RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);
  return isSafe ? value : null;
}

String? _safeRequestType(Object? value) {
  if (value is! String || value.isEmpty || value.length > 64) {
    return null;
  }
  final isSafe = RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(value);
  return isSafe ? value : null;
}

bool _containsSensitiveRequestKey(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String && _sensitiveRequestKeys.contains(key.toLowerCase())) {
        return true;
      }
      if (_containsSensitiveRequestKey(entry.value)) {
        return true;
      }
    }
  } else if (value is Iterable) {
    for (final item in value) {
      if (_containsSensitiveRequestKey(item)) {
        return true;
      }
    }
  }
  return false;
}
