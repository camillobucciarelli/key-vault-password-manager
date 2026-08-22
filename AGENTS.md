# Repository Guidelines

## Project Structure & Module Organization

Cross-feature infrastructure lives in `lib/core/`. Keep one Password Manager feature under `lib/features/password_manager/{data,domain,presentation,di}`; do not split cloud sync, autofill, or vault workflows into new top-level features without an approved spec.

Three BLoCs (`presentation/bloc/{database_selection,database_unlock,vault}`) stay thin: event/state translation only. Put atomic business actions with policy, validation, or transaction value in `domain/usecases/`; put multi-step sequencing and rollback in `presentation/coordinators/` (`database_session_coordinator.dart`, `vault_session_coordinator.dart`, and dedicated integration coordinators). Do not create one-line pass-through use cases only for symmetry. Large screens are split into `*.part.dart` files assembled by the owning screen.

Domain repository/port contracts define application-required behavior; data implements them. Data sources own direct persistence, API, plugin, or platform access. Data services own technical integration and transaction mechanics by composing those sources. Presentation never imports data implementations or provider SDK types.

DI uses `get_it`, split across `lib/core/di/core_di.dart` and `lib/features/password_manager/di/*.dart`, assembled by `lib/injection_container.dart`. `data/services/vault_kdbx_service.dart` owns semantic KDBX parsing/edits. Approved raw-byte replacement, import, and sync writers remain in data services/orchestrator paths under shared `DatabasePathMutex`, backup, and safe-writer invariants; never bypass those protections or imply every vault write routes through `VaultKdbxService`.

Cloud sync is currently hard-coded to Google Drive. [Spec 010](specs/010-multi-cloud-storage/spec.md) plans one provider-neutral storage port, a sole Google data adapter, remote identity as `(providerId, remoteFileId)`, typed safe errors, and direct DI without a registry. Do not describe that refactor as implemented until its tasks land. Its deferred provider evidence/single-file constraints remain normative outside the immediate Google-only DoD. Autofill has two live paths: Apple (`apple_autofill_v2_coordinator.dart` + `ios/CredentialProviderExtension`, `macos/CredentialProviderExtension`) and desktop browsers (`desktop_browser_autofill_*.dart` + `desktop/native_host/` + `desktop/browser_extension/`). The native messaging protocol is Dart in `tool/native_host_protocol.dart`, entry point `tool/native_host.dart`.

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

**Windows prerequisite:** three QA suites build a `/var`→`/private/var`-style path divergence with `Link.create`, which on Windows requires Developer Mode or an elevated shell. Without it these files fail locally for environment reasons only — they are not skipped, since every CI Flutter job runs on `ubuntu-latest` and macOS is unaffected. Affected files: `test/features/password_manager/data/portable_path_symlink_qa_test.dart`, `test/core/utils/mobile_file_storage_guard_qa_test.dart`, `test/core/utils/mobile_file_storage_guard_bypass_qa_test.dart`.

### iOS container-relocation harness (manual, on-demand)

`integration_test/ios_portable_paths_qa_test.dart` is the only check that reproduces the iOS app-container relocation end to end: it runs the real `createNewDatabase` flow through the real DI graph and real `path_provider`, then re-drives `checkInitialDatabase()` after the container UUID has rotated. No CI job runs it, and `flutter test` never collects `integration_test/` — run it by hand when touching persisted-path code.

Prerequisite: a booted iOS simulator. Run the two phases in order, from the repo root:

```bash
# Phase 1 — create the vault and stash Documents/ to /tmp/qa_docs_backup.
flutter test integration_test/ios_portable_paths_qa_test.dart -d <simulator-id> \
  --dart-define=QA_PHASE=create

# Phase 2 — restores the stash into the new container and asserts the vault
# still resolves and unlocks. The uninstall performed between the two
# `flutter test` runs is what rotates the container UUID.
flutter test integration_test/ios_portable_paths_qa_test.dart -d <simulator-id> \
  --dart-define=QA_PHASE=verify
```

Phase 2 fails loudly (`container UUID did not change; the test proves nothing`) if the container did not actually rotate — if that happens, uninstall the app from the simulator and re-run phase 2. Progress is reported as `QA|KEY|value` lines; paths are only ever printed as a *shape*, never verbatim — assertion failures included, which is why the harness asserts on derived booleans and routes path diagnostics through `expectPortable`/`shape` instead of matching on the path itself.

Known limitation: the simulator does **not** reproduce the `/var` vs `/private/var` symlink divergence, because its container lives under `~/Library/Developer/CoreSimulator/...` with no symlinked component. The harness therefore does not replace physical-device QA for the Locate flow; it covers everything else.

## Commit & Pull Request Guidelines

Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`), scope optional (`fix(ci):`). Never hand-edit `version:` in `pubspec.yaml` — `.github/workflows/release.yml` bumps the build number on every push to `main`, commits `chore: bump build number to vX.Y.Z+N`, tags, and pushes.

## Agent Instructions

Per `.github/copilot-instructions.md`: if `graphify-out/GRAPH_REPORT.md` exists, read it before answering structural questions about the repo.

## Agent Branch Workflow

- Before changing files for an isolated development task, create a dedicated branch from `origin/main`, unless the user names another base.
- Use branch names `feat/<slug>`, `fix/<slug>`, `refactor/<slug>`, or `chore/<slug>`.
- If the shared worktree contains unrelated changes, do not switch branches. Create a separate Git worktree for the task instead.
- Do not reuse or modify another agent's branch or worktree.
- Do not push, merge, rebase, delete branches, open pull requests, or commit unless the user explicitly requests it.
- Before finishing, run relevant tests and report the branch name, worktree path when applicable, and verification performed.

## Agent Memory

- At the start of a task, recall relevant TokenSave decisions and inspect related Git history when prior intent matters.
- Record reusable architecture, workflow, and product decisions with TokenSave, including the reason and affected files.
- Update this file only when a repeated practice becomes a stable repository convention.
- Do not persist passwords, tokens, personal data, private keys, or other secrets in agent memory.
