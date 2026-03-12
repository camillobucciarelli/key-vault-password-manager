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
       _googleSignIn = GoogleSignIn.instance;

  final GoogleOAuthConfig _config;
  final GoogleTokenDataSource _googleTokenDataSource;
  final DesktopOAuthPkceService _desktopOAuthPkceService;
  final GoogleSignIn _googleSignIn;
  bool _googleSignInInitialized = false;

  static const _requiredDriveScope = 'https://www.googleapis.com/auth/drive';

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) {
      return;
    }

    await _googleSignIn.initialize(
      clientId: !kIsWeb && Platform.isIOS ? _config.mobileClientId : null,
      serverClientId: !kIsWeb && Platform.isAndroid
          ? _config.androidServerClientId
          : null,
    );
    _googleSignInInitialized = true;
  }

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
      final hasRequiredScope = await _desktopOAuthPkceService
          .tokenContainsScope(
            accessToken: tokenSet.accessToken,
            requiredScope: _requiredDriveScope,
          );
      if (!hasRequiredScope) {
        await _googleTokenDataSource.clearDesktopCredentialsJson();
        throw Exception(
          'Google Drive authorization is outdated. Please reconnect and grant full Drive access.',
        );
      }
      await _googleTokenDataSource.saveDesktopCredentialsJson(
        tokenSet.toJson(),
      );
      return;
    }

    await _ensureGoogleSignInInitialized();

    final signedInUser = await _authenticateForDriveScopes();
    await _ensureDriveScopeAuthorization(signedInUser);
  }

  Future<void> disconnect() async {
    await _googleTokenDataSource.clearDesktopCredentialsJson();
    await _ensureGoogleSignInInitialized();

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

    await _ensureGoogleSignInInitialized();
    final lightweightAttempt = _googleSignIn.attemptLightweightAuthentication();
    final current = lightweightAttempt == null
        ? null
        : await lightweightAttempt;
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
      }

      final hasRequiredScope = await _desktopOAuthPkceService
          .tokenContainsScope(
            accessToken: tokenSet.accessToken,
            requiredScope: _requiredDriveScope,
          );
      if (!hasRequiredScope) {
        await _googleTokenDataSource.clearDesktopCredentialsJson();
        throw Exception(
          'Google Drive authorization needs to be renewed with full Drive access.',
        );
      }

      await _googleTokenDataSource.saveDesktopCredentialsJson(
        tokenSet.toJson(),
      );

      return tokenSet.accessToken;
    }

    await _ensureGoogleSignInInitialized();

    final lightweightAttempt = _googleSignIn.attemptLightweightAuthentication();
    var user = lightweightAttempt == null ? null : await lightweightAttempt;

    user ??= await _authenticateForDriveScopes();

    final authz = await _ensureDriveScopeAuthorization(user);
    final accessToken = authz.accessToken;
    if (accessToken.isEmpty) {
      throw Exception('Unable to obtain a valid Google access token.');
    }
    return accessToken;
  }

  Future<GoogleSignInAccount> _authenticateForDriveScopes() async {
    try {
      return await _googleSignIn.authenticate(
        scopeHint: const [_requiredDriveScope],
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        final lightweightAttempt = _googleSignIn
            .attemptLightweightAuthentication();
        final user = lightweightAttempt == null ? null : await lightweightAttempt;
        if (user != null) {
          return user;
        }
      }
      throw _mapGoogleSignInException(e);
    }
  }

  Future<GoogleSignInClientAuthorization> _ensureDriveScopeAuthorization(
    GoogleSignInAccount user,
  ) async {
    try {
      final existing = await user.authorizationClient.authorizationForScopes(
        const [_requiredDriveScope],
      );
      if (existing != null) {
        return existing;
      }
      final granted = await user.authorizationClient.authorizeScopes(
        const [_requiredDriveScope],
      );
      return granted;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        final rehydratedUser = await _tryRecoverSignedInUser();
        if (rehydratedUser != null) {
          final recoveredAuthz = await rehydratedUser.authorizationClient
              .authorizationForScopes(const [_requiredDriveScope]);
          if (recoveredAuthz != null) {
            return recoveredAuthz;
          }
          throw Exception(
            'Google account selected, but Drive permission was not granted.',
          );
        }
      }
      throw _mapGoogleSignInException(e);
    }
  }

  Future<GoogleSignInAccount?> _tryRecoverSignedInUser() async {
    final lightweightAttempt = _googleSignIn.attemptLightweightAuthentication();
    if (lightweightAttempt != null) {
      return lightweightAttempt;
    }
    return null;
  }

  Exception _mapGoogleSignInException(GoogleSignInException exception) {
    if (exception.code == GoogleSignInExceptionCode.canceled) {
      return Exception('Google sign-in cancelled.');
    }
    if (exception.code == GoogleSignInExceptionCode.clientConfigurationError) {
      if (!kIsWeb && Platform.isAndroid) {
        return Exception(
          'Android Google Sign-In is not configured. Set GOOGLE_ANDROID_SERVER_CLIENT_ID (or GOOGLE_WEB_CLIENT_ID) in --dart-define-from-file.',
        );
      }
      if (!kIsWeb && Platform.isIOS) {
        return Exception(
          'iOS Google Sign-In is not configured. Set GOOGLE_MOBILE_CLIENT_ID in --dart-define-from-file.',
        );
      }
    }
    return Exception('Google sign-in failed: ${exception.toString()}');
  }
}
