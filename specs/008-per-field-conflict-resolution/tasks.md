# 008 — Tasks

Ordered gates. Later phase cannot start until prior gate exit passes.

## Phase 0 — Feasibility and report (blocking)

> **Gate 0 executed 2026-08-13 on `feat/008-merge-gate0`, corrected after
> independent review 2026-08-14 — verdict NO-GO.**
> T001–T004 and T006–T008 pass; **T005 is partial**. **One** blocker keeps the
> feature disabled and forbids T201/domain freeze:
> **B1** server-enforced Drive conditional upload is unproven — the Drive REST
> v3 `files.update` reference documents no precondition and the v3 `File`
> resource has no `etag`. The transport is not the obstacle: Drive is called via
> a raw `http.Client`, so `If-Match` can be sent; it never has been, and only a
> live-network spike can settle it.
> Previously listed as B2 (entry colors) and R2 (entry auto-type): **both
> closed**. Their values round-trip through the exported `KdbxNode.node`.
> Full evidence: `specs/008-per-field-conflict-resolution/feasibility-report.md`,
> section "Post-review corrections".

- [x] **T001 KDBX semantic matrix** — generated KDBX 3/4 cases covering every
      installed-library-supported fidelity category: hierarchy/moves, recycle
      bin/tombstones, history, protected custom fields, exact attachment bytes/
      protection, custom data/icons, metadata/settings and header/KDF settings.
- [x] **T002 Credential round-trip** — password-only and password+key-file
      save/reopen semantic parity; no byte-equality criterion.
- [x] **T003 Adapter mutation spike** — import one-sided record/group/custom field/
      attachment and choose one real conflict without changing unrelated manifest.
- [x] **T004 Tombstone/lineage spike** — inspect/re-emit deletion evidence and
      compare root UUID before diff. Spike pre-diff rejection for duplicate entry,
      duplicate group, group-entry collision, nil live UUID and cross-side kind
      mismatch. Prove no call to unfinished `KdbxFile.merge`.
- [~] **T005 Drive conditional spike** — PARTIAL. HTTP-rejection vs
      timeout-after-dispatch classification proven against a fake transport;
      server-enforced token NOT proven (blocker B1, needs live-network spike).
- [x] **T006 Filesystem harness spike** — define portable failure/interruption
      harness and artifact schema for backup/flush/replace semantics.
- [x] **T007 Writer/path discovery** — scan current feature for `File.write*`,
      `rename`, `copy`, `delete`, staged commits and service mutations; reconcile
      every result with plan inventory.
- [x] **T008 Gate report** — populate
      `specs/008-per-field-conflict-resolution/feasibility-report.md` with KDBX
      support matrix, unsupported detector, Drive token/outcome rules, complete
      writer inventory, path identity design, artifact schema and per-platform
      `not-run|passed|failed|disabled` status/feature flags. Gate 0 may leave target
      artifacts `not-run` and disabled; Gate 1 produces evidence.

**Gate 0 exit**: **T001–T008** pass. **NOT MET** — see banner above. T008 is mandatory before T201/domain freeze.
Unavailable conditional upload or fidelity gap blocks Gate 0. Platform evidence
may remain `not-run` only with target disabled; Gate 1 T111 must pass before that
target enables.

```bash
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart --plain-name "merge feasibility"
flutter test test/features/password_manager/data/services/google_drive_api_service_test.dart --plain-name "conditional update"
flutter test test/features/password_manager/data/services/database_writer_inventory_test.dart --plain-name "inventory baseline"
flutter test test/features/password_manager/data/services/safe_vault_file_writer_harness_schema_test.dart
```

## Phase 1 — All-writer serialization and filesystem safety

- [ ] **T101 Freeze writer inventory before mutex** — verify current paths:
      `VaultKdbxService` all mutations + credential transaction;
      `DatabaseSyncOrchestrator.syncNow/_backupFile`;
      `DatabaseImportService` import/stage/commit/finalize/rollback/move/replace/
      create; `DatabaseSessionCoordinator` create/import/replace/delete;
      `VaultSessionCoordinator.updateDatabaseSettings` settings/credential/
      rename/rollback; database exports in `database_selection_screen.dart` and
      `vault_navigation.part.dart`.
