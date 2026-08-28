# 015 — Implementation plan

## Delivery strategy

Trust boundary first, UI last. `CreateDatabaseUseCase` learns to reject an
invalid credential set before any wizard control changes, and the coordinator
becomes transactional before the wizard is allowed to stay mounted across a
failure. That order matters: the wizard is only allowed to survive a failure once
a failure actually leaves nothing behind, otherwise "draft intact" means the user
retries on top of a half-created vault.

The spec's own phase order already encodes this and is kept. What this plan adds
is the concrete mutation list the rollback must invert, the exact places where an
optional password becomes a new hazard, and the two dependencies on spec 014 that
are load-bearing rather than merely sequential.

This plan changes creation, the wizard and the unlock fallback. It changes no
KDBX format, no safe writer, no `DatabasePathMutex` and no sync. There is no
migration (FR-15).

**Owner agent**: `senior-flutter-dev`
**Platform agents**: `senior-web-chrome-dev` (Phase 5 — the download-only web path
and the `dart:io` conditional boundary). `senior-tester` owns the induced-failure
matrix (T007) and the T023 manual Safari/Firefox pass. No native change is
expected on Android/iOS/macOS/Windows/Linux: FR-12's picker gate uses the existing
`BiometricDataSource` over `local_auth`, which is already wired.

## Constitution Check

Checked against `.specify/memory/constitution.md` v1.1.2. No gate is violated and
no complexity waiver is needed.

| Principle | Verdict | Evidence |
| --- | --- | --- |
| I — Secrets never leak into the shell | PASS | The password stays in ephemeral controllers and the typed `CreateDatabaseCredentials` result; FR-10 keeps the draft and every secret out of the BLoC. Generated key bytes are produced at submit and never persisted by an abandoned draft (FR-5). FR-11 and AC-6 forbid writing an empty string to the secure store — see the hazard below, which this plan fixes rather than inherits. On web, FR-14 persists nothing at all. |
| II — Clean architecture layering holds | PASS | Validation lands in the use case (the trust boundary), sequencing and rollback in `DatabaseSessionCoordinator`, event/state translation only in `DatabaseSelectionBloc`. No new BLoC and no new coordinator: `createNewDatabase` already lives in the right place and gains the compensations. |
| III — Design tokens | PASS | The rebuilt credentials step, the three-way key control, the inline generated-key warning and the web notice read from `AppColors`/`AppSpacing`/`AppRadii`/`AppMotion`. The step collapse removes a screen rather than adding hard-coded values. |
| IV — Pixel fidelity is testable | PASS | T015 replaces the three-step wizard goldens with the two-step inventory at 390×844 and 1024×768 in light and dark, per screen. The three key modes and the empty-vs-filled password states are covered by named widget assertions rather than a golden per combination, which the constitution permits when the spec names the omitted axes — done in T014. |
| V — Accessibility floor | PASS | The three-way key control is a radio-style exclusive group, not colour-coded state: each option carries its own label and semantics. The inert submit control states its reason (FR-2) rather than being silently dead. Contrast, 44×44 targets and focus rings asserted in T014. |
| VI — Copy preserved unless a spec marks a change | PASS | The wizard's copy changes are exactly what FR-1 to FR-14 authorize: the merged credentials step, the three key-mode labels, the inert-submit reason, the FR-13 backup warning and the FR-14 web notice. The snackbar `Choose the generated key file option to continue.` is deleted with the control it belonged to. Every literal outside the wizard stays byte-identical. |
| VII — Destructive operations ask first and back up | PASS | FR-9 is the principle applied: a failed creation deletes only what that attempt created and restores six stores. The user's selected key file is never deleted (T006), which is the one irreversible mistake available here. FR-13's permanent warning covers the generated-key loss case. |
| VIII — Ship the smallest thing | PASS | No new use case, no new coordinator, no new BLoC, no new dependency. The rollback reuses the `_commitStagedImport` shape already in the file rather than introducing a transaction abstraction. The picker gate reuses `BiometricDataSource`. |
| IX — Verification is local | PASS | T025 runs `flutter analyze` and the full `flutter test` including goldens before commit. `pubspec.yaml: version:` is untouched. |

