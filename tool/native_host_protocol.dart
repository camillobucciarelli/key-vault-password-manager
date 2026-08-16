import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';

const nativeHostName = 'dev.camillobucciarelli.keyvault_native_host';
const nativeProtocolVersion = 2;
const maxNativeMessagePayloadBytes = 64 * 1024;
const _maxRevealUsernameBytes = 4096;
const _maxRevealPasswordBytes = 32 * 1024;
const _revealBridgeTimeout = Duration(seconds: 2);

const supportedNativeMessageTypes = <String>[
  'hello',
  'status',
  'queryCredentials',
  'searchCredentials',
  'createPendingAssociation',
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

Future<Map<String, Object?>> handleNativeHostRequest(
  Map<String, Object?> request, {
  DesktopBrowserAutofillCacheStore? store,
}) async {
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

  final effectiveStore = store ?? DesktopBrowserAutofillCacheStore();

  return switch (type) {
    'hello' => await _helloResponse(id: id, type: type, store: effectiveStore),
    'status' => await _statusResponse(
      id: id,
      type: type,
      store: effectiveStore,
    ),
    'queryCredentials' => await _queryCredentialsResponse(
      id: id,
      type: type,
      payload: payload,
      store: effectiveStore,
    ),
    'searchCredentials' => await _searchCredentialsResponse(
      id: id,
      type: type,
      payload: payload,
      store: effectiveStore,
    ),
    'createPendingAssociation' => await _createPendingAssociationResponse(
      id: id,
      type: type,
      payload: payload,
      store: effectiveStore,
    ),
    'revealForFill' => await _revealForFillResponse(
      id: id,
      type: type,
      payload: payload,
      store: effectiveStore,
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

Future<Map<String, Object?>> _helloResponse({
  required String? id,
  required String type,
  required DesktopBrowserAutofillCacheStore store,
}) async {
  return _successResponse(
    id: id,
    type: type,
    data: {
      ...await _statusData(store),
      'supportedMessages': supportedNativeMessageTypes,
    },
  );
}

Future<Map<String, Object?>> _statusResponse({
  required String? id,
  required String type,
  required DesktopBrowserAutofillCacheStore store,
}) async {
  return _successResponse(id: id, type: type, data: await _statusData(store));
}

Future<Map<String, Object?>> _queryCredentialsResponse({
  required String? id,
  required String type,
  required Map<String, Object?> payload,
  required DesktopBrowserAutofillCacheStore store,
}) async {
  final pageTarget = _pageTargetFromPayload(payload);
  if (pageTarget == null) {
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

  final cache = await store.readMetadataCache();
  if (cache == null) {
    return _cacheUnavailableResponse(id: id, type: type);
  }
  final bridgeAvailable = await _isRevealBridgeAvailableForCache(store, cache);

  final strongMatches =
      cache.entries
          .where((entry) => _isStrongBrowserMatch(entry, pageTarget))
          .toList(growable: false)
        ..sort(_compareMetadataByDisplay);
  final strongIds = strongMatches.map((entry) => entry.id).toSet();
  final possibleMatches = strongMatches.isEmpty
      ? _possibleMatches(
          entries: cache.entries
              .where((entry) => !strongIds.contains(entry.id))
              .toList(growable: false),
          pageTarget: pageTarget,
          pageTitle: _safeOptionalString(payload['title'], maxLength: 512),
          limit: limit is int ? limit : 5,
        )
      : const <DesktopBrowserAutofillCredentialMetadata>[];

  return _successResponse(
    id: id,
    type: type,
    data: {
      'metadataOnly': true,
      'fillAvailable': bridgeAvailable,
      'databaseId': cache.databaseId,
      'generatedAtEpochMs': cache.generatedAtEpochMs,
      'target': pageTarget.toJson(),
      'strongMatches': strongMatches
          .take(limit is int ? limit : 5)
          .map((entry) => _metadataResult(entry, 'strong'))
          .toList(growable: false),
      'possibleMatches': possibleMatches
          .map((entry) => _metadataResult(entry, 'possible'))
          .toList(growable: false),
      'message': bridgeAvailable
          ? 'Desktop browser v2 returned metadata. Exact strong matches can be filled after popup user action.'
          : 'Desktop browser v2 returned metadata only. Unlock KeyVault desktop to enable one-shot fill.',
    },
  );
}

Future<Map<String, Object?>> _searchCredentialsResponse({
  required String? id,
  required String type,
  required Map<String, Object?> payload,
  required DesktopBrowserAutofillCacheStore store,
}) async {
  final query = _safeOptionalString(payload['query'], maxLength: 256) ?? '';
  final limit = payload['limit'];
  if (limit != null && (limit is! int || limit < 1 || limit > 50)) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'searchCredentials limit must be an integer between 1 and 50.',
    );
  }
  final cache = await store.readMetadataCache();
  if (cache == null) {
    return _cacheUnavailableResponse(id: id, type: type);
  }

  final pageTarget = _pageTargetFromPayload(payload, isRequired: false);
  final results = _manualSearch(
    entries: cache.entries,
    query: query,
    limit: limit is int ? limit : 25,
  );

  return _successResponse(
    id: id,
    type: type,
    data: {
      'metadataOnly': true,
      'fillAvailable': false,
      'databaseId': cache.databaseId,
      'generatedAtEpochMs': cache.generatedAtEpochMs,
      if (pageTarget != null) 'target': pageTarget.toJson(),
      'results': results
          .map((entry) => _metadataResult(entry, 'manual'))
          .toList(growable: false),
      'message':
          'Global search returned metadata only. Selecting a result creates a pending association for app confirmation.',
    },
  );
}

Future<Map<String, Object?>> _createPendingAssociationResponse({
  required String? id,
  required String type,
  required Map<String, Object?> payload,
  required DesktopBrowserAutofillCacheStore store,
}) async {
  final entryId = payload['entryId'];
  if (entryId is! String || entryId.trim().isEmpty || entryId.length > 256) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'createPendingAssociation requires a non-empty entryId string.',
    );
  }

  final target = _pageTargetFromPayload(payload);
  if (target == null) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message:
          'createPendingAssociation only accepts http(s) page origins for the target.',
    );
  }

  final pending = await store.savePendingAssociation(
    entryId: entryId,
    target: target,
  );
  if (pending == null) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'pending_association_failed',
      message:
          'Unable to create pending association. Open and unlock KeyVault, then try again.',
    );
  }

  return _successResponse(
    id: id,
    type: type,
    data: {
      'pendingAssociation': pending.toJson(),
      'message':
          'Pending association saved. Confirm or reject it in the KeyVault desktop app.',
    },
  );
}