- [ ] **T102 Remove presentation database file writes** — export/copy/delete/
      rename operations use domain ports with data implementations. Architecture
      test rejects new presentation `dart:io` database mutation.
- [ ] **T103 `database_path_identity_resolver.dart`** — normalize absolute/
      relative, separators, `.`/`..`, existing symlinks, nonexistent target
      parent, platform case rules and hard-link/file identity. Use global database
      lock fallback where alias identity cannot be proven.
- [ ] **T104 `database_path_mutex.dart`** — singleton shared by every T101 writer,
      manual/auto sync and merge. Deduplicate/sort multi-path identities before
      acquisition; independent databases concurrent only when proven distinct.
- [ ] **T105 Route all writers** — patch `VaultKdbxService`, import service,
      orchestrator, database/session settings flows and exports. No bypass.
- [ ] **T106 Rename transaction** — lock old+new canonical paths in deterministic
      order through rename, registry/security/sync mapping updates and rollback.
- [ ] **T107 Alias/deadlock tests** — relative/absolute, separators, `.`/`..`,
      symlink path/parent, case aliases on relevant filesystem, hard links where
      supported, missing target, source==target and inverse concurrent renames.
- [ ] **T108 Collision-safe backup** — exclusive-create temp/final; microsecond
      timestamp + random/counter suffix; no overwrite. Test frozen same timestamp,
      preexisting backup, repeated collision and content preservation.
- [ ] **T109 Safe target writer** — same-directory temp, flush/fsync/close, verified
      backup before target write, atomic replace without delete-first, directory
      sync where supported.
- [ ] **T110 Failure tests** — backup create/write/flush/verify, disk-full/short
      write, target flush, rename and cleanup failures leave old/full new target.
- [ ] **T111 Platform harness artifacts** — run target harness separately on
      Android, iOS, macOS, Windows and Linux. Feature flag defaults disabled until
      matching artifact passes; macOS host test qualifies macOS only. Update each
      `feasibility-report.md` row with result/artifact metadata.

**Gate 1 exit**: writer audit has no bypass, alias/rename tests pass, backups never
overwrite, and enabled platform has its own artifact.

## Phase 2 — Compile-safe domain contract

- [ ] **T201 Freeze `data-model.md`** from T008 report.
- [ ] **T202 Safe domain models** — `MergeReviewSummary`, opaque session/decision
      IDs, redacted categories/choices/counts, typed commit/recovery outcomes and
      `staleRecoveryLocal`. No path, UUID, checksum/token, plaintext or plaintext
      handles in Equatable/serialization.
- [ ] **T203 `MergeFieldDisplay`** — transient non-Equatable/non-serializable
      response with redacted `toString`; only field widget may own it.
- [ ] **T204 `domain/repositories/sync_merge_repository.dart`** — compile against
      T202/T203 models; opaque/redacted port for start, update decision, commit,
      cancel, invalidate, recover pending and transient load-field-display.
- [ ] **T205 Focused domain use cases** under `domain/usecases/` for every T204
      operation. No data imports.
- [ ] **T206 Domain policy/tests** — visible defaults, deterministic notes both,
      shortcut decision set excludes one-sided rows, missing side cannot be
      selected, safe `props`/`toString`; `flutter analyze` and domain tests compile
      without any data implementation.

**Gate 2 exit**: domain models, port, use cases and tests compile/pass standalone.
No `SyncMergeRepositoryImpl` or DI task starts before exit.

## Phase 3 — Data-owned full-fidelity implementation and DI

- [ ] **T301 `data/services/kdbx_merge_adapter.dart`** — production
      full-fidelity open/import/apply/serialize/reopen/manifest validation based on
      private T003 spike; no `VaultSnapshot` write model, no `KdbxFile.merge`.
- [ ] **T302 `data/repositories/sync_merge_repository_impl.dart`** — implement
      already-compiling T204 port; resolve credentials internally and own private
      session store with `KdbxFile`, plaintext, UUID maps, paths, checksums/tokens
      and generation.
- [ ] **T303 Secret boundary** — port returns only domain models. Password,
      key-file path/bytes, KDBX types, plaintext store and preconditions never
      cross port. Dispose store on cancel/lock/invalidate/completion.
- [ ] **T304 Pre-diff UUID validation** — per side, require globally unique non-nil
      live root/group/entry UUIDs. Reject duplicate entry, duplicate group,
      group-entry collision, nil UUID and cross-side object-kind mismatch as
      `unsupportedKdbxData` before session/write/upload.
