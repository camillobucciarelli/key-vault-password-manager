import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

import 'package:local_auth/local_auth.dart';

import '../../domain/models/vault_entry.dart';
import '../../domain/services/vault_autofill_matcher.dart';
import '../../domain/usecases/get_selected_database_path_usecase.dart';
import '../../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../datasources/secure_data_source.dart';
import 'vault_kdbx_service.dart';

class DesktopAutofillBridgeService {
  DesktopAutofillBridgeService({
    required this.getSelectedDatabasePathUseCase,
    required this.getSelectedKeyFilePathUseCase,
    required this.secureDataSource,
    required this.vaultKdbxService,
    required this.matcher,
  });

  final GetSelectedDatabasePathUseCase getSelectedDatabasePathUseCase;
  final GetSelectedKeyFilePathUseCase getSelectedKeyFilePathUseCase;
  final SecureDataSource secureDataSource;
  final VaultKdbxService vaultKdbxService;
  final VaultAutofillMatcher matcher;

  HttpServer? _server;
  String? _token;
  DateTime? _tokenExpiresAt;

  static const Duration _tokenTtl = Duration(minutes: 20);

  Future<void> start() async {
    if (!_isDesktop || _server != null) {
      return;
    }

    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final token = _generateToken();
      final expiresAt = DateTime.now().add(_tokenTtl);

      _server = server;
      _token = token;
      _tokenExpiresAt = expiresAt;

      await _writeBridgeConfig(server.port, token, expiresAt);
      server.listen(
        _handleRequest,
        onError: (Object error, StackTrace st) {
          logError('Desktop autofill bridge error.', error, st);
        },
      );
      logInfo('Desktop autofill bridge started on 127.0.0.1:${server.port}.');
    } catch (e, st) {
      logError('Unable to start desktop autofill bridge.', e, st);
    }
  }

  bool get _isDesktop {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }

      if (request.method != 'POST' || request.uri.path != '/v1/find') {
        _json(request.response, HttpStatus.notFound, {
          'ok': false,
          'error': 'Not found',
        });
        return;
      }

      final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';

      final tokenExpired =
          _tokenExpiresAt == null || DateTime.now().isAfter(_tokenExpiresAt!);
      if (tokenExpired) {
        await _rotateToken();
      }

      final expected = 'Bearer ${_token ?? ''}';
      if (auth != expected) {
        _json(request.response, HttpStatus.unauthorized, {
          'ok': false,
          'error': 'Unauthorized',
        });
        return;
      }

      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        _json(request.response, HttpStatus.badRequest, {
          'ok': false,
          'error': 'Invalid body',
        });
        return;
      }

      final payload = decoded.cast<String, Object?>();
      final url = payload['url'] as String? ?? '';
      final requestedLimit = payload['limit'];
      final limit = requestedLimit is num
          ? requestedLimit.toInt().clamp(1, 10)
          : 5;

      final databasePath = await getSelectedDatabasePathUseCase();
      final password = await secureDataSource.getMasterPassword() ?? '';
      final keyFilePath = await getSelectedKeyFilePathUseCase();

      if (databasePath == null || databasePath.trim().isEmpty) {
        _json(request.response, HttpStatus.ok, {
          'ok': true,
          'credentials': const [],
        });
        return;
      }

      if (password.isEmpty && (keyFilePath == null || keyFilePath.isEmpty)) {
        _json(request.response, HttpStatus.ok, {
          'ok': true,
          'credentials': const [],
        });
        return;
      }

      final entries = await vaultKdbxService.loadAllEntries(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final host = _extractHost(url);
      final roughMatches = matcher.findBestMatches(
        entries: entries,
        webDomains: host.isEmpty ? const {} : {host},
        limit: limit,
      );
      final matches = _filterMatchesForHost(
        roughMatches,
        host,
      ).take(limit).toList(growable: false);

      if (matches.isNotEmpty) {
        final auth = LocalAuthentication();
        final canCheckBiometrics = await auth.canCheckBiometrics;
        final isDeviceSupported = await auth.isDeviceSupported();

        if (canCheckBiometrics || isDeviceSupported) {
          final isAuthorized = await auth.authenticate(
            localizedReason: 'Autenticati per inserire le credenziali in $host',
            biometricOnly: false,
            sensitiveTransaction: true,
          );

          if (!isAuthorized) {
            _json(request.response, HttpStatus.forbidden, {
              'ok': false,
              'error': 'User cancelled biometric authentication',
            });
            return;
          }
        }
      }

      _json(request.response, HttpStatus.ok, {
        'ok': true,
        'credentials': matches
            .map(
              (entry) => {
                'id': entry.id,
                'title': entry.title,
                'username': entry.username,
                'password': entry.password,
                'url': entry.url,
              },
            )
            .toList(growable: false),
      });
    } catch (e, st) {
      logError('Desktop autofill bridge request failed.', e, st);
      _json(request.response, HttpStatus.internalServerError, {
        'ok': false,
        'error': 'Internal error',
      });
    }
  }

  void _json(HttpResponse response, int statusCode, Map<String, Object?> body) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }

  String _extractHost(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.host.isEmpty) {
      return '';
    }

    final host = uri.host.toLowerCase();
    if (host.startsWith('www.')) {
      return host.substring(4);
    }
    return host;
  }

  Iterable<VaultEntry> _filterMatchesForHost(
    List<VaultEntry> entries,
    String requestedHost,
  ) {
    if (requestedHost.isEmpty) {
      return const [];
    }

    return entries.where((entry) {
      final entryHost = _extractHost(entry.url);
      if (entryHost.isEmpty) {
        return false;
      }

      return _hostsMatch(requestedHost, entryHost);
    });
  }

  bool _hostsMatch(String requestedHost, String credentialHost) {
    if (requestedHost == credentialHost) {
      return true;
    }

    if (requestedHost.endsWith('.$credentialHost')) {
      return true;
    }

    if (credentialHost.endsWith('.$requestedHost')) {
      return true;
    }

    return false;
  }

  String _generateToken() {
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> _rotateToken() async {
    if (_server == null) {
      return;
    }

    final token = _generateToken();
    final expiresAt = DateTime.now().add(_tokenTtl);
    _token = token;
    _tokenExpiresAt = expiresAt;
    await _writeBridgeConfig(_server!.port, token, expiresAt);
  }

  Future<void> _writeBridgeConfig(
    int port,
    String token,
    DateTime expiresAt,
  ) async {
    final dir = Directory(_bridgeDirectoryPath());
    await dir.create(recursive: true);

    final file = File(p.join(dir.path, 'bridge.json'));
    final payload = {
      'host': '127.0.0.1',
      'port': port,
      'token': token,
      'expiresAtEpochMs': expiresAt.millisecondsSinceEpoch,
      'version': 1,
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  String _bridgeDirectoryPath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'KeyVaultAutofill');
      }
    }

    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return p.join(home, '.keyvault_autofill');
  }
}
