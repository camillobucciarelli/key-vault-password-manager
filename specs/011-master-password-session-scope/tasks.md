# 011 — Tasks

Implementation landed on `main` in three reviewable slices, in the order the
spec's risk table requires: transport swap first, gating second, migration
third. The boxes below record what is actually merged; the open boxes are the
per-platform manual verification the Definition of Done still requires.

Manual steps are **not duplicated here**. They live in
[`docs/manual-qa.md`](../../docs/manual-qa.md), which replaced the per-spec
prose in PR #118. Each open task below names the session to run and the items
inside it that belong to this spec; run the session, then record the outcome in
the status table of that file — that table, not this one, is where a `passed` /
`failed` / `not-run` result is written.

## Slice 1 — session secret holder (PR #74)

- [x] T001 FR-1: introduce a coordinator-owned in-memory session secret holder
      and make `VaultBloc` read the master password from it instead of
      `SecureDataSource` at `InitializeVault`.
- [x] T002 FR-2: populate the holder on successful unlock and clear it on lock,
      on database switch, on unlock failure, and on `AppLifecycleState.detached`
      (previously a bare `break` with no cleanup).
- [x] T003 FR-2: remove the silent `?? ''` fallback so an absent session secret
      raises the existing locked-state error instead of attempting an empty
      password.
- [x] T004 Slice 1 invariant: every keystore write and biometric-path read is
      left byte-for-byte unchanged, so the slice is a pure transport swap.

## Slice 2 — keystore gating and per-database keys (PR #76)

- [x] T005 FR-3: gate all five write sites on `biometricProtectionEnabled`,
      resolved from the target database's `DatabaseSecurityProfile` and never
      assumed.
- [x] T006 FR-4: derive the keystore key from the database id
      (`MASTER_PASSWORD.<databaseId>`); a biometric unlock reads only its own
      entry. The legacy global constant stays defined but inert, reserved for
      the FR-6 migration.
- [x] T007 FR-5: erase the stored credential in the same operation that
      disables biometric protection, unregisters a database, or replaces its
      content.
- [x] T008 FR-7: deserialise an absent `biometricProtectionEnabled` flag to
      `false`, and default implicit profile creation to `false`.
- [x] T009 Import-commit rollback no longer touches the keystore; the
      transaction restores only the in-memory session secret.

## Slice 3 — migration and privacy policy (PR #78)

- [x] T010 FR-6: delete the legacy global `'MASTER_PASSWORD'` entry
      unconditionally at startup, awaited inside `di.init()` before any widget
      is built. The value is never copied to a per-database entry because it
      cannot be attributed to a database.
- [x] T011 FR-8: verify the Apple credential provider extensions and the
      desktop native messaging host against FR-1..FR-5. Neither reads any
      `MASTER_PASSWORD*` entry, so both are unaffected.
- [x] T012 FR-9: restore the strict `PRIVACY.md` claim in the same change that
      makes it true.

## Automated test plan

- [x] T013 Coordinator tests for the FR-3 gate at each write site, in both flag
      states — the invariant that had no coverage at all before this spec.
- [x] T014 Coordinator test for FR-5: disabling biometrics erases.
- [x] T015 Coordinator tests for FR-2: the session secret is cleared on lock, on
      database switch and on `detached`, and a vault operation after clearing
      raises the locked error instead of using an empty password.
- [x] T016 Migration tests for FR-6: the legacy entry is deleted on first run,
      the second run is a no-op, per-database entries are untouched, plus a
      `di.init()` wiring test that fails if the startup call is removed.
- [x] T017 Repository test for FR-7: an absent flag deserialises to `false`.
- [x] T018 `VaultBloc` tests updated for the FR-1 source change, including the
      case where the session secret is absent.

## Manual per-platform verification (outstanding)

Gates the Definition of Done. Host evidence never qualifies another platform,
and `not-run` is recorded as `not-run`, never upgraded by reasoning.

- [ ] T019 Android — run `docs/manual-qa.md` session **S1**, items S1-1..S1-5
      (AC-1, AC-2, AC-3, AC-5, AC-6), and record each outcome in that file.
- [ ] T020 iOS — run session **S2**, items S2-1..S2-6 (AC-2, AC-3, AC-5, AC-6
      and the FR-8 Apple autofill smoke). S2-1 and S2-2 are marked BLOCKED
      there: keychain inspection is unavailable on a physical device, so they
      are recorded `not-run` with the reason, not assumed passing.
- [ ] T021 macOS — run session **S3**, items S3-1..S3-5 (AC-1, AC-2, AC-5, AC-6
      and the FR-8 desktop browser autofill smoke).
- [ ] T022 Windows — run session **S4**, item S4-1 (AC-1 / AC-2 against the
      Windows credential store).
- [ ] T023 Linux — run session **S5**, items S5-1..S5-3 (AC-1, AC-2 and the
      FR-8 desktop browser autofill smoke).
- [ ] T024 Close the spec: once T019..T023 are recorded, fill in the
      per-platform matrix in the Definition of Done, marking every uncovered
      platform explicitly `not-run`, and have `senior-tester` validate the
      keystore inspection steps.
