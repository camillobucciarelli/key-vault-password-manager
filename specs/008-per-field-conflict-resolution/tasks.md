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
- [ ] **T105 Route all writers** — patch `VaultKdbxService`, import service,
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
      Follow-up (HIGH-4 residual, T109 tester review): `SafeVaultFileWriter`
      resolves a live leaf symlink with **no perimeter gate**, while
      `MobileFileStorage` two files away refuses to follow one in the same
      directory. Not a regression — `main` write-through is identical, and
      the backup no longer escapes the caller's directory — but the two
      layers disagree by construction. Candidate fix: a `followSymlinks:`
      flag set by the desktop call sites and cleared by the managed-path
      ones, or a gate on `isPathInAppDirectory`. **Close before the next
      mobile release.**
      Follow-up (MEDIUM-2, T109 tester review): the HIGH-3 sandbox fallback
      covers the target temp only, not the `createBackup` sibling that runs
      before it. If the HIGH-3 premise holds on sandboxed macOS, routine
      saves (`backupExistingTarget: false`) degrade and succeed while the
      three sync replacements fail permanently at the backup step —
      fail-safe and consistent with the FR-9 hard stop, but an undocumented
      asymmetry. Recorded in `safe_vault_file_writer.dart`'s doc comment;
      resolve together with T111 platform evidence.
      Follow-up (MEDIUM, T109 tester review): `VaultKdbxService`
      `beginCredentialChange` (`vault_kdbx_service.dart:391-397`) renames the
      database to the backup name and only then renames the temp into place —
      a real window in which `databasePath` does not exist. Preexisting
      (T105/T106), the last delete-then-write left in the codebase; route it
      through the safe writer's replace instead.
- [ ] **T110 Failure tests** — backup create/write/flush/verify, disk-full/short
      write, target flush, rename and cleanup failures leave old/full new target.
- [ ] **T111 Platform harness artifacts** — run target harness separately on
      Android, iOS, macOS, Windows and Linux. Feature flag defaults disabled until
      matching artifact passes; macOS host test qualifies macOS only. Update each
      `feasibility-report.md` row with result/artifact metadata.

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
- [ ] **T302 `data/repositories/sync_merge_repository_impl.dart`** — implement
      already-compiling T204 port; resolve credentials internally and own private
      session store with `KdbxFile`, plaintext, UUID maps, paths, checksums/tokens
      and generation.
- [ ] **T302a Opaque id minting** — the data layer mints `MergeSessionId` and
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
- [ ] **T303 Secret boundary** — port returns only domain models. Password,
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
- [ ] **T401a Deterministic tie-break** — implement FR-3's globally deterministic
      total order over candidate values (unsigned lexicographic, greater wins)
      for timestamp ties and unknown timestamps, and use the same order to fix
      the operand order of the deterministic notes concatenation. Never "prefer
      local": that is perspective-dependent and makes the merge non-commutative.
      Promote the T009 model properties to adapter-level tests.
      **Blocked on a design decision, raised by T301 (2026-08-22): KDBX has no
      per-field modification time.** `KdbxTimes` is on `KdbxObject`, so the
      finest available granularity is one `lastModificationTime` per entry.
      Rules 1 and 2 of the total order therefore cannot discriminate two fields
      of the same entry, and **every intra-entry field conflict falls through to
      rule 3** (the UTF-8 value order) as a block. Decide and record which it
      is before implementing: (a) accept entry-level LWW and rewrite FR-3's
      "newer modification time wins" to say so; (b) treat every field timestamp
      as unknown and rely on rule 3 alone; or (c) source a per-field time from
      history revisions, if one can be derived at all. The adapter deliberately
      emits **no** timestamp today rather than passing off an entry time as a
      field time. See `feasibility-report.md` §"Where the T301 adapter's
      evidence does NOT line up with T009's model". T401a must also extend the
      model to cover the protection dimension the adapter compares.
- [ ] **T401b Sticky decision ledger** — record explicit user decisions keyed by
      object UUID plus field key/attachment name, re-apply after every re-merge
      ahead of LWW/tie-break/shortcuts, and return the session to review when a
      re-merge introduces a conflict the user has never been shown.
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
