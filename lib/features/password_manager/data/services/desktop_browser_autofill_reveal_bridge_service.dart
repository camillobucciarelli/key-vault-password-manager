import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../domain/models/vault_entry.dart';
import 'desktop_browser_autofill_cache.dart';

const _maxRevealRequestBytes = 4096;

class DesktopBrowserAutofillRevealBridgeService {
  DesktopBrowserAutofillRevealBridgeService({
    required this.store,
    required this.mapper,
  });

  final DesktopBrowserAutofillCacheStore store;
  final DesktopBrowserAutofillMetadataMapper mapper;

  HttpServer? _server;
  String? _databaseId;
  String? _token;
  Map<String, _DesktopBrowserRevealCredential> _credentials = const {};

  Future<void> start({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    if (store.directory == null) {
      return;
    }

    await stop();

    final databaseId = DesktopBrowserAutofillMetadataMapper.databaseIdForPath(
      databasePath,
    );
    final credentials = _credentialsFromEntries(entries);
    final token = _newBridgeToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    _server = server;
    _databaseId = databaseId;
    _token = token;
    _credentials = credentials;

    try {
      await store.writeBridgeDescriptor(
        DesktopBrowserAutofillBridgeDescriptor(
          version: desktopBrowserAutofillBridgeDescriptorVersion,
          port: server.port,
          token: token,
          databaseId: databaseId,
          createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      await stop();
      rethrow;
    }

    unawaited(_serve(server));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _databaseId = null;
    _token = null;
    _credentials = const {};

    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
    await store.clearBridgeDescriptor();
  }

  Map<String, _DesktopBrowserRevealCredential> _credentialsFromEntries(
    List<VaultEntry> entries,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <String, _DesktopBrowserRevealCredential>{};
    for (final entry in entries) {
      final credential = _DesktopBrowserRevealCredential.fromEntry(
        entry,
        mapper: mapper,
        updatedAtEpochMs: now,
      );
      if (credential != null) {
        result[credential.id] = credential;
      }
    }
    return Map<String, _DesktopBrowserRevealCredential>.unmodifiable(result);
  }

  Future<void> _serve(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request));
      }
    } catch (_) {}
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    try {
      if (request.method != 'POST' ||
          (request.uri.path != '/reveal' && request.uri.path != '/status')) {
        await _writeError(request, HttpStatus.notFound, 'not_found');
        return;
      }

      final remoteAddress = request.connectionInfo?.remoteAddress;
      if (remoteAddress == null || !remoteAddress.isLoopback) {
        await _writeError(request, HttpStatus.forbidden, 'forbidden');
        return;
      }

      if (!_isAuthorized(
        request.headers.value(HttpHeaders.authorizationHeader),
      )) {
        await _writeError(request, HttpStatus.unauthorized, 'unauthorized');
        return;
      }

      if (request.uri.path == '/status') {
        await _writeJson(request, HttpStatus.ok, {
          'ok': true,
          'data': {'databaseId': _databaseId},
        });
        return;
      }

      final payload = await _readJsonPayload(request);
      if (payload == null) {
        await _writeError(request, HttpStatus.badRequest, 'invalid_request');
        return;
      }

      final databaseId = _safeString(payload['databaseId'], maxLength: 128);
      if (databaseId == null || databaseId != _databaseId) {
        await _writeError(request, HttpStatus.conflict, 'database_mismatch');
        return;
      }

      final entryId = _safeString(payload['entryId'], maxLength: 256);
      final origin = _canonicalBrowserOrigin(payload['origin']);
      if (entryId == null || origin == null) {
        await _writeError(request, HttpStatus.badRequest, 'invalid_request');
        return;
      }

      final credential = _credentials[entryId];
      if (credential == null) {
        await _writeError(
          request,
          HttpStatus.notFound,
          'credential_unavailable',
        );
        return;
      }

      if (!_isExactBrowserMatch(credential, origin)) {
        await _writeError(
          request,
          HttpStatus.forbidden,
          'strong_match_required',
        );
        return;
      }

      await _writeJson(request, HttpStatus.ok, {
        'ok': true,
        'data': {
          'entryId': credential.id,
          'username': credential.username,
          'password': credential.password,
        },
      });
    } catch (_) {
      await _writeError(
        request,
        HttpStatus.internalServerError,
        'bridge_error',
      );
    }
  }

  bool _isAuthorized(String? header) {
    final token = _token;
    if (token == null || header == null || !header.startsWith('Bearer ')) {
      return false;
    }
    return _constantTimeEquals(header.substring(7), token);
  }

  Future<Map<String, Object?>?> _readJsonPayload(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > _maxRevealRequestBytes) {
        return null;
      }
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final result = <String, Object?>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is! String) {
        return null;
      }
      result[key] = entry.value as Object?;
    }
    return result;
  }

  Future<void> _writeError(
    HttpRequest request,
    int statusCode,
    String code,
  ) async {
    await _writeJson(request, statusCode, {
      'ok': false,
      'error': {'code': code, 'message': _publicErrorMessage(code)},
    });
  }

  Future<void> _writeJson(
    HttpRequest request,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    request.response.statusCode = statusCode;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

class _DesktopBrowserRevealCredential {
  const _DesktopBrowserRevealCredential({
    required this.id,
    required this.username,
    required this.password,
    required this.serviceIdentifiers,
  });

  static _DesktopBrowserRevealCredential? fromEntry(
    VaultEntry entry, {
    required DesktopBrowserAutofillMetadataMapper mapper,
    required int updatedAtEpochMs,
  }) {
    final metadata = mapper.mapEntry(entry, updatedAtEpochMs: updatedAtEpochMs);
    if (metadata == null) {
      return null;
    }
    return _DesktopBrowserRevealCredential(
      id: metadata.id,
      username: entry.username,
      password: entry.password,
      serviceIdentifiers: metadata.serviceIdentifiers,
    );
  }

  final String id;
  final String username;
  final String password;
  final List<DesktopBrowserAutofillServiceIdentifier> serviceIdentifiers;
}

bool _isExactBrowserMatch(
  _DesktopBrowserRevealCredential credential,
  String origin,
) {
  return DesktopBrowserAutofillMetadataMapper.isRevealAuthorizedOrigin(
    serviceIdentifiers: credential.serviceIdentifiers,
    origin: origin,
  );
}

String? _canonicalBrowserOrigin(Object? rawValue) {
  if (rawValue is! String ||
      rawValue.trim().isEmpty ||
      rawValue.length > 4096) {
    return null;
  }
  final uri = Uri.tryParse(rawValue.trim());
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

String? _safeString(Object? value, {required int maxLength}) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > maxLength) {
    return null;
  }
  return trimmed;
}

String _newBridgeToken() {
  final random = Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(32, (_) => random.nextInt(256)),
  );
  return base64Url.encode(bytes).replaceAll('=', '');
}

bool _constantTimeEquals(String left, String right) {
  final leftUnits = left.codeUnits;
  final rightUnits = right.codeUnits;
  var diff = leftUnits.length ^ rightUnits.length;
  final maxLength = max(leftUnits.length, rightUnits.length);
  for (var i = 0; i < maxLength; i += 1) {
    final leftCode = i < leftUnits.length ? leftUnits[i] : 0;
    final rightCode = i < rightUnits.length ? rightUnits[i] : 0;
    diff |= leftCode ^ rightCode;
  }
  return diff == 0;
}

String _publicErrorMessage(String code) {
  return switch (code) {
    'unauthorized' => 'Reveal bridge authentication failed.',
    'database_mismatch' => 'KeyVault database changed. Query again.',
    'credential_unavailable' => 'Requested credential is unavailable.',
    'strong_match_required' =>
      'Credential is not an exact match for this site.',
    'invalid_request' => 'Reveal bridge request is invalid.',
    'forbidden' => 'Reveal bridge rejected the request.',
    _ => 'Reveal bridge request failed.',
  };
}
