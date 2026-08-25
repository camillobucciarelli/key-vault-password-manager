# 008 — Tasks

Ordered gates. Later phase cannot start until prior gate exit passes.

## Phase 0 — Feasibility and report (blocking)

> **Gate 0 is CLOSED (2026-08-21). T201 and the domain freeze are unblocked.**
> T009 passed with executable evidence — 36 tests green and the mutation check
> at exit 0 (PR #65), re-verified on `main` and accepted by the PM on
> 2026-08-21. **T009b remains a separate open gate**: it blocks only
> deletion/tombstone/attachment work, not Gate 0.
>
> History: executed 2026-08-13 on `feat/008-merge-gate0`; corrected after
> independent review 2026-08-14; **B1 closed by live-network measurement
> 2026-08-15**; Gate 0 declared closed the same day and **that close was
> reverted by independent review 2026-08-15**.
>
> **B1 is settled and is no longer a blocker.** Google Drive REST v3 enforces no
> precondition on the upload path — measured live, six decisive probes and six
> counter-probes. Spec 008 FR-7 was rewritten around a storage-agnostic
> `get` + `put` write-verify-converge cycle that needs no server precondition.
>
> **What blocked Gate 0 until 2026-08-21 was that the replacement cycle was
> validated by nothing.** The 2026-08-15 close rewrote the Gate 0 exit criterion in the same
> commit that declared it met, and the cycle it substituted for B1 is `not-run`.
> Reading it found three defects that each prevented convergence — no
> re-anchoring of the expected base on retry, a byte comparison with no semantic
> arbiter, and a perspective-dependent tie-break — plus four correctness and
> safety defects. All are corrected in `spec.md`; none was caught by a test.
>
> **Gate 0 closes when T009 passes, and on no other condition.** It did, on
> 2026-08-21.
>
> Previously listed as B2 (entry colors) and R2 (entry auto-type): **both
> closed**. Their values round-trip through the exported `KdbxNode.node`.
> Full evidence: `specs/008-per-field-conflict-resolution/feasibility-report.md`,
> sections "Convergence-cycle review (2026-08-15)" and "Post-review corrections".

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
- [x] **T005 Drive concurrency-capability measurement** — DONE, negative result.
      HTTP-rejection vs timeout-after-dispatch classification proven against a
      fake transport; **server-enforced conditional write measured ABSENT**
      against live Drive (`tool/drive_conditional_spike.dart`, 2026-08-15). B1 is
      `failed` and closed. A negative measurement is a valid outcome: FR-7 now
      requires only `get` + `put`, so the capability's absence lowers the
      guarantee tier instead of blocking the feature.
      **Drive `versionHistory` is NOT covered by this task** and is declared
      absent — it was briefly recorded present from documentation alone, which
      spec 010's own rules forbid. Measuring it is a spec 010 FR-5 spike.
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
- [x] **T009 Convergence model validation** — **passed 2026-08-21** (PR #65:
      36 tests green; `node tool/mutation_runner.mjs
      --definitions=tool/mutations/008_t009_convergence.json --check` exit 0,
      0 survivors; re-verified on `main` by the PM the same day). Was the
      remaining Gate 0 blocker.
      Validate the FR-7 write-verify-converge cycle as a **model**, in memory:
      no network, no filesystem, no KDBX, no `lib/` dependency. Simulate
      devices against a shared bare `get`/`put` remote and assert the properties
      below. The enumeration is **2 injection points across 2 concurrent
      writers**, plus **sequential scenarios at 3 and 4 devices** covering every
      ordering and association of the merge; interleaved concurrency at three or
      more writers is not enumerated. State the enumeration, never "every
      interleaving" — the previous 2-device-only enumeration is what hid N1.
      1. convergence to a stable state within the declared retry budget of 3;
      2. no record and no one-sided field lost, at both injection points and
         across all six 3-device sync orders — including the honest case where a
         write inside the race window IS clobbered and is recovered only when
         that device resyncs, and a device that rejoins late;
      3. no oscillation on a timestamp tie; mirrored perspectives pick the same
         winner, and two devices that each **retain** their own candidate stop
         the remote moving across sessions;
      4. a semantically complete union terminates instead of ping-ponging on
         byte difference alone, including against a peer that keeps rewriting;
      5. explicit user decisions survive a re-merge — over two consecutive
         rounds — and a never-seen conflict reopens review instead of
         auto-resolving;
      6. a non-executable step-5 read-back is classified ambiguous, never
         finalized, on the first read-back and on a later one;
      7. the merge is associative, commutative and idempotent at 3 and 4 sides,
         with known and unknown timestamps.
      Every correction must be **mutation-guarded**: reverting it in the model
      must kill at least one test that asserts an outcome, not only a counter.
      Record the mutation table in the feasibility report.
      **Scope limit — T009 says nothing about deletions.** The model expresses
      no tombstone, no `fieldDeletionConflict` (FR-4/FR-5) and no attachment, so
      the join-semilattice result is **no evidence** about the convergence of
      deletion. A grow-only union is also the wrong structure for it: it cannot
      remove an element, so a delete either fails to converge or is resurrected
      by the next peer that still holds the value. Convergent deletion needs
      removal evidence — a 2P-Set or a tombstone with a causal clock — proved
      over both operations. Tracked as **T009b**, below; T009 passing does not
      discharge it.
      Artifact:
      `test/features/password_manager/data/services/sync_merge_convergence_model_test.dart`.
      This task exists because C1, C2 and C4 were found by reading a document,
      and N1 by running the model at a device count the suite did not cover.
      Convergence must be **executable**, not argued in prose.
- [x] **T009b Deletion convergence model** — **a separate gate, not part of
      Gate 0.** Extend the convergence model to express deletion evidence and
      prove that the chosen structure converges over **both** add and remove:
      associative, commutative and idempotent, at 3 and 4 devices, mutation-
      guarded to the same standard as T009. Covers tombstones and record
      deletion (FR-5), the deletion-evidence rows of the FR-4 table
      (`fieldDeletionConflict`), and attachments. **Must pass before any
      deletion, tombstone or attachment behaviour enters the implementation.**
      T009 passing does not discharge it: T009's union is grow-only and
      therefore says nothing about removal. Nothing in the current design
      depends on this — FR-4 states that a missing KDBX field or attachment is
      normally a union, not a deletion — so it blocks the deletion work only.
      **ACCEPTED by the PM 2026-08-22 — the T009b gate is CLOSED.** Acceptance
      was earned, not declared: the evidence was re-executed on `main` by the PM
      (18 tests green; `node tool/mutation_runner.mjs
      --definitions=tool/mutations/008_t009b_deletion_convergence.json --check`
      exit 0, 14 mutations, 0 survivors), the equal-clock tie was verified to
      break toward preservation with an executable assertion (G3, model line
      ~614), and the D13/D14 rows were spot-read to confirm they mutate model
      semantics (Keep clock stamping, manifest omission of the tombstone), not
      counters. Deletion/tombstone/attachment implementation work is unblocked.
      Structure chosen:
      **tombstone with a clock** (LWW-element-set family), not a 2P-Set —
      FR-5's Keep is an un-delete, which a 2P-Set cannot express, and FR-5's
      "preserve newest supported deletion data" is a max-clock join. Evidence:
      `test/features/password_manager/data/services/sync_merge_deletion_convergence_model_test.dart`
      (18 tests: semilattice over add+remove at 3 and 4 devices, every
      ordering × every full parenthesization; FR-4 presence/deletion rows
      including zero-byte attachments; resurrection, delete-vs-edit, repeated
      delete, Keep/Delete convergence) and
      `tool/mutations/008_t009b_deletion_convergence.json` (14 mutations,
      `--check` exit 0, 0 survivors, 0 drift; two of them close survivors an
      adversarial tester pass found against the first table — F1/F2 in
      `feasibility-report.md` §"Adversarial tester pass"). Four spec gaps found and
      resolved conservatively — G1–G4, recorded in
      `feasibility-report.md` §"T009b". **The gate closes only when the PM
      accepts this evidence**, per the T009 precedent: a suite declaring
      itself green is the failure mode the status row exists to prevent.

**Gate 0 exit**: **T001–T009** pass. **MET 2026-08-21** — T001–T008 have
executed evidence; **T009 passed** (36 tests, mutation check exit 0, PR #65).
T201/domain freeze are unblocked. **T009b is not a Gate 0 condition** and does
not block it; it gates the deletion/attachment work only.

A backend's **absent** concurrency capability no longer blocks Gate 0 — it
selects a lower guarantee tier (`spec.md` §"Guarantee by backend category").
What blocked Gate 0 was the storage-agnostic cycle that replaced it being
unvalidated; T009 now validates it. A fidelity gap would still block Gate 0. Platform evidence may remain
`not-run` only with target disabled; Gate 1 T111 must pass before that target
enables.

```bash
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart --plain-name "merge feasibility"
flutter test test/features/password_manager/data/services/google_drive_api_service_test.dart --plain-name "conditional update"
flutter test test/features/password_manager/data/services/database_writer_inventory_test.dart --plain-name "inventory baseline"
flutter test test/features/password_manager/data/services/safe_vault_file_writer_harness_schema_test.dart
flutter test test/features/password_manager/data/services/sync_merge_convergence_model_test.dart
```

## Phase 1 — All-writer serialization and filesystem safety

- [x] **T101 Freeze writer inventory before mutex** — verify current paths:
      `VaultKdbxService` all mutations + credential transaction;
      `DatabaseSyncOrchestrator.syncNow/_backupFile`;
      `DatabaseImportService` import/stage/commit/finalize/rollback/move/replace/
      create; `DatabaseSessionCoordinator` create/import/replace/delete;
      `VaultSessionCoordinator.updateDatabaseSettings` settings/credential/
      rename/rollback; database exports in `database_selection_screen.dart` and
      `vault_navigation.part.dart`.
- [x] **T102 Remove presentation database file writes** — export/copy/delete/
      rename operations use domain ports with data implementations. Architecture
      test rejects new presentation `dart:io` database mutation.
- [x] **T103 `database_path_identity_resolver.dart`** — normalize absolute/
      relative, separators, `.`/`..`, existing symlinks, nonexistent target
      parent, platform case rules and hard-link/file identity. Use global database
      lock fallback where alias identity cannot be proven.
- [x] **T104 `database_path_mutex.dart`** — singleton shared by every T101 writer,
      manual/auto sync and merge. Deduplicate/sort multi-path identities before
      acquisition; independent databases concurrent only when proven distinct.
- [x] **T105 Route all writers** — patch `VaultKdbxService`, import service,
      orchestrator, database/session settings flows and exports. No bypass.
- [ ] **T106 Rename transaction** — lock old+new canonical paths in deterministic
      order through rename, registry/security/sync mapping updates and rollback.
- [x] **T107 Alias/deadlock tests** — relative/absolute, separators, `.`/`..`,
      symlink path/parent, case aliases on relevant filesystem, hard links where
      supported, missing target, source==target and inverse concurrent renames.
- [x] **T108 Collision-safe backup** — exclusive-create temp/final; microsecond
      timestamp + random/counter suffix; no overwrite. Test frozen same timestamp,
      preexisting backup, repeated collision and content preservation.
- [x] **T109 Safe target writer** — same-directory temp, flush/fsync/close, verified
      backup before target write, atomic replace without delete-first, directory
      sync where supported.
      Follow-up (LOW, T105 tester review): `DatabaseImportService.saveKeyFile`
      and the managed key-file copies write in place today (no temp+rename) —
      route key-file writes through this same safe writer.
      Follow-up (HIGH-4 residual, T109 tester review) — **CLOSED**:
      `SafeVaultFileWriter` now gates leaf-symlink resolution on the
      app-private perimeter (`SafeVaultFileIo.appDirectoryRoot` +
      `_isInsideAppPerimeter`), so it agrees with `MobileFileStorage` on the
      directory they share. Outside the perimeter a live link is still
      written THROUGH (HIGH-2, the `~/vault.kdbx -> ~/Cloud/...` case);
      inside it the link is left unresolved and the rename replaces the
      entry (#45/#46). Dangling links are unchanged on both sides. Chosen
      over the `followSymlinks:` flag because the same call sites
      (`VaultKdbxService._save`, the three sync replacements) serve managed
      and user-picked paths interchangeably, so no caller can answer the
      question statically.
      **The perimeter is NOT `documentsRoot()`.**
      `getApplicationDocumentsDirectory()` is the per-app container only on
      iOS/Android and under the macOS sandbox; on Linux
      (`xdg DOCUMENTS`), Windows (`WindowsKnownFolder.Documents`) and
      unsandboxed macOS it is the user's own `~/Documents`, i.e. the
      picker's default location — so the first cut of this gate froze a
      `~/Documents/vault.kdbx -> ~/Dropbox/vault.kdbx` cloud vault while
      reporting success. `SafeVaultFileIo.isAppPrivateDocumentsRoot` decides
      per platform (`Containers` segment for the macOS sandbox); the other
      targets get no perimeter at all. No perimeter counts as outside —
      pre-follow-up behaviour.
      A path holding a `..` segment is now refused outright before the
      perimeter is consulted: the kernel follows an intermediate symlink
      BEFORE applying `..`, so a planted directory link makes a
      textually-inside path land anywhere and NEITHER answer of the symlink
      gate helps. `MobileFileStorage` refuses traversal for the same reason.
      Every direction has a killer in `safe_vault_file_writer_test.dart`,
      including the desktop and the traversal reproducers.
      Follow-up (MEDIUM-2, T109 tester review) — **CLOSED**: the hard stop
      stays. Extending the HIGH-3 fallback to the backup is not available:
      a backup IS a second file, so under a sandbox that authorizes the
      chosen path alone the only degraded option would be to skip it, which
      FR-9 forbids — and the callers that request one are the three sync
      replacements, where remote bytes overwrite the local vault. What
      changed is the diagnosis: a permission-refused backup now raises
      `SafeVaultBackupUnavailableException` naming the operation and the OS
      reason (path-shaped tokens stripped), instead of a raw
      `FileSystemException`. Only the sibling claim is converted — a
      permission failure reading the source vault keeps its own diagnosis,
      since "re-grant folder access" would be the wrong advice there — and
      non-permission backup failures propagate unchanged. The asymmetry is
      documented in `SafeVaultFileWriter.write`'s doc comment; the HIGH-3
      premise itself still awaits T111 platform evidence.
      Follow-up (MEDIUM, T109 tester review): `VaultKdbxService`
      `beginCredentialChange` (`vault_kdbx_service.dart:391-397`) renames the
      database to the backup name and only then renames the temp into place —
      a real window in which `databasePath` does not exist. Preexisting
      (T105/T106), the last delete-then-write left in the codebase; route it
      through the safe writer's replace instead.
- [x] **T110 Failure tests** — backup create/write/flush/verify, disk-full/short
      write, target flush, rename and cleanup failures leave old/full new target.
- [x] **T111 Platform harness artifacts** — run target harness separately on
      Android, iOS, macOS, Windows and Linux. Feature flag defaults disabled until
      matching artifact passes; macOS host test qualifies macOS only. Update each
      `feasibility-report.md` row with result/artifact metadata. Evidence status
      2026-08-25: Android, Windows, Linux, macOS and iOS all passed (Android on
      Android 16 / API 36 emulator, arm64, 8/8 cases). T111 platform evidence
      complete.

**Gate 1 exit**: writer audit has no bypass, alias/rename tests pass, backups never
overwrite, and enabled platform has its own artifact.

## Phase 2 — Compile-safe domain contract

- [x] **T201 Freeze `data-model.md`** from T008 report. **FROZEN 2026-08-22.**
      15 divergences between the document and the executed evidence found and
      resolved toward the report (or toward `spec.md`/`tasks.md` where the
      report is silent, stated per row); recorded in `data-model.md`
      §"T201 freeze log — divergences resolved". Two additions were considered
      and deliberately refused, with the reason recorded: the backend guarantee
      tier (AC 15c forbids the branch it would create; spec 010 owns it) and a
      deletion-evidence model beyond `keep`/`delete` (T009b's G1–G4 resolve in
      the data-layer evidence join).
- [x] **T202 Safe domain models** — `MergeReviewSummary`, opaque session/decision
      IDs, redacted categories/choices/counts, typed commit/recovery outcomes and
      `staleRecoveryLocal`. No path, UUID, checksum/token, plaintext or plaintext
      handles in Equatable/serialization.
      `domain/models/sync_merge_models.dart`. Ids are **types, not `String`s**
      (`MergeSessionId`/`MergeDecisionId`/`MergeDatabaseId`), shape-validated so
      a canonical path, a KDBX UUID or an MD5 checksum is rejected on
      construction. `unsupportedKdbxConstruct` (T008 model correction),
      `unresolvedConflict` and `MergeNeedsReview` added — FR-7's return-to-review
      and budget exhaustion previously had no representation at all.
- [x] **T203 `MergeFieldDisplay`** — transient non-Equatable/non-serializable
      response with redacted `toString`; only field widget may own it.
      `domain/models/merge_field_display.dart`, its **own library**: the safe
      models neither import nor export it, and Dart imports are not transitive,
      so a coordinator/BLoC cannot name the type without adding an import the
      architecture test rejects. Disposable, and a read after disposal throws.
- [x] **T204 `domain/repositories/sync_merge_repository.dart`** — compile against
      T202/T203 models; opaque/redacted port for start, update decision, commit,
      cancel, invalidate, recover pending and transient load-field-display.
      Plus `SyncMergeFailure` (safe code only) for the pre-session FR-2/FR-4
      refusals, which had no way to be reported through the frozen port.
- [x] **T205 Focused domain use cases** under `domain/usecases/` for every T204
      operation. No data imports. Six command use cases in
      `sync_merge_usecases.dart`; `LoadSyncMergeFieldDisplayUseCase` is in its
      own library so importing the commands cannot bring the plaintext response
      into scope.
- [x] **T206 Domain policy/tests** — visible defaults, deterministic notes both,
      shortcut decision set excludes one-sided rows, missing side cannot be
      selected, safe `props`/`toString`; `flutter analyze` and domain tests compile
      without any data implementation.
      Policy in `domain/services/sync_merge_policy.dart`; the FR-4/FR-5/FR-6
      rules are **constructor invariants** on `RedactedMergeDecision`, so a
      one-sided row without deletion evidence is unrepresentable as a decision
      rather than merely skipped by the shortcut. Redaction is enforced
      structurally by a source-parsing test (safe type AND safe name per field,
      `String` only at three listed shape-validated ids, no serializer in the
      module), and an architecture test asserts no `data/` import and that no
      `SyncMergeRepositoryImpl`/DI binding exists yet. Three mutations
      hand-verified as killed.

**Gate 2 exit**: domain models, port, use cases and tests compile/pass standalone.
No `SyncMergeRepositoryImpl` or DI task starts before exit.

**T201–T206 executed 2026-08-22** on `feat/008-t201-t206-domain-contract`:
`flutter analyze` clean, `flutter test` green, zero files added under `data/`,
zero DI registrations.

**Validated in two rounds.** Round 1 (author): 3 mutations, all killed. Round 2
(independent tester): 15 mutations, **6 survived — verdict NOT VALIDATED**. The
contract was sound; the *enforcement* was not, which is precisely what Gate 2
hands to Phase 3. Both gates read hardcoded file lists, so a new leaking model
in `domain/models/` was inspected by nothing. All six are closed, each
re-verified by replaying the tester's exact mutant:

- **F1** scope now derives from `sync_merge_module_registry.dart`, and a file in
  `lib/` naming a merge identifier while absent from the registry fails the
  suite. Killed both unregistered and registered.
- **F2** the field/getter/static rules run on every strictly-redacted registry
  file, so `SyncMergeFailure` is covered — it is the object that reaches logs
  and crash telemetry.
- **F3** getters and statics are walked; a private static may only be a
  `RegExp`.
- **F4** methods are judged by **return type**, not by a name blacklist.
- **F5** the false non-derivability claim is struck from the frozen contract and
  relocated to **T302a**; the shape check's actual acceptances are pinned by
  assertions.
- **F6** registered as a gate condition on **T603**, not implemented now.

Tracked, not implemented: **F7** `RedactedMergeDecision.withChoice` throws
`ArgumentError` while the port declares `SyncMergeFailure` its only error — the
port comment now states the distinction; converting it into a total variant is a
Phase 5 decision. **F8** `MergeDatabaseId`'s path heuristic accepts
`C:vault.kdb` and `Users_me_Documents_Vault`. **F9** `MergeReviewSummary` is the
one `ArgumentError.value` that does not pass `'<redacted>'`.

**Round 3** confirmed F1-F5 genuinely closed (6/6 prior survivors dead) and
returned a second NOT VALIDATED on the gate's *design*: round 1 enumerated
files, round 2 enumerated AST declaration kinds — the same defect twice. The
judge is now **fail-closed** (`test/.../domain/sync_merge_ast_gate.dart`): an
unrecognised top-level construct, class member, type-annotation shape or
directive is a violation, not a skip, so a Dart construct that does not exist
yet breaks the gate the first time it is used. Seven escapes closed and
re-verified on the tester's mutants: **N1** the safe-type set absorbed the
plaintext bucket, letting `SyncMergeFailure` hold a live `MergeDisplaySide`;
**N2/N3** enums, extensions, extension types, typedefs and mixins were never
walked — including an extension adding a plaintext getter to a gated class from
outside its body; **N4** `part` injection (refused outright, with `export`);
**N5** bucket 2 was an opt-out and the importer check matched a literal
filename; **N6** bare-name exemptions left four identifiers free; **N7** the
layering test never checked where a registered file lives. Proof the fix is
structural rather than another enumeration: a deliberately harmless
`class MergeAliased = Object with _Harmless;` fails as
`unhandled top-level construct (ClassTypeAliasImpl)` — it leaks nothing and is
rejected purely for being unrecognised.

**Round 4** accepted the design: 13 constructs thrown at the judge, none passed,
all seven round-3 escapes still dead, no hole of the same family remaining. Four
point rules were added, the first two sharing one root — the judge governed the
port's outbound surface and not its inbound one: **H1** method parameters and
**H4** constructor parameters are now judged (T303 forbids a password, key-file
path or plaintext handle crossing the port, and inbound is the only direction
one can); **H18b** a method named `props` was skipped before the `isGetter`
check, smuggling a serializer onto the port's error object; **H3** inherited
surface (`extends`/`implements`/`with`/`on`) is judged for the strict buckets;
**H2** a bare type parameter is refused in a return position except for private
methods. An own probe of six inbound parameter shapes with neutral names found a
residual: an old-style function-typed formal is reported by the AST via its
return type, so a callable returning a safe type passed — now refused outright.

**The gate closes on PM acceptance of this evidence, not on the suite declaring
itself green** — the T009/T009b precedent.

## Phase 3 — Data-owned full-fidelity implementation and DI

- [x] **T301 `data/services/kdbx_merge_adapter.dart`** — production
      full-fidelity open/import/apply/serialize/reopen/manifest validation based on
      private T003 spike; no `VaultSnapshot` write model, no `KdbxFile.merge`.
      *(Landed 2026-08-22 as the **read half**: open, per-side/lineage/cross-side
      validation and the FR-4 presence diff — the file is read-only and touches
      no filesystem. The mutating half — import one-sided objects, apply
      decisions, serialize, reopen, validate the manifest — lands with the tasks
      whose tests exercise it, T308 and T309, rather than shipping untested
      vault-mutating code ahead of them.)*
- [x] **T302 `data/repositories/sync_merge_repository_impl.dart`** — implement
      already-compiling T204 port; resolve credentials internally and own private
      session store with `KdbxFile`, plaintext, UUID maps, paths, checksums/tokens
      and generation.
- [x] **T302a Opaque id minting** — the data layer mints `MergeSessionId` and
      `MergeDecisionId` tokens from a CSPRNG (`Random.secure()`) with **at least
      128 bits of entropy**, never derived from any input: not the canonical
      path, object UUID, field key, attachment name, checksum, credential or any
      user value. Test asserts the source is `Random.secure()`, that the token
      length carries the declared entropy, that N tokens minted for the same
      database/decision are all distinct across sessions, and that no minted
      token equals a digest of the inputs in scope.
      **This task carries the T202 "not derivable into sensitive values"
      requirement.** It was previously claimed by the id *type*, which cannot
      deliver it: the `ms-`/`md-` + 32-hex shape is a typo guard, and an MD5 is
      itself 32 lowercase hex, so `'ms-' + md5(path)` is accepted — measured by
      the Phase 2 tester (F5). The frozen contract now says so, and the
      guarantee lives here, where there is code to enforce it.
- [x] **T303 Secret boundary** — port returns only domain models. Password,
      key-file path/bytes, KDBX types, plaintext store and preconditions never
      cross port. Dispose store on cancel/lock/invalidate/completion.
- [x] **T304 Pre-diff UUID validation** — per side, require globally unique non-nil
      live root/group/entry UUIDs. Reject duplicate entry, duplicate group,
      group-entry collision, nil UUID and cross-side object-kind mismatch as
      `unsupportedKdbxData` before session/write/upload.
- [x] **T305 Lineage/unsupported guards** — wrong root UUID and other unsupported
      data fail before review/backup/write/upload.
- [x] **T306 Field presence diff** — explicit present/missing model; empty string
      and zero-byte attachment remain present. Missing without explicit marker is
      automatic union.
- [x] **T307 Presence/UUID tests** — all T304 failures plus same entry UUID with
      local-only/remote-only custom fields and attachments, empty-vs-missing,
      zero-byte-vs-missing, protection flags and equal-name/different bytes.
- [x] **T308 Shortcut/deletion tests** — Prefer local/remote never choose missing/
      null; all one-sided data survives; deletion requires explicit evidence and
      keep/delete choice; no ambiguous resurrection.
- [x] **T309 Password+key-file candidate reopen** — semantic manifest matches
      expected result and unrelated metadata/history/icons/settings survive.
- [x] **T310 DI after contract+implementation compile** — bind T302 in data DI and
      T205 use cases in domain DI; no presentation dependency on data
      implementation. Run analyze after registrations.

**Gate 3 exit**: implementation compiles against domain contract; fidelity,
UUID/lineage, presence, deletion, shortcut, secret boundary and DI tests pass.

> **Gate 3 is CLOSED (2026-08-22).** Independent tester verdict **VALIDATED**,
> against `main` at PRs #91, #93 and #96. The evidence was re-executed, not
> declared: **1293 tests green**, `flutter analyze` clean; end-to-end
> commutativity **30/30 on `main`**; **zero undeclared dimensions** in the
> full-manifest diff between two devices at **0, 10 and 25 seconds of skew**, on
> a fixture that also exercises divergent metadata; **15/15 regression mutants
> killed**, including the two gaps the previous round left open (`_newer`
> inverted, and the D16 codes). HIGH-5 and HIGH-6 are re-verified closed with
> their original probes: the tombstone reports `CONVERGED=true` from the first
> exchange on the max and stays stable over three rounds, and remote metadata is
> preserved from both perspectives with the recycle bin resolving by UUID.
>
> Four residual findings remain — **MEDIUM-5, MEDIUM-6, LOW-4, LOW-5**. They are
> coverage gaps on code verified correct, **not regressions**, and none produces
> data loss as the code stands. They are handed to **T401**, which re-reads
> `_mergeMeta` for FR-7 step 5 anyway, and are written out there.

**Phase 3 slice 2 executed 2026-08-22** on `feat/008-t302-t310-merge-repository`
(T302, T302a, T303, T308, T309, T310). `flutter analyze` clean, `flutter test`
green (1264 tests). What landed beyond the six task lines, and why:

- the **mutating half of T301** — record-level FR-5 evidence, decision apply,
  one-sided record import, candidate serialization and the FR-1 reopen/manifest
  parity gate (`kdbx_semantic_manifest.dart`). T308 and T309 are not assertable
  without it; slice 1 deferred it for exactly that reason.
- **recycle-bin membership is re-derived from the tree.** Deleting an entry in
  this app MOVES it to the bin, so the record stays shared and its fields keep
  diffing, while the bin group appears as an ordinary one-sided group. Neither
  fact is visible in the adapter's UUID sets.
- **no write, no mutex.** `commit` returns `MergeRejected(platformDisabled)` and
  `recoverPending` reports `none`: the FR-7 cycle is T401-T410 and Gate 1 T111's
  per-platform artifacts are still `not-run`. Nothing in this slice touches the
  filesystem, so nothing routes through `DatabasePathMutex` — the anti-nesting
  audit is trivially satisfied and the Gate 1 routing guard's `maxDepth == 1`
  is unchanged.
- **registry**: `SyncMergeRepositoryImpl` removed from `phase3TypeNames`; a
  fifth bucket, `mergeCompositionRootFiles`, makes the DI modules a *barrier*
  in the T303 transitive-reachability check, guarded by an assertion that they
  export nothing.

Frozen-contract insufficiency found and **resolved by amendment** (PM-ratified,
`data-model.md` D16): one new code, `mergePreconditionFailed`, for an unknown
database id and for a database with no remote mapping. A missing local database
file deliberately stays `staleLocal` — its user-facing remedy is correct for an
absent file too.

**Validated in two rounds.** Round 1 (independent tester): **NOT VALIDATED**,
three HIGH. The code was right; the mechanisms meant to keep it right were not.
All closed, each re-verified by replaying the tester's own mutant:

- **HIGH-3** `buildCandidateBytes` was re-callable on a session `applyMerge` had
  already consumed. In debug a raw `AssertionError` crossed the port; **in
  release the assertion is compiled out** and the candidate carried two objects
  with the same UUID — the FR-2 violation, introduced by the merge. Closed by
  consuming the session before applying, and by re-running `validatePair` on the
  candidate, which is the layer that still works with assertions off. Both
  verified: `dart run` (asserts off) reproduces `DUPLICATE_UUIDS=true` on the
  unfixed path and `OUTPUT_REVALIDATION=refused unsupportedKdbxData` with the
  fix.
- **HIGH-2** the FR-1 parity gate had no test: deleting `serializeCandidate`
  left the suite green. Closed with both branches — a candidate that does not
  reopen, and one that reopens while its **manifest** does not survive.
- **HIGH-1** the DI barrier checked only for `export`; a `typedef` and a public
  factory carried decrypted plaintext into `presentation/` with `analyze` clean.
  Closed by bounding the exemption by construction: a barrier declares the two
  `register*Dependencies` functions, private declarations, and nothing else at
  all.
- **MEDIUM-1** FR-2's "nothing before the guards" is now asserted on the source
  order inside `startReview`. **MEDIUM-2** the T302a source test was passable by
  an LCG that never writes the word `Random`; the assertion moved to the body of
  `_mintToken`. **MEDIUM-3** the tombstone clock re-stamp had no coverage.
- Added on request: **end-to-end commutativity** (FR-3), the bridge from T009's
  model to the implementation.

**Round 2** (independent tester): seven of seven round-1 mutants dead, the
release reproduction matching byte for byte, the barrier's whitelist-by-
construction the right shape. Two HIGH remained, both closed here:

- **HIGH-1** the barrier's signature check was **inert on the return type**: an
  absent `typeParameters` interpolates as the literal `null` and destroys the
  trailing word boundary, so the real function's signature read
  `KdbxMergeAdapternull(GetIt sl)`. Return type is the laundering direction
  that matters — a barrier leaks by *returning* the adapter. Fixed by joining
  the null-coalesced parts with a separator; a sweep found the pattern nowhere
  else in the gate tests.
- **HIGH-4** a third commutativity divergence, and unlike the other two it was
  state **the merge wrote itself**: `addEntry`/`addGroup`/`setString` route
  through `Changeable.modify`, which stamps `DateTime.now()`. Two devices never
  merge in the same second, so the group that received an import and the entry
  that received the other side's fields diverged permanently. **Corrected, not
  projected away**: `_stampDeterministicTimes` restores every object's
  modification and location times to the FR-3 join of the two inputs, so the
  candidate no longer depends on when it was built. The commutativity test now
  forces a 1.5 s gap between the two devices, which turns the former ~27% flake
  into a deterministic assertion — 30/30 isolated runs green.

Two dimensions remain **not** commutative, each pinned by its own executable
assertion rather than hidden, and both are pre-existing per-replica state the
merge preserves rather than writes: **sibling order** (each device appends its
imports to the end of the target group — needs FR-3's total order, T401a) and
**entry history** (KDBX history is a per-replica edit log; FR-1 says preserve,
nothing says merge). Both matter to FR-7 step 5, which arbitrates on the
canonical manifest. Reported as T401/T401a input.

**Round 3** (independent tester): two HIGH, both closed.

- **HIGH-6** the wall-clock exception above was ratified on a convergence that
  did not exist. `_unionTombstones` was add-if-missing, with no comparison, so
  two devices deleting the same record seconds apart each froze their own clock
  forever — `ROUND2_CONVERGED=false`, `ROUND3_CONVERGED=false` — while the
  method's own doc claimed FR-5's "preserve newest supported deletion data".
  The join is now a real max; the three-round replay converges in round 1.
- **HIGH-5** `applyMerge` never merged `KdbxMeta`, so every metadata field came
  unconditionally from the local side: a database renamed on one device lost
  its name after a merge on the other, with no conflict, decision or refusal —
  and a device whose local side had no recycle bin imported the bin group as a
  one-sided union while `recycleBinUUID` stayed null, leaving an orphan group
  of deleted entries in the ordinary tree and creating a second bin on the next
  delete. **Merged, not refused**: KDBX stores a change clock beside each
  metadata field (`DatabaseNameChanged`, `RecycleBinChanged`, `SettingsChanged`
  and the rest), so FR-3's automatic policy has the evidence it needs and no
  new conflict category is required. The clocks are now part of the canonical
  manifest, since they are the evidence the merge resolves on.
- **MEDIUM-4** the direction of the time join is asserted directly (the
  commutativity test is blind to it — both directions are commutative).
  **LOW-2** D16's code placement is asserted. **LOW-3** the override-vs-stamp
  imprecision is annotated, with its conservative damage direction.

**Frozen-contract insufficiency found and NOT resolved.** An automatic metadata
adoption is invisible in `MergeReviewSummary`: `localOnlyRecordCount`,
`remoteOnlyRecordCount` and `oneSidedFieldCount` are record- and field-scoped,
and there is no counter, decision row or category for "the database name came
from the other side". The merge is correct and silent. Phase 6 cannot show the
user what changed at metadata level without a contract change; raised here, not
worked around.

One wall clock is left in the apply step by decision: the tombstone of a
**fresh** explicit Delete. A Delete is a user decision taken at a real moment
and is per-device by T009b's G4, and — now that `_unionTombstones` really is a
max — the clock is join-convergent, so two devices converge on the next round
instead of rewriting each other forever, which is precisely what a modification
time under a wall clock does not do.

## Phase 4 — Preconditions, commit and remote recovery

- [ ] **T401 Write-verify-converge cycle** — implement FR-7's storage-agnostic
      cycle in `get` + `put` terms: read/record expected base, merge, revalidate
      under the mutex, write, and **mandatory step-5 read-back verification**.
      On divergence: re-anchor the expected base to the observed content,
      short-circuit on canonical semantic-manifest equality, then re-merge with
      the sticky decision ledger re-applied. Retry budget 3 per commit session.
      A non-executable read-back is `ambiguous`, not `finalized`.
      **No concurrency token is selected or added.** Drive enforces none —
      measured, B1 — and FR-7 declares the token optional, used only where the
      storage adapter declares `conditionalWrite`. `DriveRemoteFile` gains no
      token field. `md5Checksum` serves as the step-5 comparator.
      *(Respecified 2026-08-15. This task previously read "add Gate 0-proven
      concurrency token and server-enforced conditional `updateFile`". The
      2026-08-15 report claimed the respecification had happened while this line
      was unchanged — a declared-but-unmade change, the same error class as the
      fabricated citation corrected in the 2026-08-14 pass. It is made here.)*

      **What T401 must decide — the single list.** Everything below is input
      T401 *treats*, not something it should rediscover; `_mergeMeta` is
      re-opened here anyway for FR-7 step 5. Every item is either a **coverage
      gap on code verified correct** or an open design question. **None is a
      regression, and none produces data loss as the code stands today.**

      *Residual findings from the Gate 3 final validation (2026-08-22) —
      **all four closed 2026-08-24** on `test/close-mergemeta-findings`, each by
      replaying its mutant first (survives at HEAD), adding the assertion, and
      re-replaying it (dies). The code was correct in all four cases, as the
      Gate 3 tester judged; what was missing was the guard.*
      - **MEDIUM-5 — recycle-bin atomicity. Closed**, two assertions: the
        winning direction adopts flag + UUID + clock together, the losing
        direction moves none of them. One correction to the finding's rationale,
        measured rather than assumed: the "subsequent deletions go permanent"
        consequence does **not** hold inside this app. Neither `KdbxDao`
        (`deleteEntry` calls `getRecycleBinOrCreate` unconditionally) nor any
        code here reads `RecycleBinEnabled`. The real cost is the permanent
        `/meta/recycleBinEnabled` manifest divergence FR-7 step 5 arbitrates on,
        plus wrong behaviour in KeePass/KeePassXC, which do honour the flag.
      - **MEDIUM-6 — "a known clock beats an unknown one". Closed.** The
        assertion drives both mirrors and picks values so that FR-3 rule 3 would
        elect the *opposite* side, which kills two mutants instead of one: the
        inversion, and a deletion of both branches that falls through to the
        value order.
      - **LOW-5 — the `customData` settings-clock pre-capture. Closed, and it is
        NOT merely a precaution:** it is load-bearing. Read inline instead of
        pre-captured, the loop sees `localAt == remoteAt` whenever the settings
        block above it just overwrote the local clock, mistakes a decided
        comparison for a tie, and drops to the byte order — while the mirrored
        merge, where that block does not fire, keeps its own side. Demonstrated
        non-commutative, with the fixture the Gate 3 tester could not build.
      - **LOW-4 — icons sharing a UUID with different bytes. Decided: PINNED,
        not fixed**, joining sibling order and entry history as a divergence
        held by an executable assertion rather than hidden. The proposed
        two-line byte tie-break is **not implementable** against kdbx 2.5.0:
        `KdbxMeta.customIcons` is an `UnmodifiableMapView` and `addCustomIcon`
        (first-wins, early return) is the only mutator, so no caller of the
        library can replace the bytes under an existing UUID. That same fact
        also settles reachability more firmly than the original argument did:
        the state cannot be produced by this app at all, only parsed in from a
        foreign writer that reuses a UUID with different bytes. The pin asserts
        both halves, so a kdbx upgrade that adds a real mutator reopens the
        remedy instead of the divergence going unnoticed. **Carry forward:**
        if T401a's comparator lands while kdbx still offers no mutator, the
        remedy is a dependency question, not a merge-adapter one.

      *Coverage finding from the same round, also closed 2026-08-24:*
      - **F4 — `BrowserSetupService`'s host-separator fix was Windows-only
        coverage. Closed.** The prescribed remedy (assert the separator against
        `platform` instead of a literal) was applied and then **measured**: it
        alone does not close the gap. With `p.posix.join` mutated back to the
        host-context `p.join`, every runtime assertion still passes on a POSIX
        host, because there the host separator and the rendered one agree, and
        for the Windows target the trailing `replaceAll('/', r'\')` normalises
        the difference away. The defect is observable at runtime only where
        host != target. What does hold on every host is a source assertion over
        the two display-path builders — no join with the implicit host context,
        and an explicit `p.posix` re-spelling present — which dies with either
        mutant half on macOS, Linux and Windows alike.

      *Removed from this list on 2026-08-23, decided:* **no per-field
      modification time.** Product decision, option (a): FR-3's LWW is
      entry-level, and the credential block of FR-3a is the one exception to
      per-field resolution. No longer an open question — it is an instruction,
      in **T401a** and **T401c** below and in `spec.md` FR-3/FR-3a.

      *Already open, carried forward — grouped here, stated where they live:*
      - **`KdbxFieldDiff.keySpellingDiverges` is emitted and read by nobody.**
        Full statement and the three analysed candidates: **T401a** below.
      - **Sibling order and entry history are not commutative.** Both are
        pre-existing per-replica state the merge preserves rather than writes,
        each already pinned by its own executable assertion. Statement: the
        Phase 3 Round 2 note above, "Two dimensions remain **not** commutative".
      - **Automatic metadata adoption is invisible in `MergeReviewSummary`.**
        Frozen-contract insufficiency, raised and deliberately not worked around.
        Statement: the Phase 3 Round 3 note above, "Frozen-contract insufficiency
        found and NOT resolved".
- [x] **T401a Deterministic tie-break** — implement FR-3's globally deterministic
      total order over candidate values (unsigned lexicographic, greater wins)
      for timestamp ties and unknown timestamps, and use the same order to fix
      the operand order of the deterministic notes concatenation. Never "prefer
      local": that is perspective-dependent and makes the merge non-commutative.
      Promote the T009 model properties to adapter-level tests.
      **Unblocked 2026-08-23 — the timestamp question is decided, option (a).**
      This is now an instruction, not a question. The adapter emits the
      **entry's** `lastModificationTime` as the timestamp for every field of
      that entry, in place of today's "no timestamp at all", so rules 1 and 2
      elect the newer *entry* and its side wins for all of that entry's
      conflicting fields at once; rule 3 decides field by field on equal or
      unknown entry times, with the FR-3a credential block as the single
      exception. Options (b) — treat every timestamp as unknown — and (c) —
      derive a per-field time from history revisions — are **rejected**;
      (c) by measurement (revision granularity is one save cycle, the derived
      time is per-replica and does not converge, and a pruned history yields a
      wrong time that rule 1 would rank above the truth). Option (d), a
      per-field time persisted in the entry's `CustomData` behind an anchor on
      `lastModificationTime`, is a recorded future improvement and is **not in
      scope here**; adopting it requires its own commutativity/associativity
      test of the T009 standard. Full statement and evidence: `spec.md` FR-3
      §"The timestamp in rules 1 and 2 is the entry's" and §"Why a per-field
      time is not derived from history revisions". Acceptance: criterion 15l,
      plus 15g/15j/15k which stand unchanged.
      T401a must also extend the model to cover the protection dimension the
      adapter compares, and must expose the byte comparator as a reusable
      primitive: **T401c** consumes it. (**LOW-4** no longer does — it was
      closed as PINNED on 2026-08-24, because kdbx 2.5.0 exposes no mutator
      that could apply a tie-break to an existing custom icon. See T401's
      residual-findings list above.)
      **Third open item from T301: `KdbxFieldDiff.keySpellingDiverges`.** The
      adapter emits it and nothing reads it today, so T401a must treat it
      deliberately rather than discover it. It cannot be deferred again: KDBX
      admits exactly one key, so even the `identical` case — equal values,
      different spelling, e.g. local `Custom_Totp` vs remote `custom_totp` —
      forces the apply step to pick one. The three candidates are already
      analysed and two are ruled out: "keep local" is perspective-dependent and
      forbidden by FR-3; promoting it to a conflict contradicts FR-4's
      "present, equal → identical" row by asking the user about values that
      agree; FR-3's deterministic UTF-8 order is probably right but needs the
      comparator this task builds, which is why the decision lives here.
      *Landed and validated 2026-08-25 on `feat/008-gate4-tiebreak-ledger-credblock`
      (uncommitted, PM-held pending Gate 4 continuation): `compareFieldPresent` and
      the Notes sentinel-union in `kdbx_merge_adapter.dart` use `utf8.encode`
      throughout, never `codeUnits`. Independent tester confirmed no UTF-16
      comparison path, replayed the 15l entry-level-LWW tests directly (both
      fields default to the newer entry, not a per-field union), and confirmed
      15j/15g/15k via the promoted adapter-level tests in
      `kdbx_merge_adapter_test.dart` and two new `sync_merge_repository_impl_test.dart`
      cases. One pre-existing, non-regressed gap disclosed and carried forward:
      `_takeRemote` (Gate 3 code) still resolves `fieldConflict` key-spelling by a
      perspective-dependent local-preferring default, not this task's UTF-8 order —
      tracked for a follow-up, not blocking.*
- [x] **T401c Atomic credential block** — implement FR-3a. Product decision of
      2026-08-23: per-field merge is kept, and `UserName`, `Password` and `URL`
      become the one exception, moving together as a block. Not expressible
      inside T401a, which owns the comparator and not the diff/apply/review
      shape.
      Scope, all of it verifiable against FR-3a and criteria 15m/15n:
      - **membership** by canonical key only — `canonicalFieldKey(key)` ∈
        {`username`, `password`, `url`} — so it is case-insensitive by
        construction and closed; `Title`, `Notes`, OTP, other custom strings and
        all attachments stay per-field;
      - **engagement** on ≥1 conflicting shared member, at which point every
        *shared* member takes value, protected/plain flag and verbatim key
        spelling from the same winning side;
      - **one winner per block**: FR-3 rules 1/2 on the entry time, then rule 3
        applied **once** to the side's block image — members in the fixed
        canonical order `password`, `url`, `username`, joined by `0x1E`, an
        absent member contributing an empty sequence — using T401a's comparator;
      - **no deletion**: FR-4 is unweakened; one-sided members are preserved
        under every shortcut, and a fully one-sided block stays dormant;
      - **one review row** per engaged block, `category` = highest-priority
        engaged member (`password` > `username` > `url`), `bothNotes`
        unavailable, shortcuts selecting the whole block;
      - **ledger keying** by entry UUID + block identity, coordinated with
        T401b, so a re-merge re-applies one decision and never re-splits it.
      Known contract gap, deliberately not worked around: `MergeFieldCategory`
      has no `credentialBlock`, so the summary names the row by its anchor only.
      Recorded beside the metadata-visibility insufficiency under T401; the row
      copy must state the scope in words (T602/T603).
      *Landed and validated 2026-08-25 on `feat/008-gate4-tiebreak-ledger-credblock`
      (uncommitted, PM-held pending Gate 4 continuation): 15m verified with a fixture
      where per-field UTF-8 order elects opposite sides for `UserName`/`Password`,
      asserting the block still takes both from one side from both mirrored
      perspectives, and asserted to fail against a naive per-field comparator.
      15n verified for dormant-fully-one-sided and engaged-with-one-one-sided-member
      cases. Case-insensitive/closed-set membership and non-conflicting-shared-member
      adoption both tested. Two LOW test-coverage gaps noted by tester, not blocking:
      one-sided-member survival tested only with block winner = remote (not local) at
      adapter level, and no attachment-named-`password`/`username`/`url` collision
      test (code already guards it via `fieldKind != string`).*
- [x] **T401b Sticky decision ledger** — record explicit user decisions keyed by
      object UUID plus field key/attachment name — and, for an FR-3a credential
      block, by entry UUID plus the block identity rather than per member —
      re-apply after every re-merge
      ahead of LWW/tie-break/shortcuts, and return the session to review when a
      re-merge introduces a conflict the user has never been shown.
      *Landed and validated 2026-08-25 on `feat/008-gate4-tiebreak-ledger-credblock`
      (uncommitted, PM-held pending Gate 4 continuation), in `merge_decision_ledger.dart`
      — a pure, session-lived primitive with no caller yet (T401 wires it in later).
      **Round 1 found HIGH**: `_replayValue` matched on the originally recorded side-tag
      instead of on which current candidate holds the decided value, so a field decided
      `remote` spuriously reopened review on the very next round where the true remote
      moved again while the decided value was carried forward into local — reachable in
      T401's ordinary re-merge shape, not the exotic neither-matches case. Repro:
      decide `remote`/`B`, replay against `currentLocal=B, currentRemote=C` → measured
      `MergeLedgerStale`, required `MergeLedgerReplayed(local)`. **Fixed and re-verified
      round 2**: `_replayValue` now decides purely from which current side's value
      matches the decision, with 4 new same-side-flip regression tests (both directions,
      both field and credential-block paths); the defensive neither-matches-stale case
      and the unconditional `bothNotes`/`keep`/`delete` operation replay were confirmed
      unregressed. Full suite independently reproduced by tester: 1449 passed, 1 skipped,
      `flutter analyze` clean.*
- [ ] **T402 Local/remote staleness** — recompute local checksum and refetch remote
      checksum under path mutex immediately before backup; compare the remote
      against the **current** expected base, which the divergence branch
      re-anchors. Refetch the token too, but only on a `conditionalWrite`
      adapter. Stale side causes zero write.
- [ ] **T403 Atomic commit integration** — candidate semantic validation, verified
      collision-safe backup, target temp/replace and mapping transaction.
- [ ] **T404 Persist `_PendingMergeUpload` before dispatch** — merged/local
      checksums, expected old remote checksum, remote file ID, private backup/
      path, no plaintext/credentials. The expected old **token** is persisted
      only on a `conditionalWrite` adapter; on a bare adapter there is none.
- [ ] **T405 Outcome classification** — a **certain rejection exists only on a
      `conditionalWrite` adapter** and means not applied. On every other backend
      a success response is an **apparent** success, never terminal: the FR-7
      step-5 read-back promotes it to confirmed before the mapping is finalized.
      Absence of a rejection is not evidence that nothing was overwritten.
- [ ] **T406 Ambiguous transport outcome** — timeout/disconnect after dispatch
      persists `outcomeAmbiguous`; do not retry blindly or mark synced/failed.
- [ ] **T407 Recovery local guard** — under per-database mutex, hash current local
      bytes and compare persisted `localCommittedChecksum` before remote client
      call or any vault mutation. Mismatch -> `staleRecoveryLocal`; no upload,
      retry, finalization or success mapping update; retain backup/evidence and
      require fresh conflict.
- [ ] **T408 Matching-local remote triage** — only after T407 match, refetch:
      merged checksum -> finalize; unchanged expected-old checksum -> safely
      re-enter FR-7 from step 3 (re-sending the token only on a
      `conditionalWrite` adapter; on any other adapter the step-3 re-read plus
      the step-5 verification carry the safety); third state -> new conflict
      while retaining local+backup. On a `versionHistory` adapter the overwritten
      revision is additionally fetched and offered as the remote side.
- [ ] **T409 Restart recovery tests** — recreate process/data repository with
      pending record. Cover local mismatch first and assert zero remote calls/
      mutation, then matching-local applied/not-applied/third-state branches before
      normal auto-sync.
- [ ] **T410 Upload tests** — apparent success verified and unverified,
      timeout-applied, timeout-not-applied, timeout-third-state, retry timeout,
      **non-executable step-5 read-back**, divergence-then-converge, semantic
      short-circuit, retry-budget exhaustion, and conditional reject (on a
      `conditionalWrite` fake adapter only). Mapping never claims synced
      prematurely and never on an unverified apparent success.
- [ ] **T412 Capability parity** — coordinator, use cases and merge adapter
      produce identical decisions against a CAS adapter, a `versionHistory`
      adapter and a bare `get`/`put` adapter. Only the reported guarantee tier
      differs; no domain or presentation code branches on a capability.
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
      **FR-3a copy duty**: an engaged credential block is one row, and
      `MergeFieldCategory` cannot say so, so the row's copy must state in words
      that answering it also moves the entry's other credential fields.
- [ ] **T603 Field diff** — widget-local transient display, protected masked,
      present/missing labels non-selectable for one-sided data, explicit deletion
      choice only with evidence.
      **Gate condition (F6), required in the same commit that adds the field
      widget to `mergeFieldDisplayImporters`.** The import allowlist is the only
      real containment layer `MergeFieldDisplay` has: an already-allowlisted file
      can still copy `.value`/`.label` into a durable `String`, put it in
      `props`/`toString`, or cache it statically — verified green by the Phase 2
      tester. So the widget may not be allowlisted until a test over the
      allowlisted files rejects (a) any `String` field or static initialized from
      `.value`/`.label`, and (b) any retention of a `MergeFieldDisplay` outside a
      `State` whose `dispose()` disposes it. Adding the widget without that test
      re-opens the hole the allowlist appears to close.
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