Future<Map<String, Object?>> _revealForFillResponse({
  required String? id,
  required String type,
  required Map<String, Object?> payload,
  required DesktopBrowserAutofillCacheStore store,
}) async {
  final entryId = payload['entryId'];
  if (entryId is! String || entryId.trim().isEmpty || entryId.length > 256) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'revealForFill requires a non-empty entryId string.',
    );
  }

  final origin = _browserOriginFromPayload(payload);
  if (origin == null) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'revealForFill requires the current http(s) tab origin.',
    );
  }

  final target = DesktopBrowserAutofillMetadataMapper.targetFromUrl(origin);
  if (target == null) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'invalid_request',
      message: 'revealForFill origin is invalid.',
    );
  }

  final cache = await store.readMetadataCache();
  if (cache == null) {
    return _cacheUnavailableResponse(id: id, type: type);
  }

  final entry = cache.entries
      .where((candidate) => candidate.id == entryId.trim())
      .firstOrNull;
  if (entry == null) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'credential_unavailable',
      message: 'Requested credential metadata is unavailable.',
    );
  }

  if (!_isStrongBrowserMatch(entry, target, origin: origin)) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'strong_match_required',
      message:
          'Credential reveal requires an exact strong match for the current site.',
    );
  }

  final descriptor = await store.readBridgeDescriptor();
  if (descriptor == null) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'app_bridge_unavailable',
      message:
          'KeyVault reveal bridge is unavailable. Open and unlock the desktop app first.',
    );
  }
  if (descriptor.databaseId != cache.databaseId) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: 'database_mismatch',
      message: 'KeyVault database changed. Query the current site again.',
    );
  }

  final reveal = await _requestRevealFromAppBridge(
    descriptor: descriptor,
    databaseId: cache.databaseId,
    entryId: entryId.trim(),
    origin: origin,
  );
  if (reveal.errorCode != null) {
    return nativeHostErrorResponse(
      id: id,
      type: type,
      code: reveal.errorCode!,
      message: _publicRevealErrorMessage(reveal.errorCode!),
    );
  }

  return _successResponse(
    id: id,
    type: type,
    data: {
      'entryId': reveal.entryId,
      'username': reveal.username,
      'password': reveal.password,
    },
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

Future<Map<String, Object?>> _statusData(
  DesktopBrowserAutofillCacheStore store,
) async {
  final status = await store.status();
  final bridgeStatus = status.revealBridgeAvailable
      ? 'available'
      : status.cacheAvailable
      ? 'metadata_cache_available'
      : 'unavailable';
  return {
    'host': {
      'name': nativeHostName,
      'protocolVersion': nativeProtocolVersion,
      'status': 'available',
    },
    'appBridge': {
      'connected': status.revealBridgeAvailable,
      'status': bridgeStatus,
      'reason': status.revealBridgeAvailable
          ? null
          : status.cacheAvailable
          ? 'reveal_bridge_unavailable'
          : 'app_bridge_unavailable',
      'revealBridgeAvailable': status.revealBridgeAvailable,
      'createdAtEpochMs': status.revealBridgeCreatedAtEpochMs,
    },
    'vault': {
      'connected': status.cacheAvailable,
      'unlocked': status.cacheAvailable,
      'status': status.cacheAvailable
          ? 'metadata_cache_available'
          : 'not_connected',
      'metadataCount': status.metadataCount,
      'databaseId': status.databaseId,
      'generatedAtEpochMs': status.generatedAtEpochMs,
    },
    'safeMode': false,
    'metadataOnly': !status.revealBridgeAvailable,
    'cacheDirectory': status.directoryPath,
    'message': status.revealBridgeAvailable
        ? 'Native Messaging v2 can fill exact strong matches after popup user action.'
        : status.cacheAvailable
        ? 'Native Messaging v2 can read metadata, but reveal bridge is unavailable. Unlock KeyVault desktop.'
        : 'Native Messaging v2 is running; open and unlock KeyVault to publish desktop browser metadata.',
  };
}

Map<String, Object?> _cacheUnavailableResponse({
  required String? id,
  required String type,
}) {
  return nativeHostErrorResponse(
    id: id,
    type: type,
    code: 'app_bridge_unavailable',
    message:
        'KeyVault desktop metadata cache is unavailable. Open and unlock the desktop app first.',
  );
}

Future<bool> _isRevealBridgeAvailableForCache(
  DesktopBrowserAutofillCacheStore store,
  DesktopBrowserAutofillMetadataCache cache,
) async {
  final descriptor = await store.readBridgeDescriptor();
  return descriptor != null && descriptor.databaseId == cache.databaseId;
}

String? _browserOriginFromPayload(Map<String, Object?> payload) {
  final rawOrigin = payload['origin'] ?? payload['url'];
  if (rawOrigin is! String ||
      rawOrigin.trim().isEmpty ||
      rawOrigin.length > 4096) {
    return null;
  }
  final uri = Uri.tryParse(rawOrigin.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final host = DesktopBrowserAutofillMetadataMapper.normalizedHost(uri.host);
  if (host == null) {
    return null;
  }
  return Uri(
    scheme: uri.scheme.toLowerCase(),
    host: host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}

Future<_RevealBridgeResult> _requestRevealFromAppBridge({
  required DesktopBrowserAutofillBridgeDescriptor descriptor,
  required String databaseId,
  required String entryId,
  required String origin,
}) async {
  final client = HttpClient()
    ..connectionTimeout = _revealBridgeTimeout
    ..findProxy = (_) => 'DIRECT';
  try {
    final uri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: descriptor.port,
      path: '/reveal',
    );
    final request = await client.postUrl(uri).timeout(_revealBridgeTimeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${descriptor.token}',
    );
    request.write(
      jsonEncode({
        'version': desktopBrowserAutofillBridgeDescriptorVersion,
        'databaseId': databaseId,
        'entryId': entryId,
        'origin': origin,
      }),
    );

    final response = await request.close().timeout(_revealBridgeTimeout);
    final bytes = await _readHttpResponseBytes(
      response,
      maxNativeMessagePayloadBytes,
    ).timeout(_revealBridgeTimeout);
    final decoded = _decodeBridgeResponse(bytes);
    if (decoded == null) {
      return const _RevealBridgeResult.error('app_bridge_invalid_response');
    }

    if (response.statusCode != HttpStatus.ok) {
      final code = _safeBridgeErrorCode(decoded);
      return _RevealBridgeResult.error(code ?? 'app_bridge_error');
    }

    final data = _asStringObjectMap(decoded['data']);
    final returnedEntryId = data?['entryId'];
    final username = data?['username'];
    final password = data?['password'];
    if (returnedEntryId != entryId ||
        username is! String ||
        password is! String ||
        utf8.encode(username).length > _maxRevealUsernameBytes ||
        utf8.encode(password).length > _maxRevealPasswordBytes) {
      return const _RevealBridgeResult.error('app_bridge_invalid_response');
    }

    return _RevealBridgeResult.success(
      entryId: returnedEntryId as String,
      username: username,
      password: password,
    );
  } on TimeoutException {
    return const _RevealBridgeResult.error('app_bridge_timeout');
  } on SocketException {
    return const _RevealBridgeResult.error('app_bridge_unavailable');
  } on HttpException {
    return const _RevealBridgeResult.error('app_bridge_error');
  } catch (_) {
    return const _RevealBridgeResult.error('app_bridge_error');
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _readHttpResponseBytes(
  HttpClientResponse response,
  int maxBytes,
) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
    if (builder.length > maxBytes) {
      throw const HttpException('response_too_large');
    }
  }
  return builder.takeBytes();
}

Map<String, Object?>? _decodeBridgeResponse(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxNativeMessagePayloadBytes) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    return null;
  }
  return _asStringObjectMap(decoded);
}

