# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A cross-platform Flutter password manager (Android, iOS, macOS, Windows, Linux, web). It uses the KeePass `.kdbx` format for encrypted vault storage, with Android/Apple autofill integration and a desktop browser autofill bridge.

## Commands

```bash
# Run the app (Google OAuth ids come from the dart-define file; see .env.dart.define.example.json)
flutter run --dart-define-from-file=.env.dart.define.json

# Run all tests
flutter test

# Run a single test file
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart

# Lint
flutter analyze

# Generate app icons (after changing assets/logo/keyvault-source.png)
flutter pub run flutter_launcher_icons

# Release artifacts -> dist/prod_packages/<timestamp>/
tool/build_prod_packages.sh --platforms android,linux

# Desktop native messaging host (compiles tool/native_host.dart)
tool/build_native_host.sh

# Browser extension zip
desktop/browser_extension/package_extension.sh
```

## Architecture

Clean architecture with three layers under `lib/features/password_manager/`:

- **`data/`** — `datasources/` (local storage, secure storage, biometric, Google OAuth token, sync metadata), `repositories/` (implementations), `services/` (kdbx read/write, sync, autofill bridges)
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
- `OtpAuthDeepLinkCoordinator` — `otpauth://` deep links, initialized in `main.dart`

Prefer adding logic to coordinators rather than BLoCs.

### Autofill

One Dart-side contract, `AppleAutofillV2CoordinatorContract` (name is historical — it covers Android too), fanned out by `CompositeAutofillV2Coordinator` in `password_manager_presentation_di.dart` to two implementations:

- **Native platforms** (`AppleAutofillV2Coordinator`): publishes credentials over the `dev.camillobucciarelli.keyvault/apple_autofill_v2` method channel. Native sides are Swift in `ios/CredentialProviderExtension/` and `macos/CredentialProviderExtension/` (`SharedAutofillStore`), and Kotlin in `android/app/src/main/kotlin/.../autofill/` (`KeyVaultAutofillService`, `AndroidAutofillV2Channel`, `AutofillPickerActivity`). No `flutter_autofill_service` package is used.
- **Desktop browsers** (`DesktopBrowserAutofillCoordinator`): writes an on-disk metadata cache (`desktop_browser_autofill_cache.dart`) plus a reveal bridge (`desktop_browser_autofill_reveal_bridge_service.dart`). `desktop/native_host/` (built from `tool/native_host.dart` + `tool/native_host_protocol.dart`) bridges `desktop/browser_extension/` to the running app.

Both directions carry pending associations (site ↔ entry links created from the native UI) back into the vault.

### Google Drive Sync

`DatabaseSyncOrchestrator` + `GoogleDriveApiService` + `DriveAuthService` implement the sync loop. Auth uses PKCE on desktop (`DesktopOAuthPkceService`) and `google_sign_in` on mobile. Sync metadata (checksums, timestamps, mappings) is stored locally via `SyncMetadataDataSource`.

### Key Files

- `lib/main.dart` — single entry point: logging setup, `di.init()`, otpauth deep-link coordinator, `runApp`
- `lib/features/password_manager/data/services/vault_kdbx_service.dart` — all `.kdbx` read/write/edit logic via the `kdbx` package
- `lib/core/theme/` — `AppTheme` + `ThemeCubit`
- `lib/core/utils/mobile_file_storage.dart` — sandboxed file I/O on mobile (iOS/Android store databases in app-internal directories)

### Vault Screen Structure

`presentation/screens/vault_screen.dart` is only the assembler: imports plus ten `part` directives pointing at `presentation/screens/vault/*.part.dart` (`vault_shell`, `vault_navigation`, `vault_entries`, `vault_entries_details`, `vault_dialogs`, `vault_duplicates`, `vault_recycle_bin`, …). Add vault UI to the matching part file, not to `vault_screen.dart`.

## Release

`.github/workflows/release.yml` bumps the build number in `pubspec.yaml` on every push to `main`, commits `chore: bump build number to vX.Y.Z+N`, tags, and pushes. Never hand-edit `version:`. CI runs no tests — run `flutter test` and `flutter analyze` locally.
