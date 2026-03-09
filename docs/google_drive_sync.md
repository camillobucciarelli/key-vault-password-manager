# Google Drive Sync Setup

This app supports KDBX sync with Google Drive on Android, iOS, macOS, Windows, and Linux.

## OAuth Configuration

Create OAuth clients in Google Cloud Console and pass credentials via `--dart-define-from-file`:

- `GOOGLE_MOBILE_CLIENT_ID` for Android/iOS sign-in.
- `GOOGLE_DESKTOP_CLIENT_ID` for macOS/Windows/Linux desktop OAuth.
- `GOOGLE_DESKTOP_CLIENT_SECRET` for macOS/Windows/Linux desktop OAuth token exchange.

The user still signs in interactively at runtime and explicitly authorizes Drive access.
The app registration values above identify your app to Google OAuth.

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
