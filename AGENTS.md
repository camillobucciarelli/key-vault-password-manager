# Repository Guidelines

`CLAUDE.md` is a symlink to this file — one set of instructions for every agent. Edit this file.

A cross-platform Flutter password manager (Android, iOS, macOS, Windows, Linux, web) storing vaults in the KeePass `.kdbx` format, with Android/Apple autofill integration and a desktop browser autofill bridge.

## Project Structure & Module Organization

Cross-feature infrastructure lives in `lib/core/`. Keep one Password Manager feature under `lib/features/password_manager/{data,domain,presentation,di}`; do not split cloud sync, autofill, or vault workflows into new top-level features without an approved spec.

Three BLoCs (`presentation/bloc/{database_selection,database_unlock,vault}`) stay thin: event/state translation only. Put atomic business actions with policy, validation, or transaction value in `domain/usecases/`; put multi-step sequencing and rollback in `presentation/coordinators/` (`database_session_coordinator.dart`, `vault_session_coordinator.dart`, and dedicated integration coordinators). Do not create one-line pass-through use cases only for symmetry. Large screens are split into `*.part.dart` files assembled by the owning screen.

Domain repository/port contracts define application-required behavior; data implements them. Data sources own direct persistence, API, plugin, or platform access. Data services own technical integration and transaction mechanics by composing those sources. Presentation never imports data implementations or provider SDK types.

DI uses `get_it`, split across `lib/core/di/core_di.dart` and `lib/features/password_manager/di/*.dart`, assembled by `lib/injection_container.dart`. `data/services/vault_kdbx_service.dart` owns semantic KDBX parsing/edits. Approved raw-byte replacement, import, and sync writers remain in data services/orchestrator paths under shared `DatabasePathMutex`, backup, and safe-writer invariants; never bypass those protections or imply every vault write routes through `VaultKdbxService`.

Cloud sync is currently hard-coded to Google Drive. [Spec 010](specs/010-multi-cloud-storage/spec.md) plans one provider-neutral storage port, a sole Google data adapter, remote identity as `(providerId, remoteFileId)`, typed safe errors, and direct DI without a registry. Do not describe that refactor as implemented until its tasks land. Its deferred provider evidence/single-file constraints remain normative outside the immediate Google-only DoD. Autofill has two live paths: Apple (`apple_autofill_v2_coordinator.dart` + `ios/CredentialProviderExtension`, `macos/CredentialProviderExtension`) and desktop browsers (`desktop_browser_autofill_*.dart` + `desktop/native_host/` + `desktop/browser_extension/`). The native messaging protocol is Dart in `tool/native_host_protocol.dart`, entry point `tool/native_host.dart`.

## Architecture Map

| BLoC | Responsibility |
|------|----------------|
| `DatabaseSelectionBloc` | Entry point — selects/creates/removes databases, handles Google Drive file picking |
| `DatabaseUnlockBloc` | Unlocks a selected `.kdbx` file with password/key file/biometrics |
| `VaultBloc` | All vault operations once unlocked — CRUD entries/groups, search, sync, attachments, CSV import |

Coordinators: `DatabaseSessionCoordinator` (import/dedup/creation/unlock), `VaultSessionCoordinator` (lock/change-database/update-settings), `OtpAuthDeepLinkCoordinator` (`otpauth://` deep links, initialized in `main.dart`).

Autofill fans out from one Dart contract, `AppleAutofillV2CoordinatorContract` (the name is historical — it covers Android too), via `CompositeAutofillV2Coordinator` in `password_manager_presentation_di.dart`:

- **Native** (`AppleAutofillV2Coordinator`) publishes credentials over the `dev.camillobucciarelli.keyvault/apple_autofill_v2` method channel. Native sides are Swift in `ios/CredentialProviderExtension/` and `macos/CredentialProviderExtension/` (`SharedAutofillStore`), Kotlin in `android/app/src/main/kotlin/.../autofill/` (`KeyVaultAutofillService`, `AndroidAutofillV2Channel`, `AutofillPickerActivity`). No `flutter_autofill_service` package is used.
- **Desktop browsers** (`DesktopBrowserAutofillCoordinator`) writes an on-disk metadata cache (`desktop_browser_autofill_cache.dart`) plus a reveal bridge (`desktop_browser_autofill_reveal_bridge_service.dart`).

Both directions carry pending associations (site ↔ entry links created from the native UI) back into the vault.