String? _safeBridgeErrorCode(Map<String, Object?> response) {
  final error = _asStringObjectMap(response['error']);
  final code = error?['code'];
  if (code is! String || code.isEmpty || code.length > 64) {
    return null;
  }
  return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(code) ? code : null;
}

DesktopBrowserAutofillAssociationTarget? _pageTargetFromPayload(
  Map<String, Object?> payload, {
  bool isRequired = true,
}) {
  final rawUrl = payload['url'];
  if (rawUrl == null && !isRequired) {
    return null;
  }
  if (rawUrl is! String || rawUrl.trim().isEmpty || rawUrl.length > 4096) {
    return null;
  }
  final uri = Uri.tryParse(rawUrl);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return DesktopBrowserAutofillMetadataMapper.targetFromUrl(rawUrl);
}

bool _isStrongBrowserMatch(
  DesktopBrowserAutofillCredentialMetadata entry,
  DesktopBrowserAutofillAssociationTarget target, {
  String? origin,
}) {
  if (origin != null) {
    // Reveal path: the page origin must be authorized as a whole (scheme, host
    // and port), never by host alone.
    return DesktopBrowserAutofillMetadataMapper.isRevealAuthorizedOrigin(
      serviceIdentifiers: entry.serviceIdentifiers,
      origin: origin,
    );
  }
  // Metadata-only path (queryCredentials): no secret leaves the host, and the
  // caller only supplies a host target, so a host match stays sufficient.
  for (final identifier in entry.serviceIdentifiers) {
    if (identifier.type == 'domain' || identifier.type == 'url') {
      final host = DesktopBrowserAutofillMetadataMapper.normalizedHost(
        identifier.value,
      );
      if (host != null && host == target.value) {
        return true;
      }
    }
  }
  return false;
}

