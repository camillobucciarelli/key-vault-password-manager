# 013 — Implementation plan

## Delivery strategy

A release blocker delivered as one atomic five-platform cut, not as a gradual
rollout. The narrow scope and the Picker replace the restricted scope and the
in-app list together; there is no intermediate build that ships one without the
other, because a build with `drive.file` and a `files.list` picker cannot find
any file, and a build with the Picker and the restricted scope still shows the
unverified-app interstitial.

Everything before the production phases is proof, not code: Gate 0-A establishes
that the flow is technically possible on real devices, Phase 1 establishes the
public prerequisites, Gate 0-B establishes that the original symptom is actually
gone. Production work starts only after both checkpoints are recorded as `pass`.

This plan changes authorization and selection. It changes no sync decision, no
conflict policy, no checksum, no backup and no KDBX byte. Copy changes are
limited to the two exposed actions, the generic `Google Drive connected` label
and the read-only/Shared-Drive refusal messages; every other string stays
byte-identical.

**Owner agent**: `senior-flutter-dev`
**Platform agents**: `senior-android-dev` (T302 Kotlin bridge, `play-services-auth`
pin), `senior-apple-dev` (T303 Swift/AppAuth bridge, Keychain).
`senior-tester` validates Phase 5 and the Phase 6 gate. Windows and Linux need no
native change — the desktop path is the existing Dart loopback service — so the
Windows/Linux specialists are involved only if T304 unexpectedly requires native
source.

## Constitution Check

Checked against `.specify/memory/constitution.md` v1.1.2. No gate is violated and
no complexity waiver is needed.

| Principle | Verdict | Evidence |
| --- | --- | --- |
| I — Secrets never leak into the shell | PASS | Spec §Architecture rule 1 keeps tokens, authorization codes and `picked_file_ids` in the data layer; T502 injects sentinels for token, code, callback URL, `picked_file_ids`, file ID and email and asserts absence from logs, state, errors and the persisted mapping; T007/T503 scan release builds. T202 removes the desktop client secret from the runtime entirely, and T501 fails if it reappears. |
| II — Clean architecture layering holds | PASS | OAuth and Picker stay in `data/services/`; the select-one operation is added to the existing repository port (T301); the migration sequence is a coordinator (T401), not a BLoC and not a use case; no new BLoC. |
| III — Design tokens | PASS | The two replacement actions and the refusal surfaces are built from `AppColors`/`AppSpacing`/`AppRadii`/`AppMotion`; removing `drive_picker_sheet.dart` removes call sites rather than adding hard-coded values. |
| IV — Pixel fidelity is testable | PASS | T305 updates the golden inventory for the removed list: `db_drive_empty_390x844_light.png`, `db_drive_loading_390x844_light.png` and `sync_picker_390x844_light.png` are deleted or replaced, and the two-action surface gets its own goldens at 390×844 and 1024×768 in light and dark. Picker and consent are OS-owned UI and are covered by widget assertions on the trigger plus the manual gate, not by goldens. |
| V — Accessibility floor | PASS | The two actions and the refusal messages carry ≥ 4.5:1 contrast, ≥ 44×44 targets, focus rings and non-colour signalling, asserted in the T305/T307 widget tests. |
| VI — Copy preserved unless a spec marks a change | PASS | Authorized changes are exactly: the two action labels, `Google Drive connected` (spec §UX rule 6), and the read-only/Shared-Drive refusal messages (rules 5 and 7). The Italian browser-setup labels and every other literal stay byte-identical. |
| VII — Destructive operations ask first and back up | PASS | T402 requires explicit confirmation before revoking and states that sync disconnects on all devices; T404 requires confirmation before a changed file ID creates a new mapping, with content comparison and the safe writer mandatory; T405 leaves vault bytes untouched on every abort path. |
| VIII — Ship the smallest thing | PASS | No new Flutter plugin, no `google_sign_in` fork, no backend, no provider registry. The port gains one operation and loses one; the Kotlin and Swift bridges are minimal channels over SDKs already present. The port itself is covered by the explicit domain-port/trust-boundary exemption. |
| IX — Verification is local | PASS | T504 runs `dart format`, `flutter analyze` and the full `flutter test` before commit; `pubspec.yaml: version:` is untouched. |

### Phase 0 / Phase 1 artifacts