Sync: `DatabaseSyncOrchestrator` + `GoogleDriveApiService` + `DriveAuthService`. Auth uses PKCE on desktop (`DesktopOAuthPkceService`) and `google_sign_in` on mobile; checksums, timestamps and mappings live in `SyncMetadataDataSource`.

Key files:

- `lib/main.dart` — single entry point: logging setup, `di.init()`, otpauth deep-link coordinator, `runApp`
- `lib/core/theme/` — `AppTheme` + `ThemeCubit`
- `lib/core/utils/mobile_file_storage.dart` — sandboxed file I/O on mobile (iOS/Android keep databases in app-internal directories)
- `presentation/screens/vault_screen.dart` — assembler only: imports plus ten `part` directives pointing at `presentation/screens/vault/*.part.dart` (`vault_shell`, `vault_navigation`, `vault_entries`, `vault_entries_details`, `vault_dialogs`, `vault_duplicates`, `vault_recycle_bin`, …). Add vault UI to the matching part file, never to `vault_screen.dart`.

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

### Flutter toolchain pin

Flutter is pinned to the exact version **3.47.1** (stable, revision `6655482ec0`).

**`.fvmrc` is the single source of truth.** It holds `{"flutter": "3.47.1"}` and
nothing else restates the version:

- Locally, `fvm flutter …` reads it.
- In CI, every `subosito/flutter-action@v2` step passes
  `flutter-version-file: .fvmrc` (the action parses that file's `flutter` key
  directly). Do **not** add a `flutter-version:` next to it — the action refuses
  both at once, and a second copy of the version is how local and CI drift apart.
- `tool/build_prod_packages.sh` reads it too, prepends a matching fvm SDK to
  `PATH` when it finds one, and then **fails the build** if the resolved
  `flutter --version` is not the pinned one.

The pin is an exact version, not the `stable` channel, because a channel moves
under the repo: when stable advanced from 3.44.8 to 3.47.1 a clean checkout of
`main` went from 1318 passing tests to 42 golden failures (sub-1% antialiasing
diffs) plus a `pub get --enforce-lockfile` failure, with no change to the code.
A moving toolchain means the test gate is not reproducible from the repository —
a fresh clone and CI can disagree with each other and with yesterday's green run.

**To upgrade the toolchain** (a dedicated change, never a side effect of
something else):

1. Bump the version in `.fvmrc`. That is the only place it is written.
2. `fvm install && fvm use <version>`, then `fvm flutter pub get`.
3. Regenerate the golden files and review the diffs — confirm they are rendering
   changes from the new engine, not real UI regressions.
4. Run `fvm flutter analyze` and the full `fvm flutter test`, and record the
   before/after counts in the PR.
5. Update the version and revision quoted in this section.
6. Install the new version on the self-hosted runners (below) *before* the next
   release, or their jobs will fail the version check by design.

#### Self-hosted release runners

The `ios` and `macos` jobs in `release.yml` run on `runs-on: self-hosted` and have
no `flutter-action` step, so nothing in the workflow installs a toolchain — they
build with whatever Flutter the machine provides. These jobs produce the
*published* artifacts, so a wrong version there ships a binary rather than merely
reddening a test.

The repo cannot install software on those machines, so instead it refuses to build
with the wrong one: `tool/build_prod_packages.sh` (the single entry point for all
five build jobs) resolves and verifies the version as described above. A
mismatched runner now fails loudly with an actionable message instead of silently
shipping.

Whoever administers those runners must therefore keep the pinned version present,
by either:

- installing fvm and running `fvm install 3.47.1` once, so the SDK is at
  `~/fvm/versions/3.47.1/` where the script looks; or
- putting Flutter 3.47.1 itself on the runner's `PATH`.

The `ios-app-store-publish` and `macos-app-store-publish` jobs are also
self-hosted but do not need Flutter: they download an artifact built by an earlier
job and upload it.

## Coding Style & Naming Conventions

`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` with no overrides. Default `dart format` (2-space indent). Files are snake_case; test files mirror the `lib/` path under `test/` with a `_test.dart` suffix.

## Testing Guidelines

`flutter_test`; tests live in `test/` mirroring `lib/`, plus `test/tool/native_host_test.dart` for the native host protocol. CI runs no tests — run `flutter test` and `flutter analyze` before pushing.