List<DesktopBrowserAutofillCredentialMetadata> _possibleMatches({
  required List<DesktopBrowserAutofillCredentialMetadata> entries,
  required DesktopBrowserAutofillAssociationTarget pageTarget,
  required String? pageTitle,
  required int limit,
}) {
  final rawTargets = <String>[pageTarget.value];
  if (pageTitle != null) {
    rawTargets.add(pageTitle);
  }
  final tokens = _targetTokens(rawTargets);
  if (tokens.isEmpty || limit <= 0) {
    return const [];
  }
  return _rankedSearch(
    entries: entries,
    tokens: tokens,
    includeUsername: false,
    requireAllTokens: false,
    limit: limit,
  );
}

List<DesktopBrowserAutofillCredentialMetadata> _manualSearch({
  required List<DesktopBrowserAutofillCredentialMetadata> entries,
  required String query,
  required int limit,
}) {
  if (limit <= 0) {
    return const [];
  }
  final tokens = _manualSearchTokens(query);
  if (tokens.isEmpty) {
    return (List<DesktopBrowserAutofillCredentialMetadata>.of(
      entries,
    )..sort(_compareMetadataByDisplay)).take(limit).toList(growable: false);
  }
  return _rankedSearch(
    entries: entries,
    tokens: tokens,
    includeUsername: true,
    requireAllTokens: true,
    limit: limit,
  );
}