`research.md` is not generated. `spec.md` carries no `[NEEDS CLARIFICATION]`
marker, and its two open questions — whether a folder grant permits
`files.create` with `parents`, and whether Android persists a usable refresh
across restarts — are explicitly not design questions: they are empirical and are
answered by Gate 0 items 5 and 6 on real hardware. Writing a research document
against them would record a guess where the spec demands an observation. Their
answers land in `feasibility-report.md`, which is the Phase 0 artifact of this
spec.

`data-model.md` is not generated. The constitution requires it only for specs 008
and 009. This spec adds no entity: it changes the OAuth scope string, replaces one
port operation with another and preserves the mapping schema owned by spec 010.

`contracts/` and `quickstart.md` are not generated either. The port contract is
normative inline in `spec.md` §Architecture and §Authorization model; the
validation procedure is the Gate 0 criteria table, the Phase 5 commands below and
the five-platform release gate. A side copy would be a third statement of the same
rules and would drift from the two that are already normative.

## Dependency and safety gates

1. **Gate 0-A blocks everything.** No production file changes until T001–T007 and
   T009 are recorded `pass` on physical Android, physical iPhone and real macOS.
   The absence of `feasibility-report.md` means the spike has not run and is never
   read as a pass.
2. **Gate 0-B blocks Phase 2 onwards.** Criterion 11 must be recorded after
   Phase 1 publishes the site, verifies the domain and publishes the branding. A
   report without a criterion 11 row is an incomplete Gate 0.
3. **Order against spec 010.** 010 is scheduled first; the recorded order is
   010 → 013, with Gate 0-A runnable in parallel because it touches no production
   path. If 010 has landed, T301 adds select-one to `CloudStorageProvider` and the
   work sits inside `GoogleDriveStorageProvider`. If 013 lands first, the same
   boundary is respected against the current `DatabaseSyncRepository`, and
   whichever lands second rebases and re-runs the selection suites. Neither spec
   implements the other's tasks.
4. **Spec 008 invariants are untouched.** No `.kdbx` write path is added. Every
   remote-to-local write keeps routing through the single process-wide
   `DatabasePathMutex`, the collision-safe backup and the safe writer. Do not
   instantiate a private mutex and do not add a second writer.
5. **Sync semantics are untouched.** `DatabaseSyncOrchestrator` decision branches,
   checksums, timeouts and baselines stay as they are. Migration resumes with the
   existing checksum and timestamp baselines; recreating a mapping with null
   baselines is forbidden because it would re-run a first sync.
6. **The old grant is never reused.** After a failed or unverifiable revocation,
   sync stays suspended. There is no code path that retries with the previous
   token.
7. **No rollback restores the broad scope.** The documented backout is disabling
   Drive temporarily. Restoring `auth/drive` or re-enabling a legacy client is
   forbidden in every scenario.

## Milestones and dependency order

```text
Gate 0-A (spike branch, no production code)
 -> Phase 1 site + domain + branding + public clients
 -> Gate 0-B external consent screen clean
 -> Phase 2 OAuth least privilege
 -> Phase 3 Picker integration
 -> Phase 4 migration and revocation
 -> Phase 5 regression and security gates
 -> Phase 6 atomic five-platform release + legacy client cut
 -> Website/extension/archival tail
```

Each phase compiles and tests before the next. Phase 1 and Gate 0-A are the only
pair that may overlap in wall-clock time, and only because Gate 0-A needs nothing
Phase 1 produces.

## Gate 0-A — feasibility spike (T001–T007, T009)

Runs on a dedicated spike branch whose diff touches nothing under `lib/`,
`android/app/src/main/`, `ios/Runner/` or `macos/Runner/`. The spike may hard-code,
duplicate and shortcut freely; none of it merges.

What the spike must exercise, mapped to the production surfaces it will later
inform:

- authorization request shape → will become `drive_auth_service.dart` and
  `desktop_oauth_pkce_service.dart`;
- Android one-pick trigger and `picked_file_ids` → will become the Kotlin bridge;
- iOS AppAuth + Keychain → will become the Swift bridge;
- desktop loopback with `trigger_onepick=true` → extends the existing service.

Gate: `feasibility-report.md` exists, carries criteria 1–10 per target with UTC
date and OS/SDK version class, records criterion 5 as `folder_parent_accepted` or
`root_fallback`, contains no `not-run` row and none of the forbidden values.
The criterion 5 outcome is a binding input to T306: the shipped creation
behaviour matches what was observed, not what was hoped.

