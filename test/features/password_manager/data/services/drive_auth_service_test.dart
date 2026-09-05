import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:password_manager/features/password_manager/data/datasources/google_token_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_oauth_pkce_service.dart';
import 'package:password_manager/features/password_manager/data/services/drive_auth_service.dart';
import 'package:password_manager/features/password_manager/data/services/google_oauth_config.dart';
import 'package:password_manager/features/password_manager/domain/errors/google_authorization_required_exception.dart';

/// spec-003 T4/C-2: desktop Drive-only OAuth cannot guarantee identity
/// without expanding scopes, so it must always return the exact fallback
/// summary rather than attempting Google Sign-In.
void main() {
  DriveAuthService buildService({required bool isDesktop}) {
    return DriveAuthService(
      config: const GoogleOAuthConfig(
        mobileClientId: null,
        androidServerClientId: null,
        desktopClientId: null,
        desktopClientSecret: null,
      ),
      googleTokenDataSource: _NoopGoogleTokenDataSource(),
      desktopOAuthPkceService: DesktopOAuthPkceService(
        httpClient: http.Client(),
      ),
      isDesktopOverride: isDesktop,
    );
  }

  group('getConnectedAccountSummary (C-2)', () {
    test('desktop always returns the exact fallback label with no email, '
        'without attempting Google Sign-In', () async {
      final service = buildService(isDesktop: true);

      final summary = await service.getConnectedAccountSummary();

      expect(summary, DriveAuthService.fallbackAccount);
      expect(summary.displayLabel, 'Google Drive account');
      expect(summary.email, isNull);
    });
  });

  group('desktop token refresh', () {
    for (final terminalError in const [
      'invalid_grant',
      'unauthorized_client',
    ]) {
      for (final status in const [400, 401]) {
        test(
          '$terminalError on $status clears credentials and requires reconnect',
          () async {
            final tokens = _StoredGoogleTokenDataSource();
            final service = _desktopService(
              tokens: tokens,
              client: MockClient(
                (_) async =>
                    http.Response('{"error":"$terminalError"}', status),
              ),
            );

            await expectLater(
              service.getValidAccessToken(),
              throwsA(isA<GoogleAuthorizationRequiredException>()),
            );

            expect(tokens.value, isNull);
            expect(tokens.clearCount, 1);
          },
        );
      }
    }

    for (final retryableStatus in const [429, 500]) {
      test(
        '$retryableStatus with terminal body preserves credentials',
        () async {
          final tokens = _StoredGoogleTokenDataSource();
          final original = tokens.value;
          final service = _desktopService(
            tokens: tokens,
            client: MockClient(
              (_) async =>
                  http.Response('{"error":"invalid_grant"}', retryableStatus),
            ),
          );

          await expectLater(service.getValidAccessToken(), throwsException);

          expect(tokens.value, original);
          expect(tokens.clearCount, 0);
        },
      );
    }

    test('malformed error response preserves credentials', () async {
      final tokens = _StoredGoogleTokenDataSource();
      final original = tokens.value;
      final service = _desktopService(
        tokens: tokens,
        client: MockClient((_) async => http.Response('not-json', 400)),
      );

      await expectLater(service.getValidAccessToken(), throwsException);

      expect(tokens.value, original);
      expect(tokens.clearCount, 0);
    });

    test(
      'terminal error_description with non-terminal error preserves credentials',
      () async {
        final tokens = _StoredGoogleTokenDataSource();
        final original = tokens.value;
        final service = _desktopService(
          tokens: tokens,
          client: MockClient(
            (_) async => http.Response(
              '{"error":"temporarily_unavailable",'
              '"error_description":"invalid_grant"}',
              400,
            ),
          ),
        );

        await expectLater(service.getValidAccessToken(), throwsException);

        expect(tokens.value, original);
        expect(tokens.clearCount, 0);
      },
    );

    test('cleanup failure preserves typed reconnect-required error', () async {
      final tokens = _StoredGoogleTokenDataSource(throwOnClear: true);
      final original = tokens.value;
      final service = _desktopService(
        tokens: tokens,
        client: MockClient(
          (_) async => http.Response('{"error":"invalid_grant"}', 400),
        ),
      );

      await expectLater(
        service.getValidAccessToken(),
        throwsA(isA<GoogleAuthorizationRequiredException>()),
      );

      expect(tokens.value, original);
      expect(tokens.clearCount, 1);
    });

    test('forceRefresh refreshes a non-expired desktop token', () async {
      var refreshCalls = 0;
      final tokens = _StoredGoogleTokenDataSource(
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final service = _desktopService(
        tokens: tokens,
        client: MockClient((request) async {
          if (request.url.path == '/token') {
            refreshCalls += 1;
            return http.Response(
              '{"access_token":"refreshed-access-token","expires_in":3600}',
              200,
            );
          }
          return http.Response(
            '{"scope":"https://www.googleapis.com/auth/drive"}',
            200,
          );
        }),
      );

      final result = await service.getValidAccessToken(forceRefresh: true);

      expect(result, 'refreshed-access-token');
      expect(refreshCalls, 1);
      expect(tokens.clearCount, 0);
    });

    test('other OAuth error preserves credentials', () async {
      final tokens = _StoredGoogleTokenDataSource();
      final original = tokens.value;
      final service = _desktopService(
        tokens: tokens,
        client: MockClient(
          (_) async => http.Response('{"error":"invalid_client"}', 401),
        ),
      );

      await expectLater(service.getValidAccessToken(), throwsException);

      expect(tokens.value, original);
      expect(tokens.clearCount, 0);
    });

    test('timeout preserves credentials', () async {
      final tokens = _StoredGoogleTokenDataSource();
      final original = tokens.value;
      final service = _desktopService(
        tokens: tokens,
        client: MockClient((_) => throw TimeoutException('synthetic timeout')),
      );

      await expectLater(
        service.getValidAccessToken(),
        throwsA(isA<TimeoutException>()),
      );

      expect(tokens.value, original);
      expect(tokens.clearCount, 0);
    });

    test('network failure preserves credentials', () async {
      final tokens = _StoredGoogleTokenDataSource();
      final original = tokens.value;
      final service = _desktopService(
        tokens: tokens,
        client: MockClient((_) => throw const SocketException('synthetic')),
      );

      await expectLater(
        service.getValidAccessToken(),
        throwsA(isA<SocketException>()),
      );

      expect(tokens.value, original);
      expect(tokens.clearCount, 0);
    });
  });

  group('connect concurrency', () {
    test('concurrent callers share one interactive sign-in', () async {
      final pkce = _ControlledPkceService();
      final service = _connectableDesktopService(pkce);

      final first = service.connect();
      final second = service.connect();

      expect(pkce.interactiveSignInCalls, 1);
      pkce.completeAllSuccessfully();
      await Future.wait([first, second]);
      expect(pkce.interactiveSignInCalls, 1);
    });

    test('failed sign-in clears guard so a later retry can succeed', () async {
      final pkce = _ControlledPkceService();
      final service = _connectableDesktopService(pkce);

      final first = service.connect();
      final second = service.connect();
      final firstExpectation = expectLater(first, throwsException);
      final secondExpectation = expectLater(second, throwsException);
      pkce.completeAllWithError(Exception('synthetic sign-in failure'));

      await firstExpectation;
      await secondExpectation;
      expect(pkce.interactiveSignInCalls, 1);

      final retry = service.connect();
      expect(pkce.interactiveSignInCalls, 2);
      pkce.completeAllSuccessfully();
      await retry;
    });
  });
}

DriveAuthService _connectableDesktopService(_ControlledPkceService pkce) {
  return DriveAuthService(
    config: const GoogleOAuthConfig(
      mobileClientId: null,
      androidServerClientId: null,
      desktopClientId: 'synthetic-client-id',
      desktopClientSecret: 'synthetic-client-secret',
    ),
    googleTokenDataSource: _NoopGoogleTokenDataSource(),
    desktopOAuthPkceService: pkce,
    isDesktopOverride: true,
  );
}

DriveAuthService _desktopService({
  required _StoredGoogleTokenDataSource tokens,
  required http.Client client,
}) {
  return DriveAuthService(
    config: const GoogleOAuthConfig(
      mobileClientId: null,
      androidServerClientId: null,
      desktopClientId: 'synthetic-client-id',
      desktopClientSecret: 'synthetic-client-secret',
    ),
    googleTokenDataSource: tokens,
    desktopOAuthPkceService: DesktopOAuthPkceService(httpClient: client),
    isDesktopOverride: true,
  );
}

class _NoopGoogleTokenDataSource implements GoogleTokenDataSource {
  @override
  Future<void> saveDesktopCredentialsJson(String json) async {}

  @override
  Future<String?> getDesktopCredentialsJson() async => null;

  @override
  Future<void> clearDesktopCredentialsJson() async {}
}

class _ControlledPkceService extends DesktopOAuthPkceService {
  _ControlledPkceService() : super(httpClient: http.Client());

  int interactiveSignInCalls = 0;
  final _signIns = <Completer<DesktopOAuthTokenSet>>[];

  @override
  Future<DesktopOAuthTokenSet> interactiveSignIn({
    required String clientId,
    required String clientSecret,
  }) {
    interactiveSignInCalls += 1;
    final signIn = Completer<DesktopOAuthTokenSet>();
    _signIns.add(signIn);
    return signIn.future;
  }

  @override
  Future<bool> tokenContainsScope({
    required String accessToken,
    required String requiredScope,
  }) async => true;

  void completeAllSuccessfully() {
    for (final signIn in _signIns.where((signIn) => !signIn.isCompleted)) {
      signIn.complete(
        DesktopOAuthTokenSet(
          accessToken: 'synthetic-access-token',
          refreshToken: 'synthetic-refresh-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
    }
  }

  void completeAllWithError(Object error) {
    for (final signIn in _signIns.where((signIn) => !signIn.isCompleted)) {
      signIn.completeError(error);
    }
  }
}

class _StoredGoogleTokenDataSource implements GoogleTokenDataSource {
  _StoredGoogleTokenDataSource({DateTime? expiresAt, this.throwOnClear = false})
    : value = DesktopOAuthTokenSet(
        accessToken: 'stored-access-token',
        refreshToken: 'stored-refresh-token',
        expiresAt: expiresAt ?? DateTime.utc(2000),
      ).toJson();

  final bool throwOnClear;
  String? value;
  int clearCount = 0;

  @override
  Future<void> saveDesktopCredentialsJson(String json) async => value = json;

  @override
  Future<String?> getDesktopCredentialsJson() async => value;

  @override
  Future<void> clearDesktopCredentialsJson() async {
    clearCount += 1;
    if (throwOnClear) {
      throw StateError('synthetic secure-storage failure');
    }
    value = null;
  }
}
