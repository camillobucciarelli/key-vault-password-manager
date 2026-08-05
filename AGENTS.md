# Repository Guidelines

## Project Structure & Module Organization

Clean architecture lives under `lib/features/password_manager/{data,domain,presentation}`. DI is `get_it`, split across `lib/core/di/core_di.dart` and `lib/features/password_manager/di/*.dart`, assembled by `lib/injection_container.dart`.

Three BLoCs (`presentation/bloc/{database_selection,database_unlock,vault}`) delegate multi-step flows to `presentation/coordinators/` — `database_session_coordinator.dart` and `vault_session_coordinator.dart` carry the workflow logic. Put new business logic in coordinators, not BLoCs. Large screens are split into `*.part.dart` files assembled by the owning screen.

Vault I/O is KeePass `.kdbx` through `data/services/vault_kdbx_service.dart`. Autofill has two live paths: Apple (`apple_autofill_v2_coordinator.dart` + `ios/CredentialProviderExtension`, `macos/CredentialProviderExtension`) and desktop browsers (`desktop_browser_autofill_*.dart` + `desktop/native_host/` + `desktop/browser_extension/`). The native messaging protocol is Dart in `tool/native_host_protocol.dart`, entry point `tool/native_host.dart`.

## Build, Test, and Development Commands

```bash
flutter run --dart-define-from-file=.env.dart.define.json   # OAuth ids required; see .env.dart.define.example.json
flutter test
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart
flutter analyze
tool/build_prod_packages.sh --platforms android,linux        # artifacts -> dist/prod_packages/<timestamp>/
tool/build_native_host.sh                                    # compile desktop native host
desktop/browser_extension/package_extension.sh               # zip the extension
flutter pub run flutter_launcher_icons                       # after changing assets/logo/
```

Flutter version is pinned via fvm (`.fvmrc`, channel `stable`).

## Coding Style & Naming Conventions

`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` with no overrides. Default `dart format` (2-space indent). Files are snake_case; test files mirror the `lib/` path under `test/` with a `_test.dart` suffix.

## Testing Guidelines

`flutter_test`; tests live in `test/` mirroring `lib/`, plus `test/tool/native_host_test.dart` for the native host protocol. CI runs no tests — run `flutter test` and `flutter analyze` before pushing.

## Commit & Pull Request Guidelines

Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`), scope optional (`fix(ci):`). Never hand-edit `version:` in `pubspec.yaml` — `.github/workflows/release.yml` bumps the build number on every push to `main`, commits `chore: bump build number to vX.Y.Z+N`, tags, and pushes.

## Agent Instructions

Per `.github/copilot-instructions.md`: if `graphify-out/GRAPH_REPORT.md` exists, read it before answering structural questions about the repo.
