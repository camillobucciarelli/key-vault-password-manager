import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../domain/models/vault_entry.dart';
import '../../domain/repositories/password_generator_settings_repository.dart';
import '../../domain/services/password_generator_service.dart';
import 'browser_exact_origin.dart';
import 'desktop_browser_autofill_cache.dart';
import 'desktop_browser_pending_generation_service.dart';

const _maxRevealRequestBytes = 4096;

class DesktopBrowserAutofillRevealBridgeService {
  DesktopBrowserAutofillRevealBridgeService({
    required this.store,
    required this.mapper,
    this.settingsRepository,
    this.passwordGenerator,
    this.pendingGeneration,
  });

  /// 009 / B006 — anti-grinding bound: fixed one-minute window per bridge
  /// session. Generation is a user-gesture path (one click, one password),
  /// so a tight ceiling costs nothing legitimate.
  // ponytail: fixed window; sliding window if a real client ever hits this.
  static const maxGenerateRequestsPerMinute = 10;

  final DesktopBrowserAutofillCacheStore store;
  final DesktopBrowserAutofillMetadataMapper mapper;

  /// 009 / B006 — generation dependencies. All three must be present for the
  /// `/generate-pending` endpoint to exist; otherwise the bridge behaves
  /// exactly like a pre-B1 app: the route answers `not_found` and the
  /// descriptor advertises no `generatePendingEntryV1` capability. Settings
  /// are read from [settingsRepository] only — the request cannot carry them.
  final PasswordGeneratorSettingsRepository? settingsRepository;
  final PasswordGeneratorService? passwordGenerator;
  final DesktopBrowserPendingGenerationService? pendingGeneration;

  bool get _generationAvailable =>
      settingsRepository != null &&
      passwordGenerator != null &&
      pendingGeneration != null;

  HttpServer? _server;
  String? _databaseId;
  String? _cacheGeneration;
  String? _bridgeGeneration;
  String? _token;
  Map<String, _DesktopBrowserRevealCredential> _credentials = const {};

  /// SR-4 — one monotonic session epoch per running bridge.
  ///
  /// The overlay reveal path reads it once before the credential lookup and
  /// compares it again immediately before writing the response, so a vault
  /// switch that lands mid-request cannot have its secret answered under the
  /// previous session's binding.
  int _sessionEpoch = 0;

  /// Test seam for the SR-4 "check again before response" requirement.
  ///
  /// Awaited between the credential lookup and the response write, which is the
  /// exact window the second check exists to close. Production never sets it.
  @visibleForTesting
  Future<void> Function()? debugBeforeOverlayRevealResponse;

  /// Same seam for `/generate-pending`: awaited between the pending-record
  /// creation and the response write. Production never sets it.
  @visibleForTesting
  Future<void> Function()? debugBeforeGeneratePendingResponse;

  int _generateWindowStartMs = 0;
  int _generateWindowCount = 0;