### Phase 0 / Phase 1 artifacts

`research.md` is not generated: `spec.md` carries no `[NEEDS CLARIFICATION]`
marker and states "Open questions: none blocking". Every technology involved —
`kdbx`, `local_auth`, `file_picker`, `flutter_secure_storage` — is already a
direct dependency.

`data-model.md`, `contracts/` and `quickstart.md` are not generated. The
constitution requires `data-model.md` only for specs 008 and 009. The credential
matrix, the fallback matrix and the rollback store list are already normative
tables in `spec.md`; the validation procedure is its §Tests section plus T025.

## Load-bearing dependencies on spec 014

The spec calls 014 a prerequisite for the opaque key name. Reading the code, there
are **two** dependencies, and the second is not mentioned:

1. **Naming (stated).** The generated key file's on-disk name is 014 FR-3. T004
   here deletes the `'database.key'` literal
   (`create_database_usecase.dart:115`) and the relative
   `'database.key'` produced by `_pickGeneratedKeyFilePath`
   (`create_database_screen.dart:70-74`); 014 supplies what replaces it. 015 must
   not restate the naming rule.
2. **`cacheKeyFilePath` (unstated).**
   `DatabaseSessionCoordinator.createNewDatabase` ends with
   `await databaseSessionRepository.cacheKeyFilePath(created.keyFilePath)` —
   that is the global `cachedKeyFilePath` which **014 FR-8 / T014 deletes**. So
   the create path contains a call that 014 removes outright. If 015 lands first,
   it writes rollback compensation for a store that is about to disappear; if 014
   lands first, that line is already gone and FR-9's store list is one shorter.
   Sequencing 014 first, as the spec requires, is therefore not a preference —
   it avoids writing and then deleting a compensation. T001 verifies this
   explicitly, not just the naming task.

## Dependency and safety gates

1. 014 T001 and T004 have landed, and `cacheKeyFilePath` is gone from
   `createNewDatabase`, before any 015 production task starts (T001).
2. No migration and no special-casing of pre-existing databases (FR-15, T024).
   FR-12 is deliberately shared code so existing vaults get the same fallback
   matrix — that is not migration, and it must not become one.
3. `SafeVaultFileWriter`, `DatabasePathMutex` and the spec 008 writer inventory
   are untouched. Creation keeps routing through the existing writer.
4. The user's selected key file is never deleted on any path (T006). Rollback
   deletes only key material this attempt created.
5. Removing the `FLUTTER_TEST` shortcut (T003) will surface latent failures in
   tests that were passing over an unexecuted branch. Those are fixed, never
   re-skipped.

## The mutation list FR-9 must invert

`createNewDatabase` (`database_session_coordinator.dart:634-697`) mutates state in
this order. Enumerated here because FR-9's list is prose and the rollback must
match the code:

```text
1. createDatabaseUseCase(...)        -> writes the .kdbx, and the key file when generating
2. _applyImportedDatabase(...)       -> registry record + active database id
3. _saveSecurityProfile(...)         -> per-database security profile (keyFilePath, biometrics)
4. sessionSecretHolder.set(password) -> in-memory session secret
5. saveMasterPassword(id, password)  -> secure store, only when biometrics enabled
6. cacheKeyFilePath(...)             -> removed by 014 T014; no compensation is written for it
```

Sync metadata appears in FR-9's list but is not written by this path today; the
compensation is still asserted, as an invariant that no mapping was created, so
the test does not silently pass by omission.

The compensation is modelled on `_commitStagedImport`
(`database_session_coordinator.dart:454`), which already owns the restore-on-
failure shape for the import path — including the session-secret capture at
lines 526-527 (`originalSessionSecret`) that step 4 needs. Reuse that shape; do not introduce a generic
transaction abstraction for one call site.

## Two hazards that an optional password creates

Both are latent today and become reachable the moment FR-2 allows an empty
password. Neither is in the task list as written, and both belong to T016.

