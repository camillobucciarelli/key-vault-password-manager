import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../datasources/google_token_data_source.dart';
import 'desktop_oauth_pkce_service.dart';
import 'google_oauth_config.dart';

class DriveAuthService {
  DriveAuthService({
    required GoogleOAuthConfig config,
    required GoogleTokenDataSource googleTokenDataSource,
    required DesktopOAuthPkceService desktopOAuthPkceService,
  }) : _config = config,
       _googleTokenDataSource = googleTokenDataSource,
       _desktopOAuthPkceService = desktopOAuthPkceService,
       _googleSignIn = GoogleSignIn(
         scopes: const ['https://www.googleapis.com/auth/drive.file'],
         serverClientId: config.mobileClientId,
       );

  final GoogleOAuthConfig _config;
  final GoogleTokenDataSource _googleTokenDataSource;
  final DesktopOAuthPkceService _desktopOAuthPkceService;
  final GoogleSignIn _googleSignIn;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> connect() async {
    if (_isDesktop) {
      final clientId = _config.desktopClientId;
      final clientSecret = _config.desktopClientSecret;
      if (clientId == null || clientSecret == null) {
        throw Exception(
          'Desktop OAuth is not configured. Set GOOGLE_DESKTOP_CLIENT_ID and GOOGLE_DESKTOP_CLIENT_SECRET.',
        );
      }

      final tokenSet = await _desktopOAuthPkceService.interactiveSignIn(
        clientId: clientId,
        clientSecret: clientSecret,
      );
      await _googleTokenDataSource.saveDesktopCredentialsJson(
        tokenSet.toJson(),
      );
      return;
    }

    final user = await _googleSignIn.signIn();
    if (user == null) {
      throw Exception('Google sign-in cancelled.');
    }
  }

  Future<void> disconnect() async {
    await _googleTokenDataSource.clearDesktopCredentialsJson();

    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
  }

  Future<bool> isConnected() async {
    if (_isDesktop) {
      return (await _googleTokenDataSource.getDesktopCredentialsJson()) != null;
    }

    final current = await _googleSignIn.signInSilently();
    return current != null;
  }

  Future<String> getValidAccessToken() async {
    if (_isDesktop) {
      final clientId = _config.desktopClientId;
      final clientSecret = _config.desktopClientSecret;
      if (clientId == null || clientSecret == null) {
        throw Exception(
          'Desktop OAuth is not configured. Set GOOGLE_DESKTOP_CLIENT_ID and GOOGLE_DESKTOP_CLIENT_SECRET.',
        );
      }

      final raw = await _googleTokenDataSource.getDesktopCredentialsJson();
      if (raw == null || raw.trim().isEmpty) {
        throw Exception('Google account not connected.');
      }

      var tokenSet = DesktopOAuthTokenSet.fromJson(raw);
      if (DateTime.now().isAfter(tokenSet.expiresAt)) {
        tokenSet = await _desktopOAuthPkceService.refreshToken(
          clientId: clientId,
          clientSecret: clientSecret,
          refreshToken: tokenSet.refreshToken,
        );
        await _googleTokenDataSource.saveDesktopCredentialsJson(
          tokenSet.toJson(),
        );
      }

      return tokenSet.accessToken;
    }

    final user =
        await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
    if (user == null) {
      throw Exception('Google account not connected.');
    }

    final auth = await user.authentication;
    final accessToken = auth.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Unable to obtain a valid Google access token.');
    }
    return accessToken;
  }
}
