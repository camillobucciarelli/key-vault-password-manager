# Google Drive Sync Setup

This app supports KDBX sync with Google Drive on Android, iOS, macOS, Windows, and Linux.

## OAuth Configuration

Create OAuth clients in Google Cloud Console and pass credentials via `--dart-define-from-file`:

- `GOOGLE_MOBILE_CLIENT_ID` for iOS sign-in (`*.apps.googleusercontent.com` iOS client ID).
- `GOOGLE_ANDROID_SERVER_CLIENT_ID` for Android Google Sign-In token exchange (use your Web OAuth client ID).
  - `GOOGLE_WEB_CLIENT_ID` is also accepted as a fallback alias.
- `GOOGLE_DESKTOP_CLIENT_ID` for macOS/Windows/Linux desktop OAuth.
- `GOOGLE_DESKTOP_CLIENT_SECRET` for macOS/Windows/Linux desktop OAuth token exchange.

The user still signs in interactively at runtime and explicitly authorizes Drive access.
The app registration values above identify your app to Google OAuth.

Android still requires proper package + SHA configuration in Google Cloud OAuth and,
with `google_sign_in` v7 flow, a server/web client ID at runtime via
`GOOGLE_ANDROID_SERVER_CLIENT_ID` (or `GOOGLE_WEB_CLIENT_ID` fallback).

Create your local env file from the example:

```bash
cp .env.dart.define.example.json .env.dart.define.json
```

Then fill `.env.dart.define.json` with your real OAuth values and run:

```bash
flutter run --dart-define-from-file=.env.dart.define.json
```

Build example:

```bash
flutter build macos --dart-define-from-file=.env.dart.define.json
```

## Runtime Flow

1. Open a database.
2. From the Vault top-right cloud menu:
   - Connect Google Drive.
   - Link this database.
   - Sync now.
   - Enable/disable auto-sync.
3. When linking, choose one:
   - Create a new `.kdbx` file in a selected Drive folder.
   - Use an existing `.kdbx` file from Drive.
4. On conflict, choose one:
    - Keep local
    - Use remote
    - Cancel

Google OAuth scope used for Drive operations: `https://www.googleapis.com/auth/drive`.