**Empty string into the secure store.** Step 5 above calls
`saveMasterPassword(record.databaseId, password)` whenever
`biometricProtectionEnabled` is true. With a key-file-only vault, `password` is
`''`, so an empty string is written to the keystore — exactly what AC-6 forbids.
FR-11 is the fix: biometric activation requires storable credentials and is
refused explicitly otherwise. The refusal must be a stated message, not a silent
no-op, and it must be decided before the vault is created, not after.

**Empty session secret.** Step 4 calls `sessionSecretHolder.set(password)`
unconditionally. For a key-only vault this seeds the spec 011 session secret with
`''`, which is not a secret and would make a later unlock comparison meaningless.
The session secret must not be set for a vault with no password; coordinate the
exact semantics with spec 011's session-scope rules rather than inventing them
here.

## Phase 0 — prerequisite (T001)

Boolean check against the tree, not against a status note: 014's managed root
helper exists, the opaque-name allocation exists, and
`rg -n 'cacheKeyFilePath' lib` returns nothing.

## Phase 1 — trust boundary (T002–T004)

### Change

- `lib/features/password_manager/domain/usecases/create_database_usecase.dart`
  - **T002** — reject a request with no factor (empty password *and* no key
    file), and reject a key file that is missing, unreadable or empty. Today
    `call` composes `Credentials.composite(ProtectedValue.fromString(request.password), keyFileBytes)`
    with both empty (lines 74-77) and produces a vault openable by anyone.
    Rejection is a typed failure, not an exception string the UI parses.
  - **T003** — delete the `if (!Platform.environment.containsKey('FLUTTER_TEST'))`
    guard (lines 63-65) so `_prepareKeyFilePath` runs under test. This is also
    the `dart:io` read that makes web creation fail at runtime, so removing it is
    a prerequisite for Phase 5, not only a test-coverage fix.
  - **T004** — delete the `'database.key'` fallback (line 115); the name comes
    from 014.
- `lib/features/password_manager/presentation/screens/create_database_screen.dart:70-74`
  — `_pickGeneratedKeyFilePath` and its literal relative `'database.key'` are
  deleted with the button they served.

Gate: use-case unit tests cover the full credential matrix and each key-file
rejection, with no UI involved (AC-2).

## Phase 2 — transactional creation (T005–T007)

### Change

- `lib/features/password_manager/presentation/coordinators/database_session_coordinator.dart`
  — `createNewDatabase` wraps steps 1-5 above and compensates each on failure, in
  reverse order, restoring the prior active database and credentials rather than
  clearing them.

Gate: T007 induces a failure at each of the five stages and asserts no `.kdbx`,
no generated key, no registry record, no changed active id, no security profile,
no secure-store entry and no sync mapping remains — and that the user's selected
key file still exists (AC-3, T006).

## Phase 3 — wizard (T008–T015)

### Change

- `lib/features/password_manager/domain/models/create_database_step.dart` — the
  enum drops `optionalLocks`; the doc comments saying "of 3" become "of 2".
- `database_session_coordinator.dart` — `resolveCreateDatabaseStepAdvance` and
  `resolveCreateDatabaseStepBack` lose their third arm. They are pure decisions
  with no I/O, which is why the step machine stays here.
- `create_database_screen.dart` — `_LocksStep` (line 507) merges into the
  credentials step; `_advance`'s `masterPassword` arm (lines 117-129) becomes the
  submit arm; `_submit` (lines 143-164) stops calling
  `Navigator.of(context).pop(...)` before creation runs.
- `create_database_screen.dart:347-356` — `_NameStepState._validate` stops being
  advisory: an invalid character blocks advancing (T011, AC-5). The reliance on
  `MobileFileStorage._normalizeFileName` (`mobile_file_storage.dart:294-299`)
  silently rewriting the name to `_` ends here; that normaliser stays as a last
  line of defence but is no longer the primary rule.

### The mounted-wizard change is the structural one

Today the screen pops with a `CreateDatabaseCredentials` result and creation runs
after it is gone, which is why a failure loses the draft and contradicts
`specs/003-database-and-unlock/spec.md:113-115`. T012 inverts this: the screen
stays mounted, dispatches creation, disables its controls and Back/Cancel while
it runs, and pops only on success. The BLoC carries neither the draft nor the
secret — it carries a "creating" flag and a failure message.