- [ ] **T305 Lineage/unsupported guards** — wrong root UUID and other unsupported
      data fail before review/backup/write/upload.
- [ ] **T306 Field presence diff** — explicit present/missing model; empty string
      and zero-byte attachment remain present. Missing without explicit marker is
      automatic union.
- [ ] **T307 Presence/UUID tests** — all T304 failures plus same entry UUID with
      local-only/remote-only custom fields and attachments, empty-vs-missing,
      zero-byte-vs-missing, protection flags and equal-name/different bytes.
- [ ] **T308 Shortcut/deletion tests** — Prefer local/remote never choose missing/
      null; all one-sided data survives; deletion requires explicit evidence and
      keep/delete choice; no ambiguous resurrection.
- [ ] **T309 Password+key-file candidate reopen** — semantic manifest matches
      expected result and unrelated metadata/history/icons/settings survive.
- [ ] **T310 DI after contract+implementation compile** — bind T302 in data DI and
      T205 use cases in domain DI; no presentation dependency on data
      implementation. Run analyze after registrations.

**Gate 3 exit**: implementation compiles against domain contract; fidelity,
UUID/lineage, presence, deletion, shortcut, secret boundary and DI tests pass.

## Phase 4 — Preconditions, commit and remote recovery

- [ ] **T401 Drive model/API** — add Gate 0-proven concurrency token and
      server-enforced conditional `updateFile`.
- [ ] **T402 Local/remote staleness** — recompute local checksum and refetch remote
      checksum/token under path mutex immediately before backup; stale side causes
      zero write.
- [ ] **T403 Atomic commit integration** — candidate semantic validation, verified
      collision-safe backup, target temp/replace and mapping transaction.
- [ ] **T404 Persist `_PendingMergeUpload` before dispatch** — merged/local
      checksums, expected old remote checksum/token, Drive ID, private backup/path,
      no plaintext/credentials.
- [ ] **T405 Definite outcomes** — conditional rejection means not applied;
      successful response refetches merged checksum before finalizing mapping.
- [ ] **T406 Ambiguous transport outcome** — timeout/disconnect after dispatch
      persists `outcomeAmbiguous`; do not retry blindly or mark synced/failed.
- [ ] **T407 Recovery local guard** — under per-database mutex, hash current local
      bytes and compare persisted `localCommittedChecksum` before remote client
      call or any vault mutation. Mismatch -> `staleRecoveryLocal`; no upload,
      retry, finalization or success mapping update; retain backup/evidence and
      require fresh conflict.
- [ ] **T408 Matching-local remote triage** — only after T407 match, refetch:
      merged checksum -> finalize; unchanged old checksum+token -> conditional
      retry; third state -> new conflict while retaining local+backup.
- [ ] **T409 Restart recovery tests** — recreate process/data repository with
      pending record. Cover local mismatch first and assert zero remote calls/
      mutation, then matching-local applied/not-applied/third-state branches before
      normal auto-sync.
- [ ] **T410 Upload tests** — conditional reject, success, timeout-applied,
      timeout-not-applied, timeout-third-state, retry timeout and verification
      failure. Mapping never claims synced prematurely.
- [ ] **T411 Upload-failure reopen** — local merged file and dated backup remain;
      reopen with password+key file succeeds.

**Gate 4 exit**: stale, backup, atomicity, definite/ambiguous upload and restart
recovery tests pass.

## Phase 5 — Coordinator, BLoC, lock and auto-sync

- [ ] **T501 `presentation/coordinators/sync_merge_coordinator.dart`** — depend on
      domain command use cases only; hold opaque session ID, redacted decisions
      and sequencing. No data imports, credential resolution, plaintext,
      plaintext handles, KDBX/private store, paths/checksums/tokens/UUIDs.
- [ ] **T502 Coordinator tests** — enforce import/dependency boundary and verify
      sequencing for review/update/commit/cancel/recovery using fake use cases.
- [ ] **T503 Field widget boundary** — widget invokes
      `LoadSyncMergeFieldDisplayUseCase` directly; result never traverses
      coordinator/BLoC/state and clears on dispose/lock.