List<DesktopBrowserAutofillCredentialMetadata> _rankedSearch({
  required List<DesktopBrowserAutofillCredentialMetadata> entries,
  required List<String> tokens,
  required bool includeUsername,
  required bool requireAllTokens,
  required int limit,
}) {
  final scored = <_ScoredMetadata>[];
  for (final entry in entries) {
    final score = _scoreMetadataEntry(
      entry: entry,
      tokens: tokens,
      includeUsername: includeUsername,
      requireAllTokens: requireAllTokens,
    );
    if (score > 0) {
      scored.add(_ScoredMetadata(entry: entry, score: score));
    }
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) {
      return byScore;
    }
    return _compareMetadataByDisplay(a.entry, b.entry);
  });
  return scored.take(limit).map((match) => match.entry).toList(growable: false);
}

int _scoreMetadataEntry({
  required DesktopBrowserAutofillCredentialMetadata entry,
  required List<String> tokens,
  required bool includeUsername,
  required bool requireAllTokens,
}) {
  final fields = <_WeightedSearchField>[
    _WeightedSearchField(entry.title, 6),
    _WeightedSearchField(entry.displayService, 8),
    if (includeUsername) _WeightedSearchField(entry.username, 5),
  ];
  for (final identifier in entry.serviceIdentifiers) {
    fields.add(_WeightedSearchField(identifier.value, 9));
    if (identifier.type == 'domain' || identifier.type == 'url') {
      final host = DesktopBrowserAutofillMetadataMapper.normalizedHost(
        identifier.value,
      );
      if (host != null) {
        fields.add(_WeightedSearchField(host, 10));
      }
    }
  }

  var total = 0;
  var matchedTokens = 0;
  for (final token in tokens) {
    int? bestScore;
    for (final field in fields) {
      final value = _normalizedSearchValue(field.value);
      if (!value.contains(token)) {
        continue;
      }
      var score = field.weight;
      if (value == token) {
        score += 12;
      } else if (value.startsWith(token)) {
        score += 6;
      } else if (_containsComponentPrefix(token, value)) {
        score += 4;
      }
      bestScore = bestScore == null ? score : math.max(bestScore, score);
    }
    if (bestScore != null) {
      total += bestScore;
      matchedTokens += 1;
    } else if (requireAllTokens) {
      return 0;
    }
  }
  return matchedTokens > 0 ? total + (matchedTokens * 2) : 0;
}