Gate: T014 widget tests cover the three key modes, optional password with and
without confirmation, the blocked invalid name, and a failure that keeps the
wizard open (AC-4). T015 replaces the wizard goldens.

## Phase 4 — biometrics and unlock fallback (T016–T019)

- **T016** implements FR-11 and fixes both hazards above: no empty string to the
  secure store, no empty session secret, and an explicit refusal when biometric
  activation is asked for without storable credentials.
- **T017** implements the FR-12 matrix in shared unlock code so existing
  databases get it too.
- **T018** gates the internal managed-key picker behind the existing
  `BiometricDataSource` (`lib/features/password_manager/data/datasources/biometric_data_source.dart`,
  already the only `local_auth` call site), with system PIN/passcode fallback.
  Default: only the key bound to that database. Listing every managed key
  requires the same authentication. Without the gate, biometric protection on a
  key-only vault is cosmetic — the managed key is already on the device.

Gate: T019 covers the full matrix and the gate (AC-7).

## Phase 5 — web (T020–T023)

`dart:io` is the blocker and it is reached from more than one place: the
`Platform.environment` read removed in T003, and the storage root via
`path_provider`. The web path therefore needs a conditional boundary rather than
runtime branching inside shared code — one `kIsWeb`-selected implementation of
the creation path, so no web build compiles a `dart:io` import.

Requirements that follow from FR-14:

- no biometric step (`local_auth` has no web support);
- a selected key file is read with `withData: true`, because `FilePicker.saveFile`
  cannot write without bytes on web;
- generated key bytes are produced **once** and held in memory, so a retry after a
  failed download reuses the same key — regenerating would hand the user a key
  that does not open the database they already downloaded;
- `KdbxFormat.dartWebWorkaround = true` is set at the web boundary, for dart2js
  `Uint64` behaviour;
- two explicit gestures, key download before database download; creation stays
  blocked until the key download has been requested;
- nothing persisted: no registry entry, no opened vault, no credential. The app
  returns to database selection, with the inline notice that reloading loses the
  draft and the key.

Gate: T022 asserts the two artefacts are mutually consistent and nothing is
persisted, without a real browser (AC-8). T023 is a manual Safari/Firefox pass
before any web release; Chrome is the automated gate.

## Phase 6 — closing checks (T024–T025)

### Targeted commands

```bash
dart format lib test
flutter analyze
flutter test test/features/password_manager/domain/usecases/create_database_usecase_test.dart
flutter test test/features/password_manager/presentation/coordinators
flutter test test/features/password_manager/presentation/screens/create_database_screen_test.dart  # new, T014
flutter test test/features/password_manager/presentation/screens/database_selection_unlock_widget_matrix_test.dart
flutter test test/goldens/database_and_unlock_test.dart
flutter test
```

### Guard searches

```bash
rg -n "'database\.key'|database\.key" lib
rg -n 'FLUTTER_TEST' lib
rg -n 'optionalLocks' lib test
rg -n 'cacheKeyFilePath' lib
rg -n "dart:io" lib/features/password_manager/domain/usecases lib/features/password_manager/presentation/screens/create_database_screen.dart
```

Expected: all five return nothing in production paths. The fourth is 014's
guarantee, re-asserted here because 015's create path was its last caller.

T024 asserts, as an absence, that no migration path and no special-casing of
existing databases was added.

## Rollout sequencing

- 014 first, then 015. Not a preference — see *Load-bearing dependencies*.
- Within 015, ship as one change: a build with an optional password but without
  the FR-11 refusal writes empty strings to the keystore, and a build with a
  mounted wizard but without the rollback lets the user retry onto a half-created
  vault.
- The web path may ship separately from the native path if needed; it persists
  nothing, so it carries no state to roll back. It must not ship before Phase 1,
  which is what removes its `dart:io` blocker.

## Deferred implementation plan

Key-file export and backup UX stay out of scope — FR-13 is a warning, not a
feature. No new credential factor (hardware token, passkey). No migration for
databases created before this spec, in any form.