**Test order must not matter.** The `test-random-order` PR job runs the suite under a fresh `--test-randomize-ordering-seed` on every run, so a new order dependence fails immediately instead of lying dormant until something reshuffles the suite. That job excludes `test/goldens/*` for the same macOS-rasterization reason the `test` job does, so **golden ordering is only ever checked locally** — when you touch a golden or its harness, run `flutter test test/goldens --test-randomize-ordering-seed=$RANDOM` as well as the plain run. Two rules keep goldens order-independent: never resolve `di.sl<T>()` inside `dispose()` (capture the dependency in `initState` — teardown must not require the locator to still be registered), and warm any `Image.asset` a golden renders via `warmUpGoldenAssets()` in `setUpAll`, because asset decoding completes on the real event loop and `pumpAndSettle()` never advances it, so whichever test mounts the asset first would otherwise capture a blank image.

**Windows prerequisite:** three QA suites build a `/var`→`/private/var`-style path divergence with `Link.create`, which on Windows requires Developer Mode or an elevated shell. Without it these files fail locally for environment reasons only — they are not skipped, since every CI Flutter job runs on `ubuntu-latest` and macOS is unaffected. Affected files: `test/features/password_manager/data/portable_path_symlink_qa_test.dart`, `test/core/utils/mobile_file_storage_guard_qa_test.dart`, `test/core/utils/mobile_file_storage_guard_bypass_qa_test.dart`.

### Manual, on-demand QA harnesses

Three harnesses run by hand only, never in CI: the spec 008 T111 safe-writer
platform harness, the spec 011 master-password keystore probe, and the iOS
container-relocation harness. Their full procedures and invariants live in the
`manual-qa-harnesses` skill (`.claude/skills/manual-qa-harnesses/SKILL.md`) —
read it before running or changing any of them.

## Commit & Pull Request Guidelines

Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`), scope optional (`fix(ci):`). Never hand-edit `version:` in `pubspec.yaml` — `.github/workflows/release.yml` bumps the build number on every push to `main`, commits `chore: bump build number to vX.Y.Z+N`, tags, and pushes.

## Agent skills

### Issue tracker

Ordinary requests use GitHub Issues; roadmap specs remain repository-authored and are mirrored to GitHub Project #2. See `docs/agents/issue-tracker.md`.

### Triage labels

Ordinary issues use the canonical `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix` states. Generated `spec` issues are excluded. See `docs/agents/triage-labels.md`.

### Domain docs

Use the single-context domain documentation layout. See `docs/agents/domain.md`.

## Agent Instructions

Per `.github/copilot-instructions.md`: if `graphify-out/GRAPH_REPORT.md` exists, read it before answering structural questions about the repo.

## Spec Task Tracking

When you finish work that completes a task in a `specs/NNN-*/tasks.md` file, tick that task's box (`- [ ]` → `- [x]`) in the same change that lands the work. This is not bookkeeping: `tasks.md` is the sole source of completed roadmap work (Projects v2 #2), and `.github/workflows/spec-project-sync.yml` derives each spec's issue body and Status from those boxes on every push to `main`. An untouched box means the board reports the work as not done. Open PRs touching a spec are detected separately and make it `In Progress`; their unmerged boxes never count as completed.

Tick a box only when that task's own acceptance criteria are met and its tests pass. Never edit the generated issue body or move a card by hand — the next sync overwrites both. To resync without a push: `PROJECT_NUMBER=2 tool/sync_spec_project.sh`.

The same duty covers every other spec edit, not just ticking boxes: adding or removing a spec, renaming one, adding, deleting, reordering or rewording tasks. The board must end up consistent with `specs/` in the same change, so keep the shapes the sync depends on:

- `specs/NNN-slug/spec.md` — first line is `# <id> — <Title>`; the id (`001`, `007A`) is the issue's identity. Changing the id orphans the existing issue and creates a second one; change the title freely, never the id.
- `tasks.md` — task lines start at column 0 as `- [ ]` / `- [x]`; continuation lines are indented. Anything else is invisible to the sync.
- A spec with no `tasks.md` shows as `Todo` with an explanatory body — expected for drafts.

After a spec change, run the script (`PROJECT_NUMBER=2 tool/sync_spec_project.sh`) or the `Spec project sync` workflow via `workflow_dispatch`, and report the resulting board state. Do not leave `specs/` and the board disagreeing.

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