Map<String, Object?> _metadataResult(
  DesktopBrowserAutofillCredentialMetadata entry,
  String matchType,
) {
  return {
    'entryId': entry.id,
    'title': entry.title,
    'displayService': entry.displayService,
    'matchType': matchType,
  };
}

List<String> _targetTokens(Iterable<String> rawValues) {
  final tokens = <String>[];
  final seen = <String>{};
  for (final rawValue in rawValues) {
    for (final token in _tokensFromRawValue(rawValue)) {
      if (seen.add(token)) {
        tokens.add(token);
      }
    }
  }
  return tokens;
}

List<String> _manualSearchTokens(String query) {
  final normalized = _normalizedSearchValue(query);
  if (normalized.isEmpty) {
    return const [];
  }
  return normalized
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

List<String> _tokensFromRawValue(String rawValue) {
  final normalized = _normalizedSearchValue(rawValue);
  if (normalized.isEmpty) {
    return const [];
  }
  return normalized
      .split(RegExp(r'[.\-_/:\\\s]+'))
      .map((token) => token.replaceAll(RegExp(r'^[^a-z0-9]+|[^a-z0-9]+$'), ''))
      .where((token) => token.length >= 3)
      .where((token) => !_genericTargetTokens.contains(token))
      .toList(growable: false);
}

String _normalizedSearchValue(String value) {
  return value.trim().toLowerCase();
}

bool _containsComponentPrefix(String token, String value) {
  return value
      .split(RegExp(r'[.\-_/:\\\s]+'))
      .any((component) => component.startsWith(token));
}

String? _safeOptionalString(Object? value, {required int maxLength}) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed.length <= maxLength
      ? trimmed
      : trimmed.substring(0, maxLength);
}

int _compareMetadataByDisplay(
  DesktopBrowserAutofillCredentialMetadata left,
  DesktopBrowserAutofillCredentialMetadata right,
) {
  return left.sortKey.compareTo(right.sortKey);
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

String _publicRevealErrorMessage(String code) {
  return switch (code) {
    'app_bridge_timeout' => 'KeyVault reveal bridge timed out.',
    'app_bridge_unavailable' =>
      'KeyVault reveal bridge is unavailable. Open and unlock the desktop app.',
    'app_bridge_invalid_response' =>
      'KeyVault reveal bridge returned an invalid response.',
    'database_mismatch' => 'KeyVault database changed. Query the site again.',
    'credential_unavailable' => 'Requested credential is unavailable.',
    'strong_match_required' =>
      'Credential reveal requires an exact strong match for the current site.',
    'invalid_request' => 'Reveal request is invalid.',
    'unauthorized' => 'KeyVault reveal bridge authentication failed.',
    _ => 'KeyVault reveal bridge failed.',
  };
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

const _genericTargetTokens = <String>{
  'www',
  'com',
  'net',
  'org',
  'login',
  'signin',
  'sign',
  'auth',
  'account',
  'accounts',
  'http',
  'https',
  'mobile',
  'app',
};

class _WeightedSearchField {
  const _WeightedSearchField(this.value, this.weight);

  final String value;
  final int weight;
}

class _ScoredMetadata {
  const _ScoredMetadata({required this.entry, required this.score});

  final DesktopBrowserAutofillCredentialMetadata entry;
  final int score;
}

class _RevealBridgeResult {
  const _RevealBridgeResult.success({
    required this.entryId,
    required this.username,
    required this.password,
  }) : errorCode = null;

  const _RevealBridgeResult.error(this.errorCode)
    : entryId = null,
      username = null,
      password = null;

  final String? entryId;
  final String? username;
  final String? password;
  final String? errorCode;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
