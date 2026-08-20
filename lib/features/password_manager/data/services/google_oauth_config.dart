/// OAuth client ids, one env key per Google Cloud Console client type:
/// - `GOOGLE_IOS_CLIENT_ID`        -> GCP client type "iOS"
/// - `GOOGLE_WEB_CLIENT_ID`        -> GCP client type "Web application"
///   (used by Android Google Sign-In as serverClientId)
/// - `GOOGLE_DESKTOP_CLIENT_ID`    -> GCP client type "Desktop app"
/// - `GOOGLE_DESKTOP_CLIENT_SECRET`-> secret of the "Desktop app" client
class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    required this.mobileClientId,
    required this.androidServerClientId,
    required this.desktopClientId,
    required this.desktopClientSecret,
  });

  final String? mobileClientId;
  final String? androidServerClientId;
  final String? desktopClientId;
  final String? desktopClientSecret;

  static GoogleOAuthConfig fromEnvironment() {
    const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    const desktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
    const desktopClientSecret = String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_SECRET',
    );

    return GoogleOAuthConfig(
      mobileClientId: iosClientId.isEmpty ? null : iosClientId,
      androidServerClientId: webClientId.isEmpty ? null : webClientId,
      desktopClientId: desktopClientId.isEmpty ? null : desktopClientId,
      desktopClientSecret: desktopClientSecret.isEmpty
          ? null
          : desktopClientSecret,
    );
  }
}
