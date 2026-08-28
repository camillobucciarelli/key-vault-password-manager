---
name: manual-qa-harnesses
description: Run the repository's manual, on-demand QA harnesses — the spec 008 T111 safe-writer platform harness, the spec 011 master-password keystore probe (including the iOS runner workaround), and the iOS container-relocation harness. Use when running, debugging, or changing any integration_test/ harness, tool/run_safety_harness.sh, tool/run_ios_keystore_qa.sh, safety-evidence artifacts, or persisted-path/keystore code that these harnesses cover.
---

# Manual QA harnesses

These three harnesses are run by hand, never by CI. Each section is the full
procedure plus the invariants that must not be broken.

### spec 008 T111 safe-writer platform harness

`tool/safe_vault_writer_harness.dart` holds the eight fault/collision cases spec
008 Gate 0 requires of every platform artifact. They run in two places on
purpose: `test/tool/safe_vault_writer_harness_test.dart` executes them on the CI
host on every PR, and `integration_test/safe_vault_writer_harness_test.dart`
executes the *same* code on a device. The device contributes hardware, not
logic.

```bash
tool/run_safety_harness.sh -d <device-id> -p android   # on a device
tool/run_safety_harness.sh -H                          # on this host
```

The runner stamps provenance the device cannot know, then
`tool/file_safety_evidence.dart` validates the artifact against
`tool/safety_evidence_schema.dart` — the same schema
`safe_vault_file_writer_harness_schema_test.dart` pins — and writes
`build/safety-evidence/<platform>/`. Exit 0 = passed, **2 = a filed `failed`
artifact** (a real finding), 1 = nothing could be filed. Linux and Windows
artifacts are produced in CI by the `t111-platform-artifact` job, because on
those two targets the runner is the platform.

Do not add a second copy of the schema anywhere. After a real run, the Gate 0
assertion `no platform artifact exists yet` will fail until
`specs/008-per-field-conflict-resolution/feasibility-report.md` is updated —
that tripwire is deliberate.

### spec 011 keystore probe (manual, on-demand)

`integration_test/master_password_keystore_qa_test.dart` answers "is there a
master-password entry for this database?" on all five platforms, including iOS,
where no keychain dump exists. Four phases via `--dart-define=QA_PHASE=`:
`ac2_unlock`, `ac2_relaunch`, `ac6_seed`, `ac6_upgrade`.

On physical iOS, never run phase pairs as separate default `flutter test`
commands: Flutter 3.44.8 stops and then uninstalls the test app after each run.
iOS preserves Keychain entries across that uninstall but deletes the app
container, including the fixture vault and registry. Use one runner command:

```bash
tool/run_ios_keystore_qa.sh -d <device-id> -s all
```

Save work and quit Xcode before starting; the runner fails without touching an
already-open Xcode session. Flutter may open Xcode while launching each phase.
The runner then asks Xcode to quit gracefully and waits for it to close between
phases and before returning. A quit error or timeout fails the run. This is the
workaround for consecutive-run failures on Xcode 26 tracked in
flutter/flutter#144218 and flutter/flutter#186455. Do not start a following
T111 run after a quit failure until Xcode has been closed manually.

`-s ac2` and `-s ac6` run one pair only. The runner passes `--no-uninstall` to
retain the container; Flutter still calls `stopApp`, so phase 2 is a new process.
A non-secret marker makes phase 2 fail unless its PID differs and its random
`databaseId` matches phase 1. This proves the same vault identity, not a newly
created equivalent vault.

It reports **presence only, never a value**, and it must stay in
`integration_test/` — that is what keeps it off the release surface without a
build flavor. `test/tool/keystore_probe_guard_test.dart` enforces this on every
PR: no `String` reporter, no `getMasterPassword` call, no reference from `lib/`.
Do not "promote" it into a debug screen.

Its readings are tri-state; an unreadable keystore is `indeterminate` and fails
loudly. Never collapse that to `false` — macOS really does refuse
(`errSecInteractionNotAllowed`), and a silent `false` would be a confident wrong
pass on an item whose whole purpose is proving absence.

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