## Phase 1 — public prerequisites (T101–T105)

New directory `website/`, static content only:

- `website/index.html` — English homepage
- `website/privacy.html` — privacy policy describing exactly the `drive.file`
  access model, support email `camillo@bucciarelli.dev`, no analytics collecting
  personal data
- serves both `/` and `/privacy` on `keyvault.camillobucciarelli.dev`

No file outside `website/` changes in this phase. DNS, deployment, Search Console
verification, Cloud Console branding and the new OAuth clients are human-operator
work recorded as boolean evidence. No client ID or secret is committed.

## Gate 0-B — external consent (T008)

Appends the criterion 11 row to the same `feasibility-report.md`. Blocking for
Phase 2 with no `not-run` waiver.

## Phase 2 — OAuth least privilege (T201–T204)

### Change

- `lib/features/password_manager/data/services/drive_auth_service.dart` —
  `_requiredDriveScope` (line 34 today) becomes exactly
  `https://www.googleapis.com/auth/drive.file`; no identity scope is added.
- `lib/features/password_manager/data/services/desktop_oauth_pkce_service.dart` —
  `_scope` (line 55 today) likewise; `clientSecret` parameters and the
  `client_secret` form fields in the token and refresh requests are removed, so
  the desktop client is a public installed-app client.
- `lib/features/password_manager/data/services/google_oauth_config.dart` — the
  `desktopClientSecret` field and its `String.fromEnvironment` read are deleted.
- `.env.dart.define.example.json` and the build docs — the
  `GOOGLE_DESKTOP_CLIENT_SECRET` define is removed so no build supplies it.
- `lib/features/password_manager/domain/models/drive_account_summary.dart` and the
  sync status/connection widgets — any email-bearing field is removed; the label
  becomes the generic `Google Drive connected`.

PKCE `S256` and `state` validation become mandatory rather than incidental: a
missing verifier or a mismatched `state` fails closed and persists no token.

Likely tests changed/added:

- `test/features/password_manager/data/services/drive_auth_service_test.dart`
- `test/features/password_manager/data/services/desktop_oauth_pkce_service_test.dart` (new)
- `test/features/password_manager/presentation/widgets/database/google_oauth_config_repro_test.dart`

Gate: a test pins the exact scope string set; a source search finds no runtime
client-secret reference; the account label carries no email.

## Phase 3 — Picker integration (T301–T307)

### Port change

The port loses "list remote objects" and gains "select exactly one remote
object", alongside create, read, update and download by opaque ID. Target is
`CloudStorageProvider` if 010 has landed, otherwise `DatabaseSyncRepository`.
Presentation receives no token, no `picked_file_ids` value and no provider SDK
type — enforced by an architecture guard test, not by review.

### Add

- Android: minimal Kotlin bridge under
  `android/app/src/main/kotlin/dev/camillobucciarelli/kdbxKeyVault/drive/`, one
  method channel, alongside the existing `autofill/` bridge it mirrors in style.
  `android/app/build.gradle.kts` gains an explicit
  `play-services-auth >= 21.6.0, < 22.0.0` pin — the dependency is transitive via
  `google_sign_in` today and must become explicit so the floor is enforced.
  `google_sign_in` is not forked.
- iOS: minimal Swift bridge over the AppAuth dependency already present
  transitively, under `ios/Runner/`, with the refresh token in the Keychain and
  never crossing the channel into Dart.
- Dart counterparts for both bridges in `data/services/`.

### Change

- `lib/features/password_manager/data/services/desktop_oauth_pkce_service.dart` —
  extended with `trigger_onepick=true` and `picked_file_ids` parsing. No new
  desktop dependency.
- `lib/features/password_manager/data/services/google_drive_api_service.dart` —
  the `files.list` discovery path is deleted, not merely unused.

### Delete

- `lib/features/password_manager/presentation/widgets/database/drive_picker_sheet.dart`
- `lib/features/password_manager/presentation/widgets/database/drive_picker_skeleton.dart`
- `lib/features/password_manager/presentation/widgets/sync/remote_file_row.dart`
  (only if 010 has not already repurposed it; otherwise its list call site goes)
