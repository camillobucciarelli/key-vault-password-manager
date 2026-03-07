class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    required this.mobileClientId,
    required this.desktopClientId,
    required this.desktopClientSecret,
  });

  final String? mobileClientId;
  final String? desktopClientId;
  final String? desktopClientSecret;

  static GoogleOAuthConfig fromEnvironment() {
    const mobileClientId = String.fromEnvironment('GOOGLE_MOBILE_CLIENT_ID');
    const desktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
    const desktopClientSecret = String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_SECRET',
    );

    return GoogleOAuthConfig(
      mobileClientId: mobileClientId.isEmpty ? null : mobileClientId,
      desktopClientId: desktopClientId.isEmpty ? null : desktopClientId,
      desktopClientSecret: desktopClientSecret.isEmpty
          ? null
          : desktopClientSecret,
    );
  }
}
