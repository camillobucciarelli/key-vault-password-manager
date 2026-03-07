# Google Drive Sync Setup

This app supports KDBX sync with Google Drive `appDataFolder` on Android, iOS, macOS, Windows, and Linux.

## OAuth Configuration

Create OAuth clients in Google Cloud Console and pass credentials via `--dart-define`:

- `GOOGLE_MOBILE_CLIENT_ID` for Android/iOS sign-in.
- `GOOGLE_DESKTOP_CLIENT_ID` for macOS/Windows/Linux desktop OAuth.
- `GOOGLE_DESKTOP_CLIENT_SECRET` for macOS/Windows/Linux desktop OAuth token exchange.

Example:

```bash
flutter run --dart-define=GOOGLE_MOBILE_CLIENT_ID=... --dart-define=GOOGLE_DESKTOP_CLIENT_ID=... --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...
```

## Runtime Flow

1. Open a database.
2. From the Vault top-right cloud menu:
   - Connect Google Drive.
   - Link this database.
   - Sync now.
   - Enable/disable auto-sync.
3. On conflict, choose one:
   - Keep local
   - Use remote
   - Cancel

All remote files are created or managed in Google Drive `appDataFolder` with scope `drive.file`.