- goldens `test/goldens/db_drive_empty_390x844_light.png`,
  `db_drive_loading_390x844_light.png`, `sync_picker_390x844_light.png`
- `test/features/password_manager/presentation/screens/vault/remote_file_picker_test.dart`
  is replaced by a two-action selection test

The database selection and vault sync surfaces expose exactly two actions. The
creation path takes an editable default name equal to the local file name, and a
destination folder if and only if Gate 0 recorded `folder_parent_accepted`;
otherwise it creates in the root of My Drive and says so. A read-only picked file
becomes a local copy with sync disabled and a stated reason; a Shared Drive result
is refused safely. Neither creates a mapping claiming write access.

Gate: architecture guard passes; widget, coordinator and golden suites green;
physical Android and physical iPhone runs of the full flow; real macOS run.

## Phase 4 — migration and revocation (T401–T406)

### Add

- `lib/features/password_manager/presentation/coordinators/drive_scope_migration_coordinator.dart`

It owns the whole ordered sequence — suspend, confirm, revoke, re-consent,
re-pick, validate, resume — per vault, triggered on open or on sync, with
multiple mappings migrating independently. Baselines are carried across, never
reset.

The existing `google_drive_reconnect_coordinator.dart` is the natural neighbour:
review whether the migration sequence belongs inside it before adding a second
coordinator. Add the new file only if the reconnect coordinator would otherwise
carry two unrelated sequences.

### Change

- `lib/features/password_manager/data/datasources/sync_metadata_data_source.dart` —
  a suspended/needs-reconnection marker per mapping; no schema rewrite beyond it.
- the background sync path — never presents UI, fails safe, marks the mapping as
  needing reconnection. Reconnection is requested in the foreground only.

Gate: coordinator tests cover every step boundary, both branches of the changed
file ID, each abort path, and assert zero requests carrying the old grant after a
failed revocation.

## Phase 5 — regression and security (T501–T504)

### Targeted commands

```bash
dart format lib/features/password_manager test/features/password_manager
flutter analyze
flutter test test/features/password_manager/data/services/drive_auth_service_test.dart
flutter test test/features/password_manager/data/services/desktop_oauth_pkce_service_test.dart
flutter test test/features/password_manager/data/services/google_drive_api_service_test.dart
flutter test test/features/password_manager/data/services/database_sync_orchestrator_test.dart
flutter test test/features/password_manager/presentation/coordinators
flutter test test/features/password_manager/presentation/screens/database_selection_unlock_widget_matrix_test.dart
flutter test test/goldens/database_and_unlock_test.dart
flutter test test/goldens/sync_health_import_test.dart
flutter test
```

### Guard searches

```bash
rg -n 'googleapis\.com/auth/drive(?!\.file)' lib test tool
rg -n 'client_secret|clientSecret|GOOGLE_DESKTOP_CLIENT_SECRET' lib test tool
rg -n 'files\.list|listRemoteFiles|DrivePickerSheet' lib test
rg -n 'WebView|webview' lib android/app/src/main ios/Runner macos/Runner
```

Expected: zero results for all four in production and test paths. A hit in the
first two is a Principle I violation, not a style nit. T501 turns the first two
into a failing guard test rather than a search someone must remember to run.

## Phase 6 — release gate and legacy cut (T601–T603)

Five platforms, five independent `pass` rows for the full flow — consent, pick,
download, update, create, restart, revoke, reconnect, migrate. No `not-run`
waiver and no cross-qualification between hosts. Windows and Linux GUI runs are
mandatory here even though they were not Gate 0 targets. The release is atomic:
all five ship together, with the new clients, and the legacy clients are cut at
the same time.

## Rollout sequencing

- The narrow scope, the Picker and the new clients ship in one release.
- Never release a build with the Picker and the old scope, or the new scope and
  the list UI.
- Backout is disabling Drive temporarily. Never restore `auth/drive`, never
  re-enable a legacy client, never mutate vault bytes to downgrade.
- `keyvault-privacy` stays online until the new URL is live and the store listing
  is approved, then is archived — never deleted during the transition.

## Deferred implementation plan

Shared Drives, a backend or token proxy, Google verification for a restricted
scope, and a provider-neutral picker abstraction for a second provider are out of
scope and are not scaffolded now. The second-provider picker belongs to spec 010's
deferred provider phase and requires a new plan revision there.
