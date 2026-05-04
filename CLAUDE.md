# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A cross-platform Flutter password manager (Android, iOS, macOS, Windows, Linux, web). It uses the KeePass `.kdbx` format for encrypted vault storage, with Android/iOS autofill integration and a desktop browser autofill bridge.

## Commands

```bash
# Run the app
flutter run

# Run all tests
flutter test

# Run a single test file
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart

# Lint
flutter analyze

# Generate app icons (after changing assets/logo/keyvault-source.png)
flutter pub run flutter_launcher_icons
```

## Architecture

Clean architecture with three layers under `lib/features/password_manager/`:

- **`data/`** — `datasources/` (local storage, secure storage, biometric, Google OAuth), `models/` (JSON serialization), `repositories/` (implementations), `services/` (kdbx read/write, sync, autofill coordinators)
- **`domain/`** — `entities/`, `models/` (pure Dart value objects), `repositories/` (abstract interfaces), `usecases/`, `services/` (e.g., autofill URL matching)
- **`presentation/`** — `bloc/` (events/states), `coordinators/` (see below), `screens/`, `widgets/`

Dependency injection via `get_it` (`lib/injection_container.dart`), split into three registration files under `features/password_manager/di/`.

### State Management

Three BLoCs drive the app:

| BLoC | Responsibility |
|------|----------------|
| `DatabaseSelectionBloc` | Entry point — selects/creates/removes databases, handles Google Drive file picking |
| `DatabaseUnlockBloc` | Unlocks a selected `.kdbx` file with password/key file/biometrics |
| `VaultBloc` | All vault operations once unlocked — CRUD entries/groups, search, sync, attachments, CSV import |

### Coordinators

Coordinators sit between BLoCs and use cases, handling multi-step workflows that touch several use cases and services. They are the main place for complex business logic:

- `DatabaseSessionCoordinator` — database import/dedup/creation/unlock flow
- `VaultSessionCoordinator` — lock/change-database/update-settings flow

Prefer adding logic to coordinators rather than BLoCs.

### Autofill

Three platform-specific autofill paths:

- **Android**: `AndroidAutofillCoordinator` — hooks into `WidgetsBindingObserver` via `flutter_autofill_service`, responds to autofill framework requests at app resume
- **iOS**: `IosAutofillSnapshotCoordinator` — writes a JSON snapshot of vault entries that the iOS credential provider extension reads
- **Desktop**: `DesktopAutofillBridgeService` + `desktop/native_host/` and `desktop/browser_extension/` — a native messaging host bridges the browser extension to the running app

### Google Drive Sync

`DatabaseSyncOrchestrator` + `GoogleDriveApiService` + `DriveAuthService` implement the sync loop. Auth uses PKCE on desktop (`DesktopOAuthPkceService`) and `google_sign_in` on mobile. Sync metadata (checksums, timestamps, mappings) is stored locally via `SyncMetadataDataSource`.

### Key Files

- `lib/main.dart` — bootstrap, two entry points (`main` and `autofillEntryPoint`)
- `lib/features/password_manager/data/services/vault_kdbx_service.dart` — all `.kdbx` read/write/edit logic via the `kdbx` package
- `lib/core/theme/` — `AppTheme` + `ThemeCubit`
- `lib/core/utils/mobile_file_storage.dart` — sandboxed file I/O on mobile (iOS/Android store databases in app-internal directories)

### Vault Screen Structure

`vault_screen.dart` is split into several `part` files (`vault_entries.part.dart`, `vault_dialogs.part.dart`, etc.) for size management. All parts are assembled by `vault_screen.dart`.