- [ ] **T504 `vault_event.dart`/`vault_state.dart`** — opaque IDs, redacted
      decisions/counts/phases/outcome codes only.
- [ ] **T505 `vault_bloc.dart`** — forward command events to coordinator; no
      download/open/diff/write/upload workflow.
- [ ] **T506 Lock/session integration** — invalidate use case before credentials
      clear; data implementation aborts pre-boundary or completes durable recovery
      bookkeeping post-boundary. Database switch invalidates late callbacks.
- [ ] **T507 Auto-sync interaction** — pending upload recovery runs before normal
      auto-sync; conflicts remain persistent status, never modal while editing.
- [ ] **T508 Secret tests** — known password, key path/bytes, protected custom
      value, attachment bytes and field display absent from coordinator, events,
      state, props, serialization and logs.
- [ ] **T509 Concurrency tests** — edit/save/manual sync/auto-sync/merge/rename and
      restart recovery serialize through shared path mutex. Restart local-check
      executes before remote client call or mutation.

**Gate 5 exit**: clean boundary, redaction, lock and background-sync tests pass.

## Phase 6 — UI and exact golden inventory

- [ ] **T601 Wire vault parts** only after Gates 0–5 green.
- [ ] **T602 Review** — automatic record/field union sections, real conflicts,
      deletion evidence, **Prefer local/Prefer remote**, “unique data preserved”,
      “nothing written yet”.
- [ ] **T603 Field diff** — widget-local transient display, protected masked,
      present/missing labels non-selectable for one-sided data, explicit deletion
      choice only with evidence.
- [ ] **T604 Ready/progress/recovery** — safety gates listed; cancellation hidden
      after atomic boundary; ambiguous upload has recovery status, never success.
- [ ] **T605 Scale** — generate 250 conflicts in memory, shortcuts-only. Binary
      fixture only if Gate 0 proves format-specific need.
- [ ] **T606 Golden case table** — exactly 12 entries and exact filenames/states/
      dimensions/themes from `spec.md`; test asserts `cases.length == 12` before
      executing all cases.
- [ ] **T607 Layout/semantics matrix** — implement all 12 exact test names from
      `spec.md`: review/field/ready × 390×844/1024×768 × light/dark. Assert matrix
      length 12, unique names, no `tester.takeException()`/overflow and required
      semantic roles for every row.
- [ ] **T608 Named dynamic widget assertions** —
      `merge progress hides cancel after atomic boundary`;
      `field plaintext is absent after widget dispose and lock`;
      `background conflict remains status and opens no modal`;
      `Prefer local and Prefer remote never remove one-sided rows`.

**Gate 6 exit**: all 12 goldens, 12 exact layout/semantics rows and four dynamic
named widget assertions pass.

## Phase 7 — Final verification

- [ ] **T701** Format focused Dart changes and run `flutter analyze`.
- [ ] **T702** Run focused tests below; full `flutter test` before release only.
- [ ] **T703** Run/attach each shipped platform harness artifact; keep failed or
      missing platform feature-disabled.
- [ ] **T704** Manual two-client pass: one-sided records/fields/attachments,
      deletion evidence, stale sides, backup/disk failures, rename aliases,
      edit/auto-sync/lock boundary, all upload outcomes, restart recovery and
      password+key-file reopen.

```bash
dart format lib/features/password_manager test/features/password_manager integration_test
flutter analyze
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart --plain-name "merge feasibility"
flutter test test/features/password_manager/data/services/database_writer_inventory_test.dart
flutter test test/features/password_manager/data/services/database_path_mutex_test.dart
flutter test test/features/password_manager/data/services/safe_vault_file_writer_test.dart
flutter test test/features/password_manager/domain/usecases/sync_merge_usecases_test.dart
flutter test test/features/password_manager/data/repositories/sync_merge_repository_impl_test.dart
flutter test test/features/password_manager/data/services/database_sync_orchestrator_test.dart
flutter test test/features/password_manager/presentation/coordinators/sync_merge_coordinator_test.dart
flutter test test/features/password_manager/presentation/bloc/vault_redaction_test.dart
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
flutter test test/goldens --plain-name "sync merge golden inventory"
flutter test test/features/password_manager/presentation/widgets/sync_merge_dynamic_test.dart
flutter test integration_test/safe_vault_file_writer_test.dart -d <target-device>
```
