import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:password_manager/features/password_manager/data/datasources/google_token_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_oauth_pkce_service.dart';
import 'package:password_manager/features/password_manager/data/services/drive_auth_service.dart';
import 'package:password_manager/features/password_manager/data/services/google_oauth_config.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_account_summary.dart';

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
    test(
      'desktop always returns the exact fallback label with no email, '
      'without attempting Google Sign-In',
      () async {
        final service = buildService(isDesktop: true);

        final summary = await service.getConnectedAccountSummary();

        expect(summary, DriveAccountSummary.fallback);
        expect(summary.displayLabel, 'Google Drive account');
        expect(summary.email, isNull);
      },
    );
  });
}

class _NoopGoogleTokenDataSource implements GoogleTokenDataSource {
  @override
  Future<void> saveDesktopCredentialsJson(String json) async {}

  @override
  Future<String?> getDesktopCredentialsJson() async => null;

  @override
  Future<void> clearDesktopCredentialsJson() async {}
}
