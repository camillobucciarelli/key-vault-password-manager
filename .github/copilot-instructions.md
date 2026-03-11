# Copilot Instructions

## Build, test, and lint commands

- Install dependencies: `flutter pub get`
- Lint/static analysis: `flutter analyze`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart`
- Run a single test by name: `flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart --plain-name "maps created and modified timestamps for new entries"`
- Run with OAuth dart-defines (from local docs): `flutter run --dart-define-from-file=.env.dart.define.json`
- Build production packages (multi-platform wrapper script): `tool/build_prod_packages.sh --env-file .env.dart.define.json`

## High-level architecture

- App bootstrap is in `lib/main.dart`: it configures logging/error handlers, initializes DI (`di.init()`), then starts autofill coordinators/services before `runApp`.
- Dependency wiring is centralized with GetIt:
  - Root: `lib/injection_container.dart`
  - Core registrations: `lib/core/di/core_di.dart`
  - Feature registrations split by layer under `lib/features/password_manager/di/` (`data`, `domain`, `presentation`).
- The main feature follows layered structure:
  - `data/`: data sources (local/secure/biometric/sync metadata) + service implementations (`VaultKdbxService`, Drive auth/API/sync orchestrator, autofill bridge/coordinators)
  - `domain/`: repository contracts, models, and use cases
  - `presentation/`: BLoCs + screens/widgets
- Navigation flow is coordinator-driven:
  - Selection (`DatabaseSelectionScreen`) -> unlock (`DatabaseUnlockScreen`) -> vault (`VaultScreen`)
  - Transition logic is centralized in `presentation/screens/coordinators/database_flow_coordinator.dart`.
- Desktop browser autofill path spans multiple surfaces:
  - In-app local bridge: `DesktopAutofillBridgeService` (loopback HTTP + rotating bearer token)
  - Native host runtime: `tool/native_host.dart`
  - Extension assets and packaging under `desktop/browser_extension/` and `desktop/native_host/` (see `docs/desktop_browser_autofill.md`).
- Google Drive sync flow is implemented through `DatabaseSyncOrchestrator` and metadata persistence, with runtime setup documented in `docs/google_drive_sync.md`.

## Key repository-specific conventions

- Use DI registration modules instead of ad-hoc object creation; new dependencies should be registered in the appropriate `*_di.dart` layer file.
- Presentation state is BLoC-based; search-like events use stream transformers (`debounce + distinct + switchMap`) in `VaultBloc` to avoid noisy state updates.
- `VaultScreen` is intentionally split with `part` files (`vault_*.part.dart`) to keep one screen’s UI logic modular; follow this split when extending vault UI behavior.
- Autofill behavior is platform-gated and credential-safe by default:
  - Android/iOS coordinators no-op when unsupported platform or unavailable credentials.
  - Desktop bridge rotates auth token and filters matches by host/subdomain relationship before returning credentials.
- Sync logic is checksum-driven (`DatabaseSyncOrchestrator`):
  - first-sync-without-baseline is treated explicitly
  - conflicts return typed conflict results unless a resolution is provided
  - remote-download fallback is used when Drive metadata checksum is missing.
- Tests in `test/features/password_manager/data/services/` focus on service-level behavior and edge-case semantics (timestamps, conflict handling, import parsing); follow this style for new service tests.