  Future<void> start({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    if (store.directory == null) {
      return;
    }

    await stop();

    // Migration (fix/macos-autofill-store-location): the store moved out of
    // the shared app group container; delete the old macOS store so its
    // bridge.json bearer never stays orphaned there. Best-effort, no-op off
    // macOS or when already gone.
    await store.cleanupLegacyStore();

    final databaseId = DesktopBrowserAutofillMetadataMapper.databaseIdForPath(
      databasePath,
    );
    // The cache generation is read from the cache the coordinator has just
    // published rather than minted here, so the descriptor and the metadata can
    // never disagree. A missing/stale cache leaves it empty, which makes every
    // overlay request fail closed while the popup path keeps working.
    final publishedCache = await store.readMetadataCache();
    final cacheGeneration =
        publishedCache != null && publishedCache.databaseId == databaseId
        ? publishedCache.cacheGeneration
        : '';
    final bridgeGeneration = newDesktopBrowserAutofillGeneration();
    final credentials = _credentialsFromEntries(entries);
    final token = _newBridgeToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    _server = server;
    _databaseId = databaseId;
    _cacheGeneration = cacheGeneration;
    _bridgeGeneration = bridgeGeneration;
    _token = token;
    _credentials = credentials;
    _sessionEpoch += 1;
    _generateWindowStartMs = 0;
    _generateWindowCount = 0;

    try {
      await store.writeBridgeDescriptor(
        DesktopBrowserAutofillBridgeDescriptor(
          version: desktopBrowserAutofillBridgeDescriptorVersion,
          port: server.port,
          token: token,
          databaseId: databaseId,
          cacheGeneration: cacheGeneration,
          bridgeGeneration: bridgeGeneration,
          createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
          // B007: the capability is advertised only when the endpoint truly
          // exists on this running bridge — the two can never disagree.
          appCapabilities: _generationAvailable
              ? const [desktopBrowserGeneratePendingCapability]
              : const [],
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
    _cacheGeneration = null;
    _bridgeGeneration = null;
    _token = null;
    _credentials = const {};
    _sessionEpoch += 1;
    _generateWindowStartMs = 0;
    _generateWindowCount = 0;

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
          (request.uri.path != '/reveal' &&
              request.uri.path != '/overlay-reveal' &&
              request.uri.path != '/generate-pending' &&
              request.uri.path != '/status')) {
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

      if (request.uri.path == '/overlay-reveal') {
        await _handleOverlayReveal(request, payload);
        return;
      }

      if (request.uri.path == '/generate-pending') {
        await _handleGeneratePending(request, payload);
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

  /// 009 / A012 — the origin-bound overlay reveal.
  ///
  /// A separate endpoint from `/reveal` on purpose, and the separation is a
  /// security property, not tidiness. The native host and this app are
  /// installed and updated independently, so a new host can meet an old app.
  /// Had the strict policy been a new *field* on `/reveal`, an old app would
  /// have ignored the field and answered under the lenient popup rule — a
  /// fail-open downgrade. An old app has no `/overlay-reveal`, so it answers
  /// `not_found` and the overlay path fails closed.
  ///
  /// `/reveal` keeps the popup policy from the reveal-authorization fix
  /// unchanged: domain identifiers, the `http` -> `https` upgrade and the
  /// non-WebPKI allowance all still apply *there*. They apply nowhere here.
  Future<void> _handleOverlayReveal(
    HttpRequest request,
    Map<String, Object?> payload,
  ) async {
    // Read the whole session under one epoch, before anything is looked up.
    final epochAtEntry = _sessionEpoch;
    final databaseId = _safeString(payload['databaseId'], maxLength: 128);
    final cacheGeneration = _safeString(
      payload['cacheGeneration'],
      maxLength: 128,
    );
    final bridgeGeneration = _safeString(
      payload['bridgeGeneration'],
      maxLength: 128,
    );
    final entryId = _safeString(payload['entryId'], maxLength: 256);
    final origin = browserExactOriginOrNull(payload['origin']);
    final matchPolicy = _safeString(payload['matchPolicy'], maxLength: 32);

    if (entryId == null ||
        origin == null ||
        matchPolicy != overlayMatchPolicy) {
      await _writeError(request, HttpStatus.badRequest, 'invalid_request');
      return;
    }
    if (!_matchesCurrentBinding(
      epoch: epochAtEntry,
      databaseId: databaseId,
      cacheGeneration: cacheGeneration,
      bridgeGeneration: bridgeGeneration,
    )) {
      await _writeError(request, HttpStatus.conflict, 'stale_session');
      return;
    }

    final credential = _credentials[entryId];
    // An unknown entry and an unauthorized origin answer identically: the
    // refusal must not disclose which rule rejected it, nor whether the entry
    // exists in this vault at all.
    if (credential == null ||
        !isExactOriginAuthorized(
          serviceIdentifiers: credential.serviceIdentifiers,
          origin: origin,
        )) {
      await _writeError(request, HttpStatus.forbidden, 'forbidden');
      return;
    }

    final beforeResponse = debugBeforeOverlayRevealResponse;
    if (beforeResponse != null) {
      await beforeResponse();
    }

    // SR-4: check again immediately before the secret is written, this time
    // against the durable descriptor as well as the in-memory session. A vault
    // switch or a coordinator teardown that landed while this request was in
    // flight invalidates it here, after every earlier check had passed.
    final durable = await store.readBridgeDescriptor();
    if (!_matchesCurrentBinding(
          epoch: epochAtEntry,
          databaseId: databaseId,
          cacheGeneration: cacheGeneration,
          bridgeGeneration: bridgeGeneration,
        ) ||
        durable == null ||
        durable.databaseId != databaseId ||
        durable.cacheGeneration != cacheGeneration ||
        durable.bridgeGeneration != bridgeGeneration) {
      await _writeError(request, HttpStatus.conflict, 'stale_session');
      return;
    }

    await _writeJson(request, HttpStatus.ok, {
      'ok': true,
      'data': {
        'entryId': credential.id,
        'matchPolicy': overlayMatchPolicy,
        'origin': origin,
        'databaseId': databaseId,
        'cacheGeneration': cacheGeneration,
        'bridgeGeneration': bridgeGeneration,
        'username': credential.username,
        'password': credential.password,
      },
    });
  }

  /// 009 / B006 — one-shot app-owned password generation.
  ///
  /// The secret exists in exactly three places: this response, the in-memory
  /// pending record, and the native host's one-shot response. It never touches
  /// the metadata cache, the bridge descriptor, `pending_associations.json`,
  /// or a log. Settings come exclusively from the app repository's last
  /// committed snapshot: a request that even *mentions* settings is
  /// `invalid_request` — rejected, not ignored — via the strict key allowlist.
  Future<void> _handleGeneratePending(
    HttpRequest request,
    Map<String, Object?> payload,
  ) async {
    final settingsRepository = this.settingsRepository;
    final passwordGenerator = this.passwordGenerator;
    final pendingGeneration = this.pendingGeneration;
    if (settingsRepository == null ||
        passwordGenerator == null ||
        pendingGeneration == null) {
      // Same shape a pre-B1 app produces: the endpoint does not exist.
      await _writeError(request, HttpStatus.notFound, 'not_found');
      return;
    }

    // Read the whole session under one epoch, before anything else.
    final epochAtEntry = _sessionEpoch;

    // Strict allowlist: any unknown key — a smuggled `settings` object, a
    // `length` override, anything — invalidates the whole request.
    const allowedKeys = {
      'version',
      'origin',
      'databaseId',
      'cacheGeneration',
      'bridgeGeneration',
    };
    if (payload.keys.any((key) => !allowedKeys.contains(key))) {
      await _writeError(request, HttpStatus.badRequest, 'invalid_request');
      return;
    }

    final origin = browserExactOriginOrNull(payload['origin']);
    final databaseId = _safeString(payload['databaseId'], maxLength: 128);
    final cacheGeneration = _safeString(
      payload['cacheGeneration'],
      maxLength: 128,
    );
    final bridgeGeneration = _safeString(
      payload['bridgeGeneration'],
      maxLength: 128,
    );
    if (origin == null) {
      await _writeError(request, HttpStatus.badRequest, 'invalid_request');
      return;
    }
    if (!_matchesCurrentBinding(
      epoch: epochAtEntry,
      databaseId: databaseId,
      cacheGeneration: cacheGeneration,
      bridgeGeneration: bridgeGeneration,
    )) {
      // The bridge only runs while the vault is unlocked, so a locked or
      // switched database can never satisfy the current binding.
      await _writeError(request, HttpStatus.conflict, 'stale_session');
      return;
    }

    // B006 rate bound — checked only after the request proved authentic and
    // current, so garbage cannot burn the window of a legitimate caller.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _generateWindowStartMs >= 60000) {
      _generateWindowStartMs = nowMs;
      _generateWindowCount = 0;
    }
    if (_generateWindowCount >= maxGenerateRequestsPerMinute) {
      await _writeError(request, HttpStatus.tooManyRequests, 'rate_limited');
      return;
    }
    _generateWindowCount += 1;

    // Latest *committed* app settings — never anything from the caller.
    final settings = await settingsRepository.read();
    final password = passwordGenerator.generate(settings.toOptions());
    final pending = pendingGeneration.create(
      databaseId: databaseId!,
      cacheGeneration: cacheGeneration!,
      bridgeGeneration: bridgeGeneration!,
      settingsRevision: settings.revision,
      origin: origin,
      password: password,
    );

    final beforeResponse = debugBeforeGeneratePendingResponse;
    if (beforeResponse != null) {
      await beforeResponse();
    }

    // SR-4: re-check against the in-memory session and the durable descriptor
    // immediately before the secret is written. A lock/switch that landed
    // mid-request already cleared the pending set via the coordinator; the
    // explicit reject below covers the durable-only divergence.
    final durable = await store.readBridgeDescriptor();
    if (!_matchesCurrentBinding(
          epoch: epochAtEntry,
          databaseId: databaseId,
          cacheGeneration: cacheGeneration,
          bridgeGeneration: bridgeGeneration,
        ) ||
        durable == null ||
        durable.databaseId != databaseId ||
        durable.cacheGeneration != cacheGeneration ||
        durable.bridgeGeneration != bridgeGeneration) {
      pendingGeneration.reject(pending.id);
      await _writeError(request, HttpStatus.conflict, 'stale_session');
      return;
    }

    await _writeJson(request, HttpStatus.ok, {
      'ok': true,
      'data': {
        'pendingGenerationId': pending.id,
        'expiresAtEpochMs': pending.expiresAtEpochMs,
        'databaseId': databaseId,
        'cacheGeneration': cacheGeneration,
        'bridgeGeneration': bridgeGeneration,
        'settingsRevision': settings.revision,
        'password': password,
      },
    });
  }

  bool _matchesCurrentBinding({
    required int epoch,
    required String? databaseId,
    required String? cacheGeneration,
    required String? bridgeGeneration,
  }) {
    return epoch == _sessionEpoch &&
        _server != null &&
        databaseId != null &&
        cacheGeneration != null &&
        bridgeGeneration != null &&
        databaseId == _databaseId &&
        cacheGeneration == _cacheGeneration &&
        bridgeGeneration == _bridgeGeneration;
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
  // Keep the host as the browser served it: the reveal policy re-normalizes it
  // for matching, but it also has to ask whether *this* name can obtain a
  // WebPKI certificate, and collapsing `m.`/`www.`/`mobile.` here would hand it
  // a single-label name (`m.me` -> `me`) that would pass as non-public.
  final host = DesktopBrowserAutofillMetadataMapper.normalizedHost(
    uri.host,
    stripPrefixes: false,
  );
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
    // Overlay refusals are deliberately uniform: neither message says whether
    // the entry exists, nor which part of the origin failed to match.
    'stale_session' => 'Reveal bridge session is no longer current.',
    'forbidden' => 'Reveal bridge rejected the request.',
    'rate_limited' => 'Too many generation requests. Try again shortly.',
    _ => 'Reveal bridge request failed.',
  };
}
