import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher_string.dart';

class DesktopOAuthTokenSet {
  const DesktopOAuthTokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, dynamic> toMap() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  factory DesktopOAuthTokenSet.fromMap(Map<String, dynamic> map) {
    return DesktopOAuthTokenSet(
      accessToken: map['accessToken'] as String,
      refreshToken: map['refreshToken'] as String,
      expiresAt: DateTime.parse(map['expiresAt'] as String).toLocal(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DesktopOAuthTokenSet.fromJson(String json) {
    return DesktopOAuthTokenSet.fromMap(
      jsonDecode(json) as Map<String, dynamic>,
    );
  }
}

class DesktopOAuthPkceService {
  DesktopOAuthPkceService({required http.Client httpClient})
    : _httpClient = httpClient;

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _scope = 'https://www.googleapis.com/auth/drive.file';
  static const _loopbackHost = '127.0.0.1';

  final http.Client _httpClient;

  Future<DesktopOAuthTokenSet> interactiveSignIn({
    required String clientId,
    required String clientSecret,
  }) async {
    final server = await HttpServer.bind(_loopbackHost, 0);
    try {
      final redirectUri = 'http://$_loopbackHost:${server.port}/oauth2callback';
      final state = _randomUrlSafe(32);
      final codeVerifier = _randomUrlSafe(64);
      final codeChallenge = base64Url
          .encode(sha256.convert(utf8.encode(codeVerifier)).bytes)
          .replaceAll('=', '');

      final authUri = Uri.parse(_authEndpoint).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': _scope,
          'state': state,
          'access_type': 'offline',
          'prompt': 'consent',
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      );

      final launched = await launchUrlString(
        authUri.toString(),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Unable to open system browser for Google sign-in.');
      }

      final callback = await server.first.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw Exception('Google authentication timeout.'),
      );
      final code = callback.uri.queryParameters['code'];
      final returnedState = callback.uri.queryParameters['state'];
      final error = callback.uri.queryParameters['error'];

      if (error != null) {
        await _respond(callback, 'Authentication denied: $error');
        throw Exception('Google authentication denied: $error');
      }
      if (code == null || returnedState != state) {
        await _respond(callback, 'Authentication failed.');
        throw Exception('Invalid OAuth callback state or missing code.');
      }

      await _respond(
        callback,
        'Authentication complete. You can close this tab.',
      );

      return await _exchangeCodeForToken(
        clientId: clientId,
        clientSecret: clientSecret,
        code: code,
        redirectUri: redirectUri,
        codeVerifier: codeVerifier,
      );
    } finally {
      await server.close(force: true);
    }
  }

  Future<DesktopOAuthTokenSet> refreshToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    final response = await _httpClient.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Google token refresh failed (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = payload['access_token'] as String?;
    final expiresIn = payload['expires_in'] as int?;
    if (accessToken == null || expiresIn == null) {
      throw Exception('Google token refresh response is invalid.');
    }

    return DesktopOAuthTokenSet(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 30)),
    );
  }

  Future<DesktopOAuthTokenSet> _exchangeCodeForToken({
    required String clientId,
    required String clientSecret,
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) async {
    final response = await _httpClient.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Google token exchange failed (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = payload['access_token'] as String?;
    final refreshToken = payload['refresh_token'] as String?;
    final expiresIn = payload['expires_in'] as int?;

    if (accessToken == null || refreshToken == null || expiresIn == null) {
      throw Exception('Google token exchange response is invalid.');
    }

    return DesktopOAuthTokenSet(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 30)),
    );
  }

  Future<void> _respond(HttpRequest request, String message) async {
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('<html><body><p>$message</p></body></html>');
    await request.response.close();
  }

  String _randomUrlSafe(int bytes) {
    final random = Random.secure();
    final values = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }
}
