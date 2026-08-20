# Google Drive Sync Setup

This app supports KDBX sync with Google Drive on Android, iOS, macOS, Windows, and Linux.

## OAuth Configuration

Create OAuth clients in Google Cloud Console and pass credentials via `--dart-define-from-file`:

Each env key maps 1:1 to a Google Cloud Console OAuth client type:

- `GOOGLE_IOS_CLIENT_ID` — GCP client type **iOS**. Used for iOS sign-in.
- `GOOGLE_WEB_CLIENT_ID` — GCP client type **Web application**. Used by Android Google Sign-In as the server client ID for token exchange.
- `GOOGLE_DESKTOP_CLIENT_ID` — GCP client type **Desktop app**. Used for macOS/Windows/Linux desktop OAuth.
- `GOOGLE_DESKTOP_CLIENT_SECRET` — secret of the same **Desktop app** client.

The user still signs in interactively at runtime and explicitly authorizes Drive access.
The app registration values above identify your app to Google OAuth.

Android still requires proper package + SHA configuration in Google Cloud OAuth and,
with `google_sign_in` v7 flow, a server/web client ID at runtime via
`GOOGLE_WEB_CLIENT_ID`.

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
