# 008 — Feasibility report

**Report task**: T008
**Current status**: Gate 0 **CLOSED 2026-08-21**. T009 passed — 36 tests green
and `node tool/mutation_runner.mjs
--definitions=tool/mutations/008_t009_convergence.json --check` exit 0, 0
survivors (PR #65) — re-verified on `main` and accepted by the PM on
2026-08-21. **T201 and the domain freeze are unblocked.** T009b remains a
separate open gate blocking only deletion/tombstone/attachment work. Feature
stays disabled on every platform, on the platform-atomicity rows.

**History**: the 2026-08-15 close was **reverted** on
independent review 2026-08-15. B1 remains measured and `failed`, and it is
correctly no longer a blocker — but the mechanism that replaced it, the FR-7
write-verify-converge cycle, is itself `not-run`, and the close was declared in
the same commit that rewrote the exit criterion. Gate 0 now closes on **T009**,
the model validation of that cycle — which it now has done.
**Safety rule**: `not-run`, `failed` or `disabled` never enables feature

This file is authoritative Gate 0/Gate 1 record. Update rows with command, commit,
runtime and artifact evidence. Never convert assumption into `passed`.

## Provenance of this run

| Item | Value |
| --- | --- |
| Branch | `feat/008-merge-gate0` |
| Base commit | `2bea450` (`chore: bump build number to v0.3.0+60`) |
| Working tree | uncommitted; Gate 0 output is test-only, `lib/` untouched |
| Flutter | 3.44.8 stable (fvm), revision `058e0af2c2` |
| Host | macOS (darwin), APFS |
| Date | 2026-08-13; corrected after independent review 2026-08-14 |

Second run — the B1 live-network re-spike:

| Item | Value |
| --- | --- |
| Branch | `feat/008-drive-conditional-spike` |
| Spike commit | `6354da0` (`chore(008): add live-network Drive conditional upload spike`) |
| Working tree | `lib/` untouched; spike lives in `tool/`, runs manually, is in no CI suite |
| Date | 2026-08-15 |
| Detail | see "B1 live-network re-spike (2026-08-15)" |

Third pass — the 2026-08-15 independent review of the amendment:

| Item | Value |
| --- | --- |
| Branch | `feat/008-drive-conditional-spike` |
| Reviewed commits | `434d0d3` (FR-7 rewrite), `281a1f0` (spec 010 draft) |
| Verdict | **not validated, rework**. Two blocking design defects in the convergence cycle, five further correctness/safety defects, Gate 0 close reverted |
| Outcome | spec 008 FR-3/FR-7/FR-10 corrected, Gate 0 reopened with new item **T009**, spec 010 Drive row demoted |
| Date | 2026-08-15 |
| Detail | see "Convergence-cycle review (2026-08-15)" |

> **Read "Post-review corrections" and "Convergence-cycle review" at the end of
> this file before any row above.** Two independent reviews have now rewritten
> parts of this record: the 2026-08-14 one found a fabricated evidence citation
> and `passed` cells with no executed test, and the 2026-08-15 one reverted the
> Gate 0 close and found the replacement convergence cycle non-convergent as
> written. Every row below is the corrected version.

**Toolchain caveat — resolved 2026-08-15.** The 2026-08-13/14 runs recorded that
`flutter pub get` could not resolve on this checkout (`pubspec.yaml` pinned
`analyzer: ^14.1.0` needing `meta ^1.18.3`, while Flutter 3.44.8 pins
`meta 1.18.0`), so every command ran with `--no-pub`. **That is no longer true.**
Commit `c139ee1` (`fix(deps): pin analyzer to ^13 so pub get resolves again`,
#32) repaired the constraint. `flutter analyze` and `flutter test` now run with
no flags and CI can reproduce this report. The `--no-pub` flag in the commands
below is retained verbatim as the historical record of how those runs were
executed; it is not required today.

Re-verified 2026-08-15 on `feat/008-drive-conditional-spike`:

```text
$ flutter analyze
No issues found! (ran in 6.7s)

$ flutter test
00:14 +570: All tests passed!
```

That run measured the full suite at **570**, against the 555 recorded for the
2026-08-14 run. The 2026-08-15 pass itself added and removed no test. The delta of
15 is the harness schema file: it landed in `80b796b` with **30** tests, while the
2026-08-14 transcript below recorded it at 15, and 555 + 15 = 570. That pre-squash
branch state no longer exists, so the 555 / `+15` transcript cannot be re-executed;
it is kept verbatim as the record of that run rather than restated as fact.

Both 555 and 570 are historical. The suite stands at **603** today — see the
fourth-pass review below for the current count.

### Commands executed and real results

```text
$ dart analyze
Analyzing password-manager...
No issues found!

$ flutter test --no-pub test/features/password_manager/data/services/vault_kdbx_service_test.dart --plain-name "merge feasibility"
00:00 +18: All tests passed!

$ flutter test --no-pub test/features/password_manager/data/services/google_drive_api_service_test.dart --plain-name "conditional update"
00:00 +10: All tests passed!

$ flutter test --no-pub test/features/password_manager/data/services/database_writer_inventory_test.dart
00:00 +13: All tests passed!

$ flutter test --no-pub test/features/password_manager/data/services/safe_vault_file_writer_harness_schema_test.dart
00:00 +15: All tests passed!

$ flutter test --no-pub
00:16 +555: All tests passed!
```

Counts above are the post-review run (2026-08-14). The pre-review run was
`+15` / `+10` / `+12` / `+15` and `+551` in total.

### Files added or changed by Gate 0

| Path | Change |
| --- | --- |
| `test/features/password_manager/data/services/vault_kdbx_service_test.dart` | added `merge feasibility` group (T001–T004), 18 tests |
| `test/features/password_manager/data/services/google_drive_api_service_test.dart` | new, `conditional update` group (T005), 10 tests |
| `test/features/password_manager/data/services/database_writer_inventory_test.dart` | new, `inventory baseline` groups (T007), 13 tests |
| `test/features/password_manager/data/services/safe_vault_file_writer_harness_schema_test.dart` | new, harness/artifact schema (T006), **30** tests (`harness schema` 17 + `harness platform status` 13). The 2026-08-14 transcript above records `+15`; the file has been unchanged since it landed in `80b796b`, where it measures 30 |
| `pubspec.yaml` | declared `xml: ^6.6.1` (already resolved transitively at that exact version via `kdbx`) |
| `specs/008-per-field-conflict-resolution/feasibility-report.md` | this file |

`lib/` has **zero** changes, as required by the Gate 0 scope. `pubspec.yaml` is
the single non-test change: reading the KDBX constructs `kdbx 2.4.2` does not
model (entry colors' RGB value, entry AutoType) goes through `XmlElement`, so
the package must be declared rather than used transitively.

## Status vocabulary

| Status | Meaning | Feature flag |
| --- | --- | --- |
| `not-run` | Harness/test not executed on named target | disabled |
| `passed` | Named target artifact satisfies schema and assertions | may enable that target only |
| `failed` | Harness ran and any required assertion failed | disabled |
| `disabled` | Target intentionally unsupported or blocked | disabled |

## Gate 0 verdict

**CLOSED 2026-08-21.** T009 passed: 36 tests green and the mutation check at
exit 0, 0 survivors (PR #65), re-verified on `main` and accepted by the PM.
The text below is the historical record of why the gate stayed open until then.

**OPEN (2026-08-15 – 2026-08-21). The 2026-08-15 close is reverted.** T001–T008 have executed evidence, and
T005 was genuinely closed by the live-network re-spike recorded below. Gate 0
nonetheless does not close, for three reasons established by the 2026-08-15
review:

1. **The exit bar was rewritten in the commit that declared it met.** Item 7 of
   the Gate 0 spike list changed from *"prove server-enforced Drive conditional
   upload"* to *"measure which optional concurrency capabilities the backend
   offers; a negative measurement is a valid Gate 0 result"*. That is a
   legitimate **proposal**, and it is probably the right one — but it is not a
   derivation, and a criterion cannot be satisfied by the act of being written.
2. **The replacement mechanism is `not-run`.** The concurrency question was not
   resolved; it moved from "measured absent" to "substituted by an unvalidated
   cycle". By this report's own safety rule — `not-run`, `failed` or `disabled`
   never enables a feature — an unvalidated substitute cannot close the gate the
   measured absence opened.
3. **Reading the cycle found it non-convergent.** Three defects, each
   independently fatal to termination: no re-anchoring of the expected base on
   retry, a byte comparison with no semantic arbiter, and a tie-break that
   defaulted to "local" and was therefore perspective-dependent. All are now
   corrected in `spec.md`, and none was caught by a test, because none existed.

**B1 is `failed`, not `passed`, and not withdrawn.** Google Drive REST v3 offers
no compare-and-swap on the upload path. That is measured against the real
service, not inferred from documentation. B1 correctly no longer gates the
feature — FR-7 was rewritten around a `get` + `put` cycle needing no
server-enforced precondition. What gates the feature now is proving that cycle
converges: **T009**.

**Gate 0 closes when T009 passes**, and on no other condition. T009 is a
model-level validation — in memory, no network, no filesystem, no KDBX — of the
FR-7 write-verify-converge cycle under adversarial multi-device interleavings.
Its required properties are listed in "T009 — convergence model validation"
below. Every other Gate 0 item already has its evidence.

| # | Finding | Status | Gates the feature? |
| --- | --- | --- | --- |
| **B1** | Drive v3 does not enforce any HTTP precondition on `files.update`. Confirmed live, with byte-level counter-proof. | **`failed`** (measured) | **No.** Spec 008 FR-7 (rewritten 2026-08-15) requires only `get` + `put`. Drive lands in the **Bare** guarantee tier: no CAS, and `versionHistory` **absent** — not measured, therefore not declared (demoted 2026-08-15, see the rows below). Spec 010 category **Ricostruibile**, pending the revisions spike. See "Guarantee by backend category" in `spec.md`. |

The transport was never the obstacle, and the re-spike proved that positively
rather than by assumption: `GoogleDriveApiService.updateFile` calls Drive through
a raw `http.Client` and spreads its header map at the call site
(`lib/features/password_manager/data/services/google_drive_api_service.dart:138-148`,
`_httpClient.patch(uri, headers: {...headers, …}, body: bytes)`). The spike used
the same header-spreading shape and demonstrated that arbitrary headers do reach
Drive and are honoured on the read path.

One further finding is a **risk**, not a blocker, but must be accepted
explicitly before T301:

| # | Risk |
| --- | --- |
| **R1** | Several primitives the full-fidelity adapter needs sit outside the `package:kdbx/kdbx.dart` public export surface (see "Library API surface"). The production adapter will need `implementation_imports` suppressions and is exposed to breakage on any patch release of `kdbx`. |

## Gate 0 summary

| Capability | Status | Evidence/artifact | Blocking note |
| --- | --- | --- | --- |
| KDBX 3 semantic round-trip | `passed` | `merge feasibility T001 KDBX 3` | full canonical manifest parity |
| KDBX 4 semantic round-trip | `passed` | `merge feasibility T001 KDBX 4` | full canonical manifest parity |
| Password+key-file reopen | `passed` | `merge feasibility T002` (4 cases) | semantic only; bytes asserted to differ |
| Full-fidelity one-sided import/mutation | `passed` | `merge feasibility T003` | object-graph mutation, no `VaultSnapshot` rebuild |
| Tombstone inspect/re-emit without `KdbxFile.merge` | `passed` | `merge feasibility T004` (2 tests) | inspect, re-emit and neutralize all round-trip |
| Root UUID lineage check | `passed` | `T004 root group UUID lineage…` | Drive file id proven insufficient |
| UUID integrity validation | `passed` | `T004 pre-diff UUID validation…` (5 tests) | duplicate entry/group, group-entry collision, nil, cross-side kind |
| Entry colors + entry AutoType (constructs the library does not model) | `passed` | `T001 entry colors round-trip…`, `T001 entry AutoType survives…` | read/written through the exported `KdbxNode.node` |
| Drive server-enforced conditional update | **`failed`** | live-network spike 2026-08-15, `tool/drive_conditional_spike.dart` | **B1**, measured. No CAS on Drive v3. **Not blocking** — FR-7 no longer requires it |
| Drive `versionHistory` | **`not-run`** | none — documentation only | **Demoted 2026-08-15.** Previously `passed` on the strength of Drive's documented revisions API. Spec 010's own rules forbid that: *"Documentation alone is not a declaration"* and *"when a behaviour is uncertain, the capability is absent"*. Retention, `keepRevisionForever`, the pinned-revision ceiling and quota impact are all unmeasured. Drive therefore declares `versionHistory` **absent** |
| Drive backend guarantee tier | **`not-run`** | derived from the two rows above | **Bare**, pending the revisions spike: no `conditionalWrite`, no declared `versionHistory`. Spec 010 category **Ricostruibile**, down from Recuperabile. Restored to Versioned/Recuperabile only when a live revisions spike passes |
| Storage-agnostic write-verify-converge cycle — model validation | **`passed`** 2026-08-21 | **T009**, `sync_merge_convergence_model_test.dart` (36 tests) + `tool/mutations/008_t009_convergence.json` (`--check` exit 0, 0 survivors) | **Was the Gate 0 blocker; closed 2026-08-21, PR #65.** **Scope: additions only** — no tombstone, no `fieldDeletionConflict`, no attachment; see §"What T009 does not cover" |
| Deletion convergence — model validation | **executed 2026-08-22, pending PM acceptance** | **T009b**, `sync_merge_deletion_convergence_model_test.dart` (18 tests) + `tool/mutations/008_t009b_deletion_convergence.json` (14 mutations, `--check` exit 0, 0 survivors) | **Separate gate, not a Gate 0 condition.** Structure: tombstone with a clock, not a 2P-Set — see §"T009b — deletion convergence model". Gates deletion/tombstone/attachment work; closes only on PM acceptance |
| Storage-agnostic write-verify-converge cycle — production implementation | `not-run` | FR-7 as corrected 2026-08-15 | implementation + integration tests are T4xx, after Gate 0 |
| Ambiguous transport outcome classification | `passed` | `conditional update` (10 tests) | client-side rules only, fake transport |
| Writer/path inventory reconciled | `passed` | `inventory baseline` (13 tests) | 14 writer files; 6 gaps vs FR-8 |
| Path identity/alias design reviewed | `not-run` | design drafted below | executed in Gate 1 T103/T107 |
| Platform artifact schema recorded | `passed` | `harness schema` (17 tests) | schema only; **no platform evidence** |

Gate 0 closes when **T001–T009** evidence is complete and every unresolved target
platform remains disabled. **That condition is MET as of 2026-08-21**: T001–T008
all have executed evidence, B1 has a measured result, and T009 is `passed`
(36 tests, mutation check exit 0, PR #65). **T201/domain freeze are unblocked.**
No platform is enabled.

## KDBX support matrix

Installed library: `kdbx 2.4.2`. All rows verified by the `merge feasibility`
group unless noted. "Semantic verify" means the canonical manifest compares the
construct across a save/reopen cycle; ciphertext, salts and IVs are never
compared.

| Construct | Read | Import/copy | Mutate | Write/reopen | Semantic verify | Unsupported detector | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
A cell in **"Unsupported detector"** is `passed` only where a detector exists in
the spike **and** a test exercises it. Every other cell is `not-run`, whatever
the round-trip columns say: a construct that round-trips is not a construct
whose malformed variant is detected. `n/a` means no detector is called for.

| Construct | Read | Import/copy | Mutate | Write/reopen | Semantic verify | Unsupported detector | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| root/group/entry UUID + hierarchy/moves | `passed` | `passed` | `passed` | `passed` | `passed` | `passed` | T001, T003, T004 (5 detector tests) |
| sibling order (`groupOrder`/`entryOrder`) | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001 |
| recycle bin (live, re-parented) | `passed` | `passed` | `passed` | `passed` | `passed` | **`not-run`** | T001, T004 |
| permanent tombstones (`DeletedObjects`) | `passed` | `passed` | `passed` | `passed` | `passed` | **`not-run`** | T004 |
| entry history | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001, T003 |
| times (creation/modification/location/expiry/usage) | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001 |
| standard/custom strings + protection + presence | `passed` | `passed` | `passed` | `passed` | `passed` | **`not-run`** | T001, T003 |
| original key spelling (verbatim, case-sensitive) | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001 |
| attachments: exact bytes (sha256), protection, inline flag | `passed` | `passed` | `passed` | `passed` | `passed` | **`not-run`** | T001, T003 |
| tags, override URL | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001 |
| entry colors (fg/bg), RGB **value** | `passed` | `passed` | `passed` | `passed` | `passed` | `not-run` | T001 (`entry colors round-trip…`) |
| entry auto-type (sequence + association) | `passed` | `passed` | `passed` | `passed` | `passed` | `not-run` | T001 (`entry AutoType survives…`) |
| group auto-type flags (`EnableAutoType`, default sequence) | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001 |
| custom data (meta) | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001 |
| custom icons + references | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001 |
| metadata/settings (name, description, recycle-bin settings, history limits) | `passed` | `passed` | `passed` | `passed` | `passed` | n/a | T001 |
| header **major version** | `passed` | n/a | `passed` | `passed` | `passed` | `passed` | T001; T004 `unsupported KDBX major version is rejected…` |
| header cipher/compression | `passed` | n/a | `passed` | `passed` | `passed` | **`not-run`** | T001 |
| KDF parameters (uuid/iterations/memory/parallelism/version, KDBX 4) | `passed` | n/a | `passed` | `passed` | `passed` | **`not-run`** | T001 |
| original credentials (password / password+key file) | `passed` | n/a | n/a | `passed` | `passed` | **`not-run`** | T002 |

Entry colors and entry AutoType are **not** fidelity gaps. `KdbxColor` is opaque
(no RGB accessor, no `==`) and `kdbx 2.4.2` models entry-level AutoType not at
all, but neither fact makes the data unobservable: `KdbxNode.node` is a public
`final XmlElement` (`src/kdbx_object.dart:118`) exported from
`package:kdbx/kdbx.dart`, `ColorNode.set` writes the RGB code straight into it,
and an unmodelled child node is carried through save/reopen untouched. Both are
now read off that node and compared by value in the canonical manifest:
`FG=#FF0000 BG=#00FF00` after a reopen, and the full `<AutoType>` element with
its `DefaultSequence` and its `Association`/`Window`/`KeystrokeSequence`.

Explicitly **excluded** from the canonical manifest because they legitimately
differ between two serializations of the same logical database: KDF salt, master
seed, encryption IV, ciphertext and `HeaderHash`. Comparing them would silently
turn the shortcut criterion into byte-equality, which `spec.md` forbids.

Required UUID evidence includes globally unique, non-nil live UUIDs per side and
object-kind match across sides. Separate failures: duplicate entry, duplicate
group, group-entry collision, nil UUID and cross-side group/entry mismatch — all
five have a passing detector (`_validateSide` / `_crossSideKindMismatch` in the
spike).

### Unsupported-construct detector

Pre-diff, per side, before any session/backup/write/upload:

1. every live root/group/entry UUID is non-nil → else `unsupportedKdbxData`;
2. live group UUIDs unique; live entry UUIDs unique; the two sets disjoint →
   else `unsupportedKdbxData` (duplicate group / duplicate entry / group-entry
   collision are distinct causes);
3. cross-side, any UUID present on both sides must denote the same object kind →
   else `unsupportedKdbxData`;
4. root group UUIDs must be equal → else `wrongLineage` (checked first; Drive
   file id is explicitly not evidence — proven in T004);
5. header major version outside 3.x/4.x → the library itself refuses the file.
   **Exercised** by `T004 unsupported KDBX major version is rejected by the
   library`: a saved fixture with its major version byte-patched to 5 or 9 is
   rejected with `KdbxUnsupportedException`. A version **below** 3 fails
   earlier and differently, with a `RangeError` from the header parser — the
   adapter must therefore not assume a single exception type for "unsupported".

Raw UUIDs and object labels never enter logs or state.

Steps 1–5 are the **whole** detector. Nothing detects a malformed recycle bin,
a malformed tombstone set, a malformed string/protection combination, a
malformed attachment, an unknown cipher or compression id, out-of-range KDF
parameters, or a credential shape the adapter cannot handle. Those rows are
`not-run` in the matrix above and stay `not-run` until a detector and its test
exist. Designing them is Gate 1 work.

### Library API surface (R1)

The public export `package:kdbx/kdbx.dart` is insufficient for a full-fidelity
adapter. Every item below required an `// ignore: implementation_imports`
suppression in the spike and will require the same in `kdbx_merge_adapter.dart`:

| Symbol | Where it lives | Needed for |
| --- | --- | --- |
| `KdbxObjectInternal.forceSetUuid` | `src/kdbx_object.dart` (extension, not exported) | importing a one-sided object while keeping its UUID |
| `KdbxEntryInternal.cloneInto` | `src/kdbx_entry.dart` (extension, not exported) | copying an entry with history across files; authoring history |
| `KdbxHeader` | `src/kdbx_header.dart` (only `KdbxVersion` is exported) | choosing the KDBX 3 vs 4 header/KDF |
| `KdbxColor` | `src/kdbx_xml.dart` (not exported) | **setting** entry colors; reading them needs only the exported `KdbxNode.node` |
| `KdbxBody.deletedObjects` | exported, but annotated `@visibleForTesting` | inspecting/emitting/neutralizing tombstones |

Additional behavioural finding: `KdbxEntry.setString` does **not** push a history
entry while the entry is still dirty from creation. History has to be authored
the way the library authors it internally, via `cloneInto(toHistoryEntry: true)`.
An adapter that assumes automatic history would silently lose revisions.

**`KdbxFile.merge` is never called.** The upstream method carries
`FIXME: THiS iS NOT YET FINISHED, DO NOT USE` (`src/kdbx_file.dart:165`).
Acceptance criterion 3 is enforced by two static-scan tests — one over
`lib/features/password_manager`, `lib/core` and `test/features/password_manager`
(`T004 forbidden KdbxFile.merge is never called`), one over all of `lib/`
(`inventory baseline KdbxFile.merge is absent from every production source`).
Both currently report zero occurrences. Both patterns now require the receiver
token to contain `kdbx`; the previous bare `merge\s*\(` matched *any* `merge(`
in the tree — a false positive waiting for the first unrelated `merge` method
(this repo already has `VaultKdbxService.mergeEntries`). The trade is explicit:
a `KdbxFile` held in a variable whose name contains no `kdbx` is not caught.

## Drive conditional/recovery evidence

**Honesty statement.** The T005 tests run against an in-process fake HTTP
transport (`package:http/testing.dart` `MockClient`). They prove the client-side
contract. They do **not** and cannot prove that Google's servers enforce a
precondition. No row below is marked `passed` on the strength of a fake server.
The live-network evidence that settled the question is in
"B1 live-network re-spike (2026-08-15)" further down; the rows in this section
were written before it and are now annotated with the measured result.

Documentation review performed as part of T005:

- Drive REST v3 `files.update` reference documents **no** `If-Match` header, no
  precondition query parameter and no `412` response;
- the Drive v3 `File` resource has **no `etag`** field (v2 had one; v3 dropped
  it). It exposes `version` (monotonic) and `headRevisionId`, neither documented
  as a write precondition.

That is the **entire** basis for B1: the documentation, and the shape of the v3
resource. It is **not** a client-library limitation. This project does not
depend on `googleapis` at all — the package is absent from `pubspec.yaml`,
absent from `pubspec.lock` and absent from `.dart_tool/package_config.json`; it
exists only in the machine-wide pub cache as a leftover of an unrelated
project. Drive is called directly:

```dart
// google_drive_api_service.dart:138-148 — raw http.Client, spreadable headers
final response = await _authedRequest(
  (headers) => _httpClient.patch(
    uri,
    headers: {...headers, 'Content-Type': 'application/octet-stream'},
    body: bytes,
  ),
);
```

So the client **can** send `If-Match`, or any other header, today. Sending it
by hand has **never been tested** — not against the fake transport, not against
Drive — and it is the only remaining candidate mechanism. Closing B1 means
observing a real server response to it.

| Item | Recorded value/status |
| --- | --- |
| Concurrency token selected | **`failed`** — measured 2026-08-15: no server-enforced token exists on Drive v3. **No longer required**; FR-7 declares the token optional |
| Metadata fields/headers | **`failed`** — `If-Match`, `If-None-Match` and `If-Unmodified-Since` were sent live and all were ignored on the upload path; no `ETag` header and no `etag` field is returned. The transport is proven adequate by the `Range` → `206` counter-probe |
| Conditional rejection proven not applied | `failed` against real Drive (no `412` is producible); `passed` against fake transport (`conditional rejection proves the write was NOT applied`). Retained because the client rule stays correct for future CAS adapters |
| Storage-agnostic read-back verification (FR-7 step 5) | `not-run` — replaces the conditional token as the primary safety mechanism; implemented and tested in T4xx |
| Timeout-after-dispatch classified ambiguous | `passed` (client-side rule) — `timeout after dispatch is ambiguous even though it APPLIED` / `… when it did NOT apply` / `the two ambiguous cases are indistinguishable to the client` |
| Persisted `localCommittedChecksum` recovery guard | `not-run` — design only, implemented in T404/T407 |
| Restart local mismatch returns `staleRecoveryLocal` before remote call/mutation | `not-run` — T407/T409 |
| Matching-local remote triage: merged/old/third state | `passed` as a pure decision function (`post-dispatch triage distinguishes applied from not-applied`) |
| Current production gap | `passed` — `production updateFile currently sends no precondition` (also asserts the raw-client call shape, i.e. that a precondition header *could* be sent) and `DriveRemoteFile carries no concurrency token` (asserts the model's four declared fields against the source; the previous `props`-based assertion proved nothing and was replaced) |
| Evidence command/artifact | `flutter test --no-pub …/google_drive_api_service_test.dart --plain-name "conditional update"` → `+10` |

### Proven outcome rules (client side)

| Observation | Classification | Mandated action |
| --- | --- | --- |
| HTTP 2xx | `appliedDefinite` | refetch metadata, verify remote checksum equals merged checksum, then finalize mapping |
| HTTP 412 (precondition failed) | `rejectedNotApplied` | certain not applied; refetch and surface a new conflict. **Never** re-send against the freshly observed token — the spike shows a blind retry succeeds and destroys the concurrent edit the rejection just protected |
| any other status | `ambiguous` | treat as unresolved |
| transport exception after dispatch (`ClientException`, `TimeoutException`) | `ambiguous` | persist `outcomeAmbiguous`; never retry blindly, never mark synced or failed |

Post-ambiguity remote triage (FR-10 steps 5–7), proven as a decision function:
remote checksum == merged → finalize mapping; == expected old → conditional retry
is safe; anything else → retain local merged file + dated backup and open a new
conflict.

### Required before B1 can clear

Superseded by the live-network re-spike below. Recorded verbatim as the standard
that was applied: option 1 was executed, and it returned a negative result.

One of:

1. a live-network spike against a throwaway Drive account, sending `If-Match`
   through the existing raw `http.Client` and showing a `412` on stale state,
   recorded as a dated artifact with request/response transcripts. This is the
   only untested path left and therefore the first thing to try; or
2. a documented Drive v3 precondition mechanism; or
3. an accepted design change (for example: a lock/marker file, or a
   resumable-upload session bound to an observed generation) that provides
   server-enforced serialization.

## B1 live-network re-spike (2026-08-15)

**Result: B1 confirmed. Google Drive REST v3 enforces no precondition on the
upload path. Measured, not assumed.**

| Item | Value |
| --- | --- |
| Artifact | `tool/drive_conditional_spike.dart` (commit `6354da0`) |
| Command | `DRIVE_SPIKE_TOKEN='<redacted>' dart run tool/drive_conditional_spike.dart` |
| Date | 2026-08-15 |
| Target | live `https://www.googleapis.com/drive/v3` + `/upload/drive/v3`, `uploadType=media` |
| Account | throwaway Google account, OAuth Playground token, scope `https://www.googleapis.com/auth/drive` |
| Subject | one spike-created file of random bytes, deleted in `finally`. No `.kdbx`, no vault data, no pre-existing file touched |
| `lib/` changes | none |

No token, file ID, account identifier or response body is reproduced in this
report. The spike never prints the token, not even truncated.

**Method — why a `200` is evidence here.** Every probe re-downloads the object
after the write and compares the bytes to the payload it sent. A `200` counts
only when the remote bytes actually changed. Without that counter-proof a `200`
would be indistinguishable from a silently discarded request.

### Decisive probes — all five wrote through

| # | Probe | Expected if CAS existed | Observed | Remote bytes overwritten |
| --- | --- | --- | --- | --- |
| 1 | `If-Match: "<invented value>"` | `412` | **`200`** | **yes** |
| 2 | `If-Match: "<stale version>"` | `412` | **`200`** | **yes** |
| 3 | `If-Match: <stale ETag-shaped value>` | `412` | **`200`** | **yes** |
| 4 | `If-Match: "<stale headRevisionId>"` | `412` | **`200`** | **yes** |
| 5 | `If-None-Match: *` on an existing resource | `412` | **`200`** | **yes** |
| 6 | `If-Unmodified-Since: <past date>` | `412` | **`200`** | **yes** |

Stale values in probes 2–4 are genuinely stale: they were read before the
earlier writes in the same run, not fabricated.

### Counter-probes — every alternative explanation excluded

| Probe | Observed | What it rules out |
| --- | --- | --- |
| `Range` header on the read path | **`206`** | Arbitrary headers **do reach** Drive and **are interpreted**. The negative result is not a limitation of our transport, our client or the header-spreading call shape. |
| `If-Match` with deliberately malformed syntax | **`200`**, not even a `400` | Drive does not parse conditional headers on the upload path at all. It is not parsing-then-ignoring; there is no precondition machinery to address. |
| `If-Match` stale on `GET` metadata | **`200`** | No precondition on the read path either. |
| JSON `etag` field on the `File` resource | **absent** | Confirms v3 dropped the v2 `etag`. |
| HTTP `ETag` response header | **absent** | No server-supplied validator to build a precondition from. |
| `version`, `headRevisionId` | present, but writes succeed against stale values | Both are **descriptive only**, not write preconditions. |

### Verdict

Google Drive offers **no compare-and-swap**. Options 2 and 3 of "Required before
B1 can clear" were not pursued: option 2 is refuted by the same measurement, and
option 3 — a client-side lock or marker file — cannot provide server-enforced
serialization on a backend with no atomic create-if-absent, so it would trade a
measured limitation for an unmeasured one.

### This no longer blocks the feature

Spec 008 FR-7 was rewritten on 2026-08-15 around a **write-verify-converge**
cycle expressed in `get` + `put` only, with revalidation under the per-database
mutex immediately before the write, and a mandatory read-back afterwards. Its
founding invariant — locally merged state is never discarded until the remote is
proven to contain it — makes a lost update **detected and non-destructive**
without any server precondition.

**Corrected 2026-08-15.** This section originally placed Drive in the
**Versioned** tier on the strength of a documented revisions API. That was a
declaration from documentation, which spec 010 forbids in the same breath it
defines the taxonomy: *"A capability is declared only when a spike has observed
the behaviour against the real service. Documentation alone is not a
declaration"*, and *"when a behaviour is uncertain, the capability is absent"*.
Nothing about Drive's revisions was measured — not retention, not
`keepRevisionForever`, not the ceiling on pinned revisions, not quota impact —
and this spike did not probe them at all.

Drive therefore declares `versionHistory` **absent** and lands in the **Bare**
tier of `spec.md` §"Guarantee by backend category": `get` + `put` only. Spec 010
category **Ricostruibile**. This is a demotion from what the 2026-08-15 pass
recorded, and it is the conservative direction the rules mandate — an absent
capability costs a guarantee tier, a wrongly present one costs user data.

The demotion is **reversible and cheap to reverse**: a live revisions spike per
010 FR-5, measuring retention, `keepRevisionForever`, the pinning ceiling and
quota impact, restores `versionHistory`, the Versioned tier and the
**Recuperabile** category. Until it runs, no user-facing promise may depend on
the server holding a previous revision.

## Writer inventory evidence

Baseline inventory is `plan.md` section "Complete database/path writer inventory"
and `spec.md` FR-8. T007 re-derives it by scanning **all of `lib/`** for
`writeAsBytes`, `writeAsString`, `openWrite`, `rename`, `copy`, `delete` and
`create` **and their `*Sync` variants**, excluding non-filesystem receivers
(`Clipboard*` including `sl<ClipboardGuard>().copy(`, `secureStorage.delete`,
`Kdbx*.create(`). The result is frozen in `_baseline` inside
`database_writer_inventory_test.dart`; any new writer fails the test.

The scanner was hardened after review (see "Post-review corrections"): it
previously scanned only two subtrees, ignored every `*Sync` form, and skipped a
whole source line when anything clipboard-shaped appeared on it. Non-filesystem
receivers are now **scrubbed out of the line** rather than used to discard it,
so a line holding both a clipboard call and a real write still reports the
write. `the scanner itself catches sync writers and mixed lines` asserts all of
this directly. Widening the scan to all of `lib/` produced **no** new writer:
the 14-file result below is unchanged, and now provably complete for `lib/`.

### Complete scan result — 14 files

| # | File:line | Operations | In FR-8? | Class |
| --- | --- | --- | --- | --- |
| 1 | `data/services/vault_kdbx_service.dart:349,359,361,363,373,382,397,400,402,406,483,812` | writeAsBytes, rename, delete | yes | **database** |
| 2 | `data/services/database_import_service.dart:221,231,241,251,260,263,265,269,288,295,299,300,303,324,379,416,462,504,510,512,513,517,519` | writeAsBytes, rename, delete | yes | **database** + key file |
| 3 | `data/services/database_sync_orchestrator.dart:178,254,291,372` | writeAsBytes, copy | yes (understated) | **database** |
| 4 | `presentation/coordinators/vault_session_coordinator.dart:217,226,312,380` | rename, copy | yes | **database** |
| 5 | `presentation/screens/database_selection_screen.dart:161` | copy | yes | **database** export |
| 6 | `presentation/screens/vault/vault_shared.part.dart:257,294` | copy | **no — FR-8 names the wrong file** | **database** export + key-file export |
| 7 | `lib/core/utils/mobile_file_storage.dart:47,141,149` | writeAsBytes, delete, create | **no** | **database** (managed) + key file |
| 8 | `presentation/widgets/internal_key_file_manager_dialog.dart:153` | copy | **no** | key file |
| 9 | `presentation/widgets/internal_key_file_manager_sheet.dart:159` | copy | **no** | key file |
| 10 | `data/services/desktop_browser_autofill_cache.dart:582,585,587,589,599` | create, writeAsString, delete, rename | **no** | non-database cache |
| 11 | `data/datasources/database_registry_local_data_source.dart:52,77` | writeAsString, create | no | non-database state |
| 12 | `data/datasources/database_security_local_data_source.dart:78,85` | writeAsString, create | no | non-database state |
| 13 | `data/datasources/local_data_source.dart:86,93` | writeAsString, create | no | non-database state |
| 14 | `data/datasources/sync_metadata_data_source.dart:120,127` | writeAsString, create | no | non-database state |

### Gaps found against FR-8 — the T007 deliverable

| Gap | Finding | Consequence |
| --- | --- | --- |
| **GAP 1** | `lib/core/utils/mobile_file_storage.dart` is an unlisted database-path writer. It is used by `DatabaseImportService` for managed databases and by both key-file manager widgets. FR-8 does not mention it. | A mutex added only to the FR-8 list leaves a bypass. |
| **GAP 2** | FR-8 names `vault_navigation.part.dart::_exportCurrentDatabase`. That file performs **no** direct file mutation. The body is `_exportDatabaseBackup` in `vault_shared.part.dart:223`, reached from **three** call sites (`vault_navigation.part.dart:345`, `vault_sync.part.dart:48`, `vault_backups.part.dart:40`). | Fixing the file FR-8 names would miss the real writer and two of three entry points. |
| **GAP 3** | `internal_key_file_manager_dialog.dart:153` and `internal_key_file_manager_sheet.dart:159` copy key files directly from presentation. Not in FR-8. | T102 ("remove presentation database file writes") is under-scoped. |
| **GAP 4** | `DatabaseSyncOrchestrator` has **three** `writeAsBytes` replacement sites (178, 254, 291) and **four** `_backupFile` call sites, not the single `syncNow` path FR-8 implies. | Each site needs the mutex and the FR-9 safe-writer independently. |
| **GAP 5** | `domain/usecases/create_database_usecase.dart:78` constructs and serializes a `KdbxFile` (`KdbxFormat().create(...)`, `kdbx.save()`) inside the **domain** layer. It writes through `DatabaseFileRepository`, so it is not a raw filesystem writer, but it owns KDBX serialization in the wrong layer. | Clean-Architecture violation; must still take the same mutex as any other creator. |
| **GAP 6** | `database_import_service.dart:462` writes a separate web-path copy (`File(webPath).writeAsBytes(...)`) not described in FR-8. | Another database-path write outside the described flows. |
| **CORRECTION** | FR-8 lists `DatabaseSessionCoordinator … removeRecentDatabase file delete` as a direct presentation write. It is **not**: it calls `databaseFileRepository.deleteFile(...)` (`database_session_coordinator.dart:689`), implemented by `DatabaseImportService.deleteFile` (`:413`). | FR-8 overstates this one; no refactor needed there. |

### Reconciliation checklist

| Check | Status | Evidence |
| --- | --- | --- |
| Vault KDBX mutators + credential rollback covered | `passed` | row 1; `inventory baseline every filesystem writer is accounted for` |
| Sync replacement/backup covered | `passed` | row 3 + GAP 4 |
| Import/stage/replace/create/rollback covered | `passed` | row 2 + GAP 6 |
| Settings/credential/database rename covered | `passed` | row 4 |
| Database create/delete/export covered | `passed` | rows 5, 6, 7 + GAP 5 + CORRECTION |
| Presentation direct database writes removed/forbidden | `passed` (2026-08-22, Gate 1 T102) | all 5 presentation writers now delegate to `DatabaseFileRepository.copyFile/renameFile`; guarded by `T102 architecture presentation layer performs no direct file mutation` |
| Alias and deterministic multi-path lock tests enumerated | `passed` | executed by Gate 1 T107: `database_path_identity_resolver_test.dart` + `database_path_mutex_test.dart` (alias matrix, inverse concurrent renames, global fallback) |
| No shared path mutex shipped by Gate 0 | `passed` | `no shared database path mutex exists yet` |

### Gate 1 progress — T101/T102 (2026-08-22)

**T101 — inventory frozen before the mutex.** The T007 scan result above was
re-verified against the code: **no divergence found** — every writer the
report lists existed at the listed operations, and no unlisted writer
appeared. The freeze is now executable at two granularities in
`database_writer_inventory_test.dart`:

- `inventory baseline` (unchanged mechanism): file → operation kinds, all of
  `lib/` + `tool/`;
- `T101 frozen writer inventory` (new): exact **mutation call-site counts**
  per database-writer file (`vault_kdbx_service` 3/6/3
  writeAsBytes/rename/delete, `database_import_service` 4/12/8/1
  writeAsBytes/rename/delete/copy, `database_sync_orchestrator` 3/1
  writeAsBytes/copy, `mobile_file_storage` 1/1/1
  writeAsBytes/delete/create), plus a by-name freeze of the T101 entry
  points (credential transaction, `syncNow`/`_backupFile`, import
  stage/commit/finalize/rollback/create, session-coordinator
  create/import/remove, `updateDatabaseSettings`/`_writeDatedPreRekeyBackup`,
  `_exportDatabaseBackup`). A new call site in an already-listed file now
  fails the freeze, which the kind-level baseline alone could not detect.

**T102 — presentation database file writes removed.** The five presentation
writers in the 14-file table (rows 4, 5, 6, 8, 9) no longer perform any
direct `dart:io` mutation. `DatabaseFileRepository` (domain port) gained
`copyFile`/`renameFile`, implemented by `DatabaseImportService` (data):

- `vault_session_coordinator.dart` — settings rename, both rollback renames
  and the dated pre-rekey backup copy go through the injected port;
- `database_selection_screen.dart`, `vault_shared.part.dart` (database and
  key-file export), `internal_key_file_manager_dialog.dart`/`_sheet.dart`
  (key-file export) resolve the port via DI for the copy.

Pure refactor: flows, error handling and UX are unchanged. Enforcement is the
`T102 architecture` group — the presentation layer is pinned at **zero**
direct file mutations, kill-checked by temporarily adding a
`File(...).writeAsBytes` to a presentation file (baseline and architecture
tests both failed, then the injection was removed). The scan-result table
above is retained as T007 evidence; post-T102 the direct-writer set is the
9 data/core rows (1–3, 7, 10–14) with row 2 additionally holding the `copy`
port implementation.

Still open for Gate 1: T103–T111 (path identity, mutex, routing, rename
transaction, collision-safe backup, safe writer, failure tests, platform
artifacts). GAP 1 (`MobileFileStorage`) and GAP 5 (domain-layer KDBX
serialization) remain unresolved by design at this step — they are mutex
routing (T104/T105) concerns, not presentation writes.

## Path identity design (input to Gate 1 T103/T104)

Design recorded; **executed by Gate 1 T103/T104** (2026-08-22) in
`lib/features/password_manager/data/services/database_path_identity_resolver.dart`
and `database_path_mutex.dart`. The per-platform decision left open below was
resolved by replacing the platform assumption with a **runtime probe**: case
sensitivity is probed per volume via `FileSystemEntity.identical` against the
case-flipped spelling of the deepest existing prefix (decisive both ways for
existing paths), and hard-link/file identity uses pairwise
`FileSystemEntity.identical` — the portable-API gap in step 5 turned out not
to exist. `identityConfidence` is the `proven` flag; it is `false` (coarse
global-lock fallback) when the target's parent directory does not exist yet or
the case probe is inconclusive (a path with no letters). A dangling-symlink
leaf takes the identity of its target, since writing through the link creates
the target. Writer routing through the mutex is T105 and has not happened.

Canonicalization pipeline for a database path, in order:

1. resolve to absolute against the process working directory;
2. normalize separators and collapse `.` / `..` textually;
3. `File.resolveSymbolicLinksSync()` when the path exists; when the target does
   not exist, resolve the **nearest existing ancestor** and re-append the
   remaining segments, so a not-yet-created target is still comparable;
4. apply platform case rules: case-insensitive comparison on Windows and on
   default macOS APFS/HFS+ volumes, case-sensitive on Linux, Android and
   case-sensitive macOS volumes. Volume case sensitivity is **not** reliably
   detectable from Dart;
5. file identity / hard-link detection has no portable Dart API (`FileStat`
   exposes no inode or file id).

Consequence, per FR-8: because steps 4 and 5 cannot be proven per platform from
Dart alone, the resolver must expose an explicit
`identityConfidence: proven | unproven`. On `unproven`, the platform falls back
to a **single coarse global database lock** rather than per-path locking.
Gate 1 T103 must decide this per platform and record it here.

Multi-path acquisition (rename, replace, export where source and destination may
alias): canonicalize every participating path, deduplicate, sort by the canonical
string, then acquire in that deterministic order. This is what makes inverse
concurrent renames deadlock-free.

Alias cases Gate 1 T107 must cover: relative vs absolute; mixed separators;
embedded `.`/`..`; symlinked file; symlinked parent directory; case aliases on a
case-insensitive volume; hard links where the platform supports them;
non-existing target with existing parent; `source == target`; two concurrent
renames in inverse order.

## Platform artifact schema

Each Gate 1 artifact is target-generated JSON plus raw harness log. The schema
below is machine-checked by
`test/features/password_manager/data/services/safe_vault_file_writer_harness_schema_test.dart`,
which also proves the validator rejects a missing field, an unknown platform, a
missing case, a failed case inside a `passed` artifact, a `targetState` that is
neither `old` nor `new`, a `passed` artifact claiming no atomic replace or
backup overwrite, and an artifact without commit/command/log provenance.

Required JSON fields:

```json
{
  "schemaVersion": 1,
  "platform": "android|ios|macos|windows|linux",
  "osVersion": "...",
  "deviceOrRunner": "...",
  "filesystem": "...",
  "flutterVersion": "...",
  "dartVersion": "...",
  "commit": "...",
  "command": "...",
  "startedAtUtc": "...",
  "completedAtUtc": "...",
  "status": "passed|failed",
  "flushSupported": true,
  "directorySyncSupported": true,
  "atomicReplaceOverExisting": true,
  "backupNoOverwrite": true,
  "cases": [
    {
      "name": "...",
      "injectedFailurePhase": "...",
      "oldChecksum": "...",
      "candidateChecksum": "...",
      "finalChecksum": "...",
      "backupChecksum": "...",
      "targetState": "old|new",
      "passed": true
    }
  ],
  "logPath": "..."
}
```

Required cases — exactly these eight names, asserted by the schema test:

| Case name | Injected failure | Required outcome |
| --- | --- | --- |
| `backup_same_microsecond_collision` | clock frozen to one microsecond | every backup survives with unique content |
| `backup_preexisting_name_collision` | final backup name precreated | existing backup never truncated or replaced; retry with new suffix |
| `backup_create_failure` | exclusive-create fails | no target write attempted |
| `backup_write_flush_verify_failure` | write/flush/verify fails | no target write attempted |
| `target_short_write_failure` | partial write to temp | target left `old` |
| `target_flush_failure` | flush/fsync fails | target left `old` |
| `target_rename_failure` | atomic replace fails | target left `old` |
| `interruption_before_and_after_replace_dispatch` | process killed either side of the replace | target left `old` or full `new`, never missing or truncated |

Enablement rule, machine-checked: an artifact enables **at most its own
platform** (`host platform never qualifies another target`); a `failed` artifact
enables nothing; a schema-invalid artifact enables nothing.

## Platform evidence matrix

Gate 0 initializes rows. Gate 1 T111 updates status/artifact. One row never
qualifies another target. macOS host unit tests executed for T001–T007 are
**not** atomicity evidence and do **not** qualify the macOS row.

| Platform | Status | Feature enabled | Required artifact | Command/runtime |
| --- | --- | --- | --- | --- |
| Android | `passed` | no | `build/safety-evidence/android/safe-vault-writer.json` + log | Android 16 (API 36) emulator, arm64; 8/8 cases passed; metadata below |
| iOS | `passed` | no | `build/safety-evidence/ios/safe-vault-writer.json` + device log | Physical iPhone 16 Pro / iOS 26.6 / APFS; schema v1; 8/8 required cases passed; metadata below |
| macOS | `passed` | no | `build/safety-evidence/macos/safe-vault-writer.json` + log | `tool/run_safety_harness.sh -H`; macOS 26.6.1 host / APFS; 8/8 cases passed; metadata below |
| Windows | `passed` | no | Actions artifact `t111-safe-vault-writer-windows` | PR #127 run `32713786823`; native `windows-2022` / NTFS; 8/8 cases passed; metadata below |
| Linux | `passed` | no | Actions artifact `t111-safe-vault-writer-linux` | PR #127 run `32713786823`; native `ubuntu-latest` / ext4; 8/8 cases passed; metadata below |

A passing row records platform-qualified filesystem evidence; it does not switch
on unfinished product code. `commit` still returns `platformDisabled` while the
later implementation gates remain open, so every feature flag above remains
`no`.

### T111 artifact metadata — 2026-08-24

- **Android — `passed`, 2026-08-25.** Schema 1; artifact and log under the
  ignored `build/safety-evidence/android/`; commit
  `14b3a87b22135b245b73f2f56e7c6fa0f09ed41e`; sanitized command
  `tool/run_safety_harness.sh -d <emulator>`; Android 16 (API 36) emulator,
  arm64; Flutter 3.44.8 / Dart 3.12.2; run date 2026-08-25 (one day after the
  shared header above, which reflects the other four platforms only); status
  `passed`; shared-schema
  validation returned 0 errors; all 8 exact required cases passed.
  Capabilities: `atomicReplaceOverExisting=true`, `backupNoOverwrite=true`,
  `flushSupported=true`, `directorySyncSupported=false`. Directory sync is a
  measured unsupported capability and remains best-effort; it is not claimed
  as `true`.
- **iOS — `passed`.** Schema 1; artifact and log under the ignored
  `build/safety-evidence/ios/`; commit
  `98467436cd9447eb4f45d5eef316d57faaba0058`; sanitized command
  `tool/run_safety_harness.sh -d <physical-device>`; physical iPhone 16 Pro;
  iOS 26.6 build 23G71; APFS; Flutter 3.44.8 / Dart 3.12.2; UTC
  `2026-08-24T15:41:03.508671Z`–`2026-08-24T15:41:04.807278Z`; status
  `passed`; shared-schema validation returned 0 errors; all 8 exact required
  cases passed. Capabilities: `atomicReplaceOverExisting=true`,
  `backupNoOverwrite=true`, `flushSupported=true`,
  `directorySyncSupported=false`. Directory sync is a measured unsupported
  capability and remains best-effort; it is not claimed as `true`. Tester
  confirmed the harness, shared schema and safe writer are unchanged between
  the artifact commit and current head.
- **macOS — `passed`.** Schema 1; artifact and log under the ignored
  `build/safety-evidence/macos/`; commit
  `118098b5026c6a53c73c3a2e4db277379abbd91b`; command
  `tool/run_safety_harness.sh -H`; runner `host`; macOS 26.6.1 build 25G76;
  APFS; Flutter 3.44.8 / Dart 3.12.2; UTC
  `2026-08-24T10:33:19.701779Z`–`2026-08-24T10:33:19.917005Z`; status
  `passed`; 8/8 cases. Capabilities:
  `atomicReplaceOverExisting=true`, `backupNoOverwrite=true`,
  `flushSupported=true`, `directorySyncSupported=false`. Host evidence
  qualifies macOS only.
- **Windows — `passed`, CI evidence verified.** PR #127 Actions run
  `32713786823`, artifact id `9515181562`, commit
  `746a4fe149b707e4ac43de49d7bc50d28e81214f`; Windows Server 2022 build
  20348 / NTFS; Flutter 3.44.8 / Dart 3.12.2; status `passed`; 8/8 cases.
  Capabilities: `atomicReplaceOverExisting=true`, `backupNoOverwrite=true`,
  `flushSupported=true`, `directorySyncSupported=false`.
- **Linux — `passed`, CI evidence verified.** Same Actions run, artifact id
  `9515143953`, same commit; `ubuntu-latest`, Linux 6.17.0-1022-azure / ext4;
  Flutter 3.44.8 / Dart 3.12.2; status `passed`; 8/8 cases. Capabilities:
  `atomicReplaceOverExisting=true`, `backupNoOverwrite=true`,
  `flushSupported=true`, `directorySyncSupported=false`.

Artifacts and transcripts remain untracked: local output is under ignored
`build/`, and CI JSON stays attached to its Actions run. Android, iOS, macOS,
Windows and Linux are all `passed`; T111 platform evidence is complete.

## Model corrections from spike

Input to T201. **T201 must not start while Gate 0 is open.**

This line previously read *"T201 must not start while B1 is open"* while the
sign-off table simultaneously declared Gate 0 closed and T201 startable — the two
statements contradicted each other inside one file. Both are now resolved the
same way and in one direction: **B1 is closed** (measured `failed`, and correctly
non-blocking), **Gate 0 is open** on T009, and T201 is blocked by Gate 0, not by
B1.

- **chosen full-fidelity adapter mechanism**: opened `KdbxFile` object graph,
  mutated in place, serialized with `save()`, reopened with the original
  `Credentials` and validated against a canonical semantic manifest before the
  target is replaced. `VaultSnapshot` is never used as a write model.
  `KdbxFile.merge` is never called. Proven by T003.
- **unsupported KDBX constructs/detection**: five-step pre-diff validator above,
  returning `wrongLineage` or `unsupportedKdbxData` before any session, backup,
  local write or upload. All five UUID failure modes have passing detectors, and
  the header-version refusal is exercised. Every other construct has **no**
  detector yet — see the `not-run` cells in the matrix.
- **fidelity gaps to carry into the model**: **none from the KDBX side.** Entry
  colors and entry auto-type were previously recorded as gaps; both round-trip
  by value through the exported `KdbxNode.node`, so the adapter does not need to
  refuse databases carrying them. The adapter must read and write them through
  the entry's XML node, because the typed API does not expose them.
- **chosen Drive token**: **none exists**. `failed`, measured 2026-08-15.
  `DriveRemoteFile` has no concurrency-token field, and none can be added,
  because Drive enforces nothing. `md5Checksum` is content-derived and cannot
  serialize writes on its own (two generations with identical content share it)
  — but it **is** sufficient as the FR-7 step-5 read-back comparator, which is
  what the rewritten FR-7 actually needs. **T401 is respecified in `tasks.md`**
  as "implement the write-verify-converge cycle", not "select a token". The
  2026-08-15 pass asserted this respecification had happened while
  `tasks.md:163-164` still read *"add Gate 0-proven concurrency token and
  server-enforced conditional `updateFile`"*; the report declared a change that
  had not been made. That is the same class of error the 2026-08-14 review
  corrected under C1, and it is corrected here by actually editing `tasks.md`.
  T401 remains **blocked by Gate 0** in any case, like every other post-Gate-0
  task.
- **platform path identity/global-lock fallback**: design recorded above;
  `identityConfidence` flag with coarse global lock fallback. Per-platform
  decision resolved 2026-08-22 by T103: a per-volume **runtime probe** instead
  of a per-platform table — see "Path identity design" for the mechanism and
  the unproven cases.
- **domain model corrections**: add an explicit `identityConfidence` concept for
  the mutex layer, and an `unsupportedKdbxConstruct` reason code distinct from
  the UUID-integrity `unsupportedKdbxData`, so a future refusal is reportable
  without leaking object labels. No construct requires that refusal today.

## Assumptions explicitly NOT converted to evidence

Listed so no reader mistakes them for results:

1. ~~Google Drive server-side enforcement of any precondition — **assumed
   absent**, never tested live.~~ **Resolved 2026-08-15**: tested live and
   measured absent. This is now evidence (`failed`), not an assumption. See
   "B1 live-network re-spike".
1a. Drive revisions API — **the whole capability, not only its details.**
   Retention window, `keepRevisionForever` semantics, ceiling on pinned
   revisions and quota impact are all unmeasured, and so is the basic claim that
   an overwritten revision is retrievable at all. `versionHistory` was briefly
   recorded as present for Drive from its documented API; that was a declaration
   from documentation and is withdrawn (2026-08-15). Drive declares
   `versionHistory` **absent** until a live spike per 010 FR-5 measures it.
   `not-run`.
1c. **The FR-7 write-verify-converge cycle converges.** Argued in prose,
   corrected twice on review, executed by nothing. This is the Gate 0 blocker
   and the subject of T009. Until it passes, "detected but never destructive" is
   a design intent, not a result.
1b. Every non-Drive provider's capabilities. Nothing was measured. Spec 010
   lists them as **to verify** and requires a per-adapter spike.
2. Detection of malformed non-UUID constructs — recycle bin, tombstones,
   strings/protection, attachments, cipher/compression, KDF parameters,
   credential shapes. Round-trip evidence exists for all of them; **detector**
   evidence does not. All `not-run`.
3. Atomicity, flush and rename semantics on **every** platform including macOS —
   nothing was executed; all rows `not-run`.
4. ~~Path canonicalization and case/hard-link behaviour — designed, not
   executed.~~ **Resolved 2026-08-22**: executed by T103/T107 on the host
   filesystems the suite runs on (macOS + ubuntu CI); other platforms get
   their evidence with the Gate 1 T111 harness runs.
5. Behaviour of the merge adapter under a `kdbx` patch upgrade — the spike
   depends on non-exported symbols; no upper bound is pinned in `pubspec.yaml`
   beyond `^2.4.2`. R1.
6. Whether the `<AutoType>` node survives a round-trip performed by **another**
   KeePass implementation. Proven here for `kdbx 2.4.2` only.

## Convergence-cycle review (2026-08-15)

An independent review of commits `434d0d3` (FR-7 rewrite) and `281a1f0` (spec 010
draft) returned **not validated, rework**. It accepted the direction — a
storage-agnostic cycle is the right response to a measured absence of CAS, FR-9
backup-failure promoted to a hard stop is correct reasoning, and the crash window
between steps 4 and 5 is well covered — and rejected the cycle as written,
because it does not converge.

Every defect below was found by reading a document. None was found by a test,
because no test covered any of it. That is the argument for T009, and it is why
Gate 0 reopens rather than closing with a note.

| # | Severity | Defect | Correction |
| --- | --- | --- | --- |
| **C1** | blocking | The expected base was recorded at step 1 and never re-anchored. A writer landing between the step-3 revalidation and the step-4 write makes every subsequent retry fail its own step 3 with `staleRemote`. The loop never runs twice; the session always ends as an unresolved conflict. | `spec.md` FR-7, "The divergence branch", item 1: the expected base becomes the checksum of the content observed at step 5. Stated in the step text, not left to inference. AC **15e**. |
| **C2** | blocking | Step 5 compares bytes — correctly — but two devices whose semantic union is *already complete* serialize to different bytes, because salts and IVs differ by design ("Approved product behavior"). They see each other as permanently divergent and exhaust the retry budget on a conflict that does not exist. | FR-7 divergence branch item 2: before re-merging, compare canonical semantic manifests; equal ⇒ finalize. The byte comparison stays the **detector**, the manifest is the **arbiter**. AC **15f**. |
| **C3** | grave | The divergence branch re-merged automatically, so FR-3's LWW could silently reverse an explicit FR-4 user decision after the user had confirmed it. | FR-7, "Explicit user decisions are sticky": a session decision ledger keyed by object UUID + field key is re-applied after every re-merge and beats LWW, the tie-break and the shortcuts. A conflict never shown to the user reopens review instead of auto-resolving. AC **15h**. |
| **C4** | blocking | FR-3 read *"tie/unknown defaults local"*. "Local" is perspective-dependent, so the merge function is not commutative: two devices with equal timestamps flip the field back and forth **across sync sessions**, where the per-session retry budget cannot reach them. KDBX timestamps have one-second granularity, so ties are common. | FR-3 rewritten around a globally deterministic total order on the candidate **values** (unsigned lexicographic byte comparison, greater wins). The deterministic notes concatenation is ordered by the same rule. UI still marks uncertainty; only the **default** is fixed. AC **15g**. |
| **C5** | grave | Step 5 was declared the sole source of truth with exactly two branches, equal and different. A read-back that times out is neither, so a procedure whose job is disambiguation left its own ambiguous state undefined — and an implementer could reasonably finalize. | FR-7 step 5 and FR-10 both gain the third branch explicitly: a non-executable read-back is `ambiguous` and enters the FR-10 triage. AC **15i**. |
| **C6** | grave | "Non-destructive" was asserted unconditionally. Step 5 proves the remote held the merged state *at that instant*; if a concurrent writer overwrites immediately after and **never returns**, the contribution is permanently and silently lost, after "synced" was displayed. | Declared in `spec.md` "Out of scope / residual limits" and in the guarantee-category table: the claim is **conditional on every writing device resynchronizing**. `versionHistory` narrows the window; only `conditionalWrite` removes the condition. Spec 010's user-facing copy is rewritten to state the condition first. |
| **C7** | grave | FR-7 cited a *"spec-declared retry budget"* that was never declared, leaving conflict behaviour to the implementer. | Declared: **3 divergence rounds per commit session**, with the reasoning recorded in FR-7 — each round is a full download/merge/upload, so a larger budget converts contention into an unresponsive commit rather than a resolution. Cross-session oscillation is prevented by C4's commutativity, not by the budget. |

Two further findings, accepted:

- The report claimed T401 had been *"respecified"* while `tasks.md` still
  described selecting a concurrency token. The report declared a change that was
  never made — the same error class as the fabricated citation corrected under
  C1 of the 2026-08-14 pass. `tasks.md` T401 is now actually rewritten.
- Spec 010 declared Drive's `versionHistory` **present** on documentation alone,
  in violation of two of its own rules. Demoted to absent; Drive drops to
  **Ricostruibile**. See the corrected rows above.

One correction was made beyond the review's list, from the same root cause as C4:

- **C4b** — FR-3's deterministic notes merge read `local + "\n\n---\n\n" +
  remote`. That is perspective-dependent for exactly C4's reason: device A
  produces `A‖B` and device B produces `B‖A`, two different byte sequences and
  two different semantic manifests, so the notes field alone would keep the cycle
  divergent forever even after C1, C2 and C4 were fixed. The operand order is now
  fixed by the same total order that decides the tie-break.

### T009 — convergence model validation

The last Gate 0 item to close. Status **`passed` 2026-08-21** — PR #65: 36
tests green; mutation check exit 0, 0 survivors; re-verified on `main` and
accepted by the PM.

Artifact:
`test/features/password_manager/data/services/sync_merge_convergence_model_test.dart`.
In memory only — no network, no filesystem, no KDBX, no `lib/` dependency. It
validates the **model** of the FR-7 cycle, not its integration; the integration
tests remain T4xx, after the gate.

Required properties. The scope of the enumeration is stated exactly, because
overstating it is what hid N1 (see below): the model enumerates **2 injection
points** — inside the race window, and between the write and the verification —
across **2 concurrent writers**, plus **sequential** scenarios at **3 and 4
devices** covering every ordering and every association of the merge.
Interleaved concurrency at three or more writers is **not** enumerated.

| # | Property | Enumeration | Guards |
| --- | --- | --- | --- |
| 1 | The cycle reaches a stable state within the declared retry budget | 2 injection points, 2 writers | C1, C7 |
| 2 | No record and no one-sided field is lost | both injection points; 3-device sequential in all 6 orders; late rejoin | the founding invariant |
| 3 | A timestamp tie produces no oscillation, and mirrored perspectives choose the same winner | 2 devices, 6 alternating sessions | C4, C4b |
| 4 | A semantically complete union terminates instead of ping-ponging | single and repeating peer rewrites | C2 |
| 5 | Explicit user decisions survive a re-merge; a never-seen conflict reopens review | 1 and 2 consecutive divergence rounds | C3 |
| 6 | A non-executable verification is classified ambiguous, never finalized | first and later read-back | C5 |
| 7 | The merge is associative, commutative and idempotent | all orderings and associations at 3 and 4 sides, known and unknown timestamps | N1, N3 |

Gate 0 closes when these pass. Nothing else remains open in Gate 0. They
passed, and the gate closed on 2026-08-21.

#### What T009 does not cover — deletions are a separate gate

Stated explicitly because a green T009 will otherwise be read as "convergence is
proved", unqualified. That is the same shape of overclaim that hid N1 once
already, and it is worth more here, because the uncovered area is the one that
is *hardest* to get right.

The model expresses a document as a map of field key to `(value, mtime)`, where
a missing key is absence and absence is never deletion evidence. It therefore
**does not express**:

- **tombstones and record deletion (FR-5)** — no deletion marker exists in the
  model at all;
- **`fieldDeletionConflict` (FR-4)** — the deletion-evidence rows of the FR-4
  table have no representation, so none of them is asserted;
- **attachments** — modelled as nothing; binary identity, deduplication and
  deletion of attachments are all outside the model.

Consequently the join-semilattice result of property 7 says **nothing about the
convergence of deletions**. It is not weak evidence for them; it is no evidence.
And a set union is not merely unproven for deletion, it is the **wrong
structure**: a grow-only union can never remove an element, so a delete either
does not converge or is resurrected by the next merge from a peer that still
holds the value. Convergent deletion needs a structure that carries removal
evidence — a 2P-Set, or a tombstone with a causal clock — and its own proof of
associativity, commutativity and idempotence over *both* operations. Deletion is
routinely the hardest case in a CRDT design, and none of that work is done here.

This is a **limit of coverage, not a defect**: FR-4 already states that a
missing KDBX field or attachment is normally a union and not a deletion, so
nothing in the current design depends on the uncovered behaviour.

**Gate: `T009b` — deletion convergence model.** Separate from T009 and from
Gate 0. T009 passing does **not** discharge it. It must be superseded before any
deletion, tombstone, `fieldDeletionConflict` or attachment behaviour enters the
implementation, and it requires: a model that expresses deletion evidence, a
demonstration that the chosen structure is a semilattice over both add and
remove, and a mutation check of the same standard applied to T009.

#### Where the T301 adapter's evidence does NOT line up with T009's model

Recorded 2026-08-22 when T301/T304-T307 landed, on tester review of the first
slice. The adapter supplies the presence evidence T009 takes as given, so any
place the two disagree is a place the proof does not reach the implementation.
Three were found. The first is fixed; the second is **decided** (2026-08-23,
below); the third remains an **open limit**, listed here so nobody reads
"T009 passed" as covering it.

1. **Key space — fixed in T301.** T009 keys a document by a case-sensitive
   `Map<String, …>`. KDBX does not: `KdbxKey` compares on `key.toLowerCase()`
   (kdbx 2.5.0, `kdbx_entry.dart:58-71`) and both `_strings` and `_binaries` are
   keyed by it, so `Custom_Totp` and `custom_totp` are one field. The first
   adapter draft re-keyed on the verbatim spelling, which reported a real value
   conflict as two automatic one-sided unions — bypassing FR-4's review — and
   proposed a union that collapses onto one key on write, losing a value in
   silence and non-deterministically. The adapter now matches on the canonical
   key and carries both verbatim spellings as payload. **T009's model remains
   case-sensitive**, so the model's key space is still not KDBX's; the
   implementation is correct against KDBX, not against the model.
2. **No per-field modification time — DECIDED 2026-08-23, option (a). No longer
   blocks T401a.** T009's `Field` is
   `(value, mtime)` and FR-3's total order consumes that `mtime`. **KDBX has no
   per-field time.** `KdbxTimes` lives on `KdbxObject`, so the finest granularity
   available is one `lastModificationTime` per *entry*. Every field of an entry
   would therefore carry the same timestamp, and FR-3's rules 1 and 2 (known
   beats unknown, then newer wins) can never discriminate two fields of the same
   entry: **every intra-entry field conflict falls through to rule 3**, the
   UTF-8 value comparison, in a block. That is not a bug in rule 3 — it is
   deterministic and convergent — but it means the LWW behaviour FR-3 describes
   is, in practice, entry-level, and the "newer field wins" reading of the spec
   is not implementable on KDBX. The adapter emits **no timestamp at all** today
   rather than emitting an entry time dressed up as a field time.

   **Decision (product, 2026-08-23): option (a) — accept entry-level LWW and say
   so in FR-3.** The adapter will emit the entry's `lastModificationTime` for
   every field of that entry; rules 1 and 2 elect the newer *entry*, and its
   side wins for all of that entry's conflicting fields at once. Rule 3 still
   decides field by field on equal or unknown times, with the new FR-3a
   credential block (`UserName`/`Password`/`URL`) as the single exception, moved
   as one unit. The declared consequence: two devices editing **different
   fields of the same entry** no longer get an automatic per-field union — both
   fields become FR-4 review rows resolved by one default.

   **Option (c) — derive a per-field time from history revisions — is excluded
   by measurement, not by preference.** Three findings, each disqualifying on
   its own:

   - *granularity is wrong by one level*: `KdbxObject.modify` fires
     `onBeforeModify` only on the first modification after the object last
     became clean (`kdbx` 2.5.0, `kdbx_object.dart`), and `KdbxEntry` overrides
     it to push one history revision — so a revision is one **save cycle**, not
     one field. `VaultKdbxService.updateEntry` writes `Title`, `UserName`,
     `Password`, `URL` and `Notes` in a single cycle, and that is the app's
     ordinary edit path;
   - *it does not converge*: the derived time is a function of the local
     history, which is per-replica. Two devices holding identical final values
     derive different times for the same field, because our own adapter adds a
     revision the peer does not have. Measured `DIVERGED_FIELDS=2`, and on a
     second round the divergence **inverts a winner** (`CONVERGED=false`) — the
     same perspective-dependence class FR-3 forbids when it forbids
     "prefer local";
   - *external pruning yields a wrong time presented as known*: KeePassXC's
     `Merger::mergeHistory` deduplicates revisions sharing the same second and
     warns explicitly about possible data loss. Under rule 1 a known time beats
     an unknown one, so the wrong derived value would outrank the true evidence.

   **Option (d) is recorded as a future improvement and not adopted**: persist a
   per-field time in the entry's `CustomData`, anchored to
   `lastModificationTime`, so the time travels with the value instead of being
   inferred from one replica's edit log; a broken anchor makes staleness
   detectable and degrades the field to *unknown*, which rule 1 already handles.
   It changes what is written into every vault and must first pass its own
   commutativity/associativity test of the T009 standard.

   Full text: `spec.md` FR-3 §"The timestamp in rules 1 and 2 is the entry's"
   and §"Why a per-field time is not derived from history revisions"; tasks
   T401a and T401c.
3. **Protection status is outside the T009 proof — OPEN, low risk.** The adapter
   treats a plain→protected change at equal text as a `fieldConflict`, on the
   FR-1 grounds that protected/plain status is preserved semantics. T009's
   `Field` has no protection dimension, so the commutativity and associativity
   results say nothing about that dimension. It is a two-valued flag compared by
   equality and never merged, so it cannot reorder anything — but that is an
   argument, and an argument is what T009 exists to replace. To be folded into
   the model when T401a extends it.

Items 2 and 3 **survived the Gate 3 close of 2026-08-22**: closing Phase 3 did
not close them. Item 2 was closed on 2026-08-23 by the product decision above
and is now an implementation instruction (T401a, T401c). Item 3 is still open
and is indexed with the rest of T401's input in `tasks.md` under T401.

#### Gate 3 final validation (2026-08-22) — VALIDATED

Independent tester, against `main` at PRs #91, #93 and #96; evidence re-executed
rather than declared. 1293 tests green, `flutter analyze` clean, end-to-end
commutativity 30/30 on `main`, **zero undeclared dimensions** in the
full-manifest diff between two devices at 0, 10 and 25 s of skew on a fixture
that also exercises divergent metadata, and 15/15 regression mutants killed —
including the two the previous round left open, `_newer` inverted and the D16
codes. HIGH-5 and HIGH-6 re-verified closed with their original probes:
tombstone `CONVERGED=true` from the first exchange on the max and stable over
three rounds; remote metadata preserved from both perspectives, recycle bin
resolving by UUID.

Four residual findings, all **coverage gaps on code verified correct — not
regressions — and none producing data loss as the code stands**. Full text and
remedies in `tasks.md` under T401:

| Id | Status | Summary |
| --- | --- | --- |
| MEDIUM-5 | open, handed to T401 | `_mergeMeta`'s recycle-bin block is declared atomic in the comment and tested by nothing; adopting `recycleBinUUID` without the `enabled` flag diverges `/meta/recycleBinEnabled` and sends later deletions permanent. Mutant verified harmful. |
| MEDIUM-6 | open, handed to T401 | "a known clock beats an unknown clock" is doc-only and unguarded; inverted it stays commutative and elects the clock-less side, discarding a real edit. Same damage direction as HIGH-5. |
| LOW-4 | open, handed to T401 | Two custom icons, same UUID, different bytes are not commutative (`addCustomIcon` is first-wins). No realistic path constructs it; two-line deterministic byte tie-break. |
| LOW-5 | open, handed to T401 | The `localSettingsAt`/`remoteSettingsAt` pre-capture for `customData` is a commented precaution with no test; not shown non-commutative either. |

### T009b — deletion convergence model

Executed 2026-08-22. Status: **pending PM acceptance** — the gate closes only
when the PM accepts this evidence, per the T009 precedent; a suite declaring
itself green is the failure mode the status row exists to prevent.

Artifact:
`test/features/password_manager/data/services/sync_merge_deletion_convergence_model_test.dart`
(18 tests). In memory only — no network, no filesystem, no KDBX, no `lib/`
dependency. It imports the T009 model for `Field`, `compareFields` and
`Outcome`, so the live-value order is the one T009 proved, not a second one.

#### Structure chosen: tombstone with a clock, not a 2P-Set

The spec decides this, not taste:

- FR-5 **Keep** "emits live record and removes/neutralizes matching tombstone"
  — Keep is an *un-delete*. A 2P-Set makes removal permanent (an element once
  removed can never re-enter), so it cannot express Keep at all.
- FR-5 "Tombstoned both sides: remain deleted; **preserve newest supported
  deletion data**" — tombstones carry data ordered by recency; the join of two
  tombstones is the max of their clocks. A 2P-Set removal carries nothing to
  order.
- FR-4's deletion-evidence rows distinguish "missing with a proven deletion
  marker" from plain absence; the marker *is* the tombstone.

Every record/field/attachment key is a pair of monotone evidence components,
`(live: Field?, tomb: clock?)`. The join is pointwise — live by FR-3's total
order, tombstone by max clock, absence the identity of both — so the product is
a join-semilattice, proved by enumeration (every ordering × every full
parenthesization at 3 and 4 devices, states mixing live-only, tombstone-only,
live+tombstone, unknown mtime, zero-byte value and one-sided keys).
Classification (`live` / `deleted` / `deletionConflict`) and the Keep/Delete
decisions are a pure view over the joined evidence: the evidence converges in
any order, therefore the view does. Records, custom fields and attachments
share this one algebra; the FR-4 rows and FR-5 rules are asserted separately
against it, zero-byte-attachment presence included.

An undecided `deletionConflict` routes to review on **every** round, first
included — FR-5 says "explicit Keep/Delete required" where FR-3 defines an
automatic policy for values. **Delete** retains the tombstone (that retention
is the whole anti-resurrection argument, asserted as an outcome); **Keep**
re-emits the live field carrying the tombstone's clock so the neutralization
dominates on every device.

#### Specification gaps found while modelling

Documented and resolved with the most conservative (data-preserving) reading —
not invented around. Each is a candidate spec.md amendment for the PM:

| # | Gap | Conservative reading modelled |
| --- | --- | --- |
| **G1** | FR-5 defines a "matching" tombstone by identity (UUID) only; it does not say whether a tombstone **older** than a later live edit still forces a `deletionConflict`. | A tombstone matches only when **strictly newer** than the live side's known mtime; an edit at or after the deletion clock supersedes it — proof of life after the delete. The superseded tombstone is retained in the evidence, never forgotten. |
| **G2** | FR-5 does not say how Keep's "neutralization" survives a merge against a peer that still holds the tombstone. Dropping it locally lets the peer re-introduce it and reopen the conflict forever. | Keep re-emits the live field carrying the tombstone's clock as its mtime, so under G1 the tombstone is non-matching on every device, deterministically; the tombstone evidence is retained (the join stays monotone). |
| **G3** | The equal-clock case (tombstone clock == live mtime) is unspecified. | Not matching — the tie breaks toward preservation, FR-4's own default, and G2's neutralization relies on it. |
| **G4** | FR-7's decision ledger is session-scoped, so a Keep/Delete decision does **not** propagate to peers. | Each device holding the conflicting state must decide too (its session returns to review). The **evidence** converges regardless; only the explicit resolution is per-device. Asserted, not hidden, in the resurrection tests. |

Two stale-ledger guards of T009's Case Q class are modelled and asserted: a
Delete recorded against a tombstone that a newer edit superseded, and a Keep
recorded for a value no longer live anywhere, both reopen review instead of
silently applying.

#### Mutation check (executable)

The table is executable, same standard and runner as T009:

```bash
node tool/mutation_runner.mjs --definitions=tool/mutations/008_t009b_deletion_convergence.json --check
```

Run 2026-08-22 (re-run after the adversarial pass, below): **exit 0, 0
survivors, 0 drift.** `expectedKills` measured with the runner, never guessed.
Rows killing exactly one test carry a `$comment` in the definitions file
explaining acceptance, per the T009 convention.

| id | mutation | kills |
| --- | --- | --- |
| T009b-D1 | tombstone join carries the oldest deletion clock (max → min) | 2 |
| T009b-D2 | tombstone join keeps the first operand (perspective-dependent) | 3 |
| T009b-D3 | absence annihilates the live side instead of being the join identity | 6 |
| T009b-D4 | an equal-clock tombstone still matches (`>` → `>=`) | 2 |
| T009b-D5 | an unknown mtime supersedes the tombstone | 1 |
| T009b-D6 | a matching tombstone classifies as deleted instead of `deletionConflict` | 9 |
| T009b-D7 | Keep does not neutralize — the live field keeps its old mtime | 2 |
| T009b-D8 | Delete erases the tombstone along with the record | 3 |
| T009b-D9 | the decision ledger is never read | 6 |
| T009b-D10 | an empty value is treated as absent | 1 |
| T009b-D11 | the stale-Delete guard removed — a superseded Delete silently keeps | 1 |
| T009b-D12 | the stale-Keep guard removed — a Keep with no live value silently no-ops | 1 |
| T009b-D13 | Keep stamps the kept field one tick newer than the tombstone clock | 1 |
| T009b-D14 | the manifest omits the deletion evidence | 1 |

#### Adversarial tester pass (2026-08-22)

An adversarial mutation pass against the original 12-row table found **two
survivors** — properties the model's own comments declared but no test pinned.
Both are the "declared in prose, enforced by nothing" failure this gate exists
to refuse, both are closed by a new test and registered as executable
mutations, and three existing rows grew kills from the new tests' blast radius
(D6 8→9, D7 1→2, D9 5→6 — re-measured, properties unchanged):

| # | Severity | Survivor | Closure |
| --- | --- | --- | --- |
| **F1** | media | `resolveKeep` stamping `tomb + 1` instead of the tombstone's clock survived 16/16. The G2 comment claimed "bumping to the tombstone's clock invents no new time" and nothing asserted it: a fabricated newer mtime ties — and by the value order can beat — a **genuine** peer edit at clock+1, silently discarding real user data. | New test `Keep re-emits the live field AT the tombstone clock — never a newer, invented time`: pins `mtime == tomb` on Keep's output and asserts the outcome — the genuine edit at clock+1 wins the next LWW round. Mutation **T009b-D13** (1 kill). |
| **F2** | alta | `delManifest` with the tombstone component removed survived 16/16. Two states differing only in deletion evidence became manifest-equal, so `DelCommitSession`'s semantic short-circuit finalized **without writing the newest deletion data** — the N4 silent-finalization class, on the deletion channel. | New test `a tombstone-only divergence is a REAL divergence`: drives a tombstone-only difference through the full commit cycle and asserts the divergence round executes (`roundsUsed == 1`) and the tombstone reaches the remote; premise guard asserts the two manifests differ. Mutation **T009b-D14** (1 kill). |

Both mutants were additionally verified killed by hand (apply, run, restore by
copy, restore verified byte-identical) before being registered in the table.

Scope limit, stated to avoid the N1-class overclaim: the enumeration is the
T009 one — 2 injection points across 2 concurrent writers, plus sequential
scenarios at 3 and 4 devices over every ordering and association. Interleaved
concurrency at three or more writers is not enumerated. Recycle-bin moves are
not distinguished from permanent tombstones in this model (FR-5 keeps them
distinct); the model expresses one kind of deletion evidence, and the
recycle-bin distinction is an adapter concern gated by T30x, not an algebraic
one. FR-5's last rule — an unclassifiable state returns `unsupportedKdbxData`,
never guess or resurrect — is likewise not modelled: it is a pre-diff adapter
rejection (T304/T305), not a merge outcome, so no state in this model reaches
it by construction.

### Second-pass review (2026-08-15)

A second independent review confirmed C1, C2, C3, C5, C6 and C7 as corrected,
confirmed C4b, and rejected the amendment on one blocking defect and three
specification gaps. The blocking defect was found by **running this model at
three devices**, which the suite did not do.

| # | Severity | Defect | Correction |
| --- | --- | --- | --- |
| **N1** | blocking | C4b fixed the *operand order* of the notes concatenation, which is sufficient at two devices and not at three: concatenation is not associative. `(A‖B)‖C = alpha‖zeta‖mike` while `A‖(B‖C) = alpha‖mike‖zeta`. Two devices that merged the same three notes in different orders hold different values → different manifests → the C2 short-circuit stops firing → the next merge concatenates the concatenations and **duplicates user-written text** in the field where recovery codes live. Measured to stabilize rather than livelock, which makes it silent. | `spec.md` FR-3, "Notes are an ordered union of segments": split on the separator, set-union the segments, drop empties, sort by the same total order, rejoin. Associative, commutative and idempotent. AC **15j**. |
| **N2** | grave | The spec equated "no ledger entry" with "never shown to the user". A user who saw a conflict and **accepted the automatic default** left no entry and was sent back to review forever; and FR-6 never said whether shortcut decisions enter the ledger at all. Neither loop is charged to the retry budget, so review re-entry was unbounded. | FR-7 now declares all three: confirming review records an entry for **every conflict presented**, including defaults accepted; **shortcuts record**, one entry per conflict resolved; a session may re-enter review at most **3 times**, counted separately from the retry budget, after which it ends unresolved with the local merged state and backup retained. |
| **N3** | grave | FR-3 extended the tie-break to "an unknown timestamp" without saying which timestamp the winner carried, and the model could not express an unknown timestamp at all — so the suite asserted nothing about a case the spec names. Treating unknown as a bare tie makes the relation non-transitive: `A=(t5,"x")`, `B=(unknown,"y")`, `C=(t3,"z")` gives `"z"` one way and `"x"` the other. | FR-3 defines the order over `(modification time, value)`: known beats unknown, then newer wins, then the value order — used on equal known times **and** on two unknowns. The winning side's timestamp travels with the value. `Field.mtime` in the model is now nullable and the case is asserted. AC **15k**. |
| **N4** | minor | The C2 short-circuit's correctness depends entirely on the canonical manifest being complete, and that dependency was implied by a reference to FR-1 rather than declared. | FR-7 divergence branch item 2 gains an explicit **safety invariant**: every semantic field omitted from the manifest is a field on which a real divergence is finalized in silence; the manifest is defined by exclusion from a closed list, never by a hand-maintained inclusion list. |

Two overclaims in this file were corrected at the same time, because they are
what allowed N1 to pass unnoticed:

- the T009 property table read *"each asserted under adversarial multi-device
  interleavings"* and property 2 read *"under **every** enumerated
  interleaving"*, while the enumeration was 2 injection points across 2 devices.
  Nothing at three devices existed, and N1 is only visible at three. The table
  now states the enumeration per property, and names what is **not** enumerated.
- the same table implied a closed enumeration where the model is a
  finite hand-written set of scenarios. It is not exhaustive and does not claim
  to be.

### Third-pass review (2026-08-15)

A third independent review reproduced the mutation table 7/7, confirmed N1 closed
by execution, confirmed the two strengthened guards, and validated the
join-semilattice claim over 20 000 randomized trials — beyond what the suite
itself asserted. Verdict **validated with risk**, with three closures required.
None is a convergence defect; two are data-loss disclosures.

| # | Severity | Finding | Correction |
| --- | --- | --- | --- |
| **Q1** | grave | The declared cost of the `\n\n---\n\n` notes separator was **incomplete**. It disclosed reordering only. Two damages existed: the peer's text was **inserted between** the user's own paragraphs, and — undisclosed — the set union **silently deleted** segments the user legitimately repeated (`TODO / rotate key / TODO` came back as two). Under-declaring a data-loss defect is worse than not declaring it. | The separator is now the sentinel `"\n\n---\u241E---\n\n"`. The union property belongs to the set union, not the delimiter, so the restriction is free. Ordinary user text is now a single indivisible segment, and both damages are eliminated for it. `spec.md` FR-3 gains §"The separator is a sentinel, and why" with the complete disclosure and the residual cost. Mutation **Q1**. |
| **Q2** | latent | In the ledger branch, `l.value == decided ? l : r` degenerates to *"take the second operand"* when `decided` matches neither side: operand-order-dependent (defect C4's class, relocated) and the sticky decision is discarded **in silence**. Measured 22678/30000 commutativity violations in that state, against 0/30000 when the decision is live. Unreachable today — but only because of FR-4 and the ledger's session lifetime, neither of which anything asserted, and `011-master-password-session-scope` is live work on exactly that scope. | The invariant `decided ∈ {local.value, remote.value}` is now checked. On violation the field **returns to review** as an undecided conflict carrying both candidates — never resolved by picking an operand. Written into `spec.md` FR-7 with the two constraints it rests on and the warning that changing either reopens it as silent data loss. Mutation **Q2**. |
| **Q3** | disclosure | The model expresses no tombstone, no `fieldDeletionConflict` and no attachment, so the proved algebra says **nothing** about the convergence of deletions — and a grow-only union is not merely unproven for deletion, it is the wrong structure. A green T009 would have been read as "convergence is proved", unqualified: the same overclaim that hid N1. | §"What T009 does not cover" added above, the T009 status rows now carry **"scope: additions only"**, and the work is registered as a **separate gate T009b** in `tasks.md` — to be superseded before any deletion, tombstone or attachment behaviour enters the implementation. Not a Gate 0 condition. |

Test counts: convergence model 28 → **31**, full suite 598 → **601**. No test was
deleted, and no assumption was promoted to `passed`: T009 remains `not-run`,
T009b opens as `not-run`. `lib/` remains untouched.

### Fourth-pass review (2026-08-16, PR #37)

A fourth review found one defect in the model, at the point where the model and
the specification are supposed to be the same statement.

| # | Severity | Finding | Correction |
| --- | --- | --- | --- |
| **R1** | grave | `compareValues` compared `String.codeUnits` — **UTF-16 code units** — while its own doc-comment and FR-3 both prescribe a comparison of **byte** sequences. The two are not two spellings of one order. UTF-16 encodes an astral character as a surrogate pair in `U+D800..DFFF`, which sorts *below* `U+E000..FFFF`; the same character's UTF-8 bytes and its code point sort *above*. `U+1F600` against `U+FFFD` elects opposite winners under the two encodings, and an emoji in a notes or title field reaches it. The consequence is not cosmetic: **T009 proved commutativity, associativity and idempotence about a total order the spec does not prescribe**, so an implementation that followed the spec would not be the function the model validated — the "model validates itself rather than the specification" failure, in the one place the spec is most explicit. | `compareValues` now compares `utf8.encode(a)` against `utf8.encode(b)`. The three algebraic properties were **re-measured** on the values that moved, not assumed to survive: new test `the semilattice still holds on the values where the byte order and the UTF-16 order disagree`. A discriminating test, `the tie-break orders by UTF-8 bytes, not by UTF-16 code units`, pins the encoding so restoring `codeUnits` fails loudly; it also asserts the UTF-8 order equals the code-point order. `spec.md` FR-3 rule 3 now names **UTF-8** explicitly and states why the encoding is load-bearing, and the notes-segment sort is declared to be the **same comparator**, not a second string ordering. Mutation **R1**. |

The notes-segment sort already used `compareValues`, so no second ordering had to
be reconciled; the spec now says so, which is what stops one appearing later.

Test counts: convergence model 31 → **33**, full suite 601 → **603**. The merge
with `main` that precedes this pass left the suite count unchanged at 601, so the
figure recorded by the third pass above still holds as the baseline for this one.
No test was deleted, no assumption
was promoted to `passed`, and `lib/` remains untouched.

#### Mutation check

Each mutation reverts one correction in the model and the suite is re-run. A
correction whose only guard is a single assertion on a counter is not guarded.
Measured with `--reporter json`; the `expanded` reporter truncates its failure
list at four and understates these counts.

**This table is now executable (2026-08-20).** The ten mutations are registered
as `tool/mutations/008_t009_convergence.json` with ids `T009-C1` … `T009-R1`,
run by the same `tool/mutation_runner.mjs` that owns the spec 009 table — a
hand-maintained prose table is the drift the runner's own header documents, in
this very PR's lineage (#37):

```bash
node tool/mutation_runner.mjs --definitions=tool/mutations/008_t009_convergence.json --check
```

Latest execution: **14/14 killed, 0 survivors, 0 drift, exit 0.** The JSON file
is the reference for kill counts from now on; two rows diverge from the prose
below and each carries its own `$comment` explaining why — `T009-C4` measures
**6** (not 9) and `T009-N1` measures **8** (not 11), both tighter
reconstructions of the historical mutants (the A1-M2 class of divergence:
same property, narrower edit, identical strongest kill). The prose table below
is retained as the historical record of the review passes, not as the current
measurement.

##### Fifth-pass closure (2026-08-20) — survivors found by running the runner

Making the table executable is what found these: an independent tester ran
mutations the prose table never contained, and three properties the model
*implements* turned out to be properties nothing *held*. Same failure mode as
A2-M4 in the spec 009 table — asserted in a comment, guarded by nothing.

| # | Severity | Finding | Closure |
| --- | --- | --- | --- |
| **M1** | media | `maxMtime` was pinned by nothing: max→min and null-poisoning (`a==null\|\|b==null → null`) both survived 33/33, because every notes scenario used identical mtimes. Min is itself commutative/associative/idempotent, so the semilattice tests are structurally blind to it. | New test `the notes union carries the newest known timestamp, and that timestamp decides a later LWW round against a peer`: divergent known mtimes and mixed known/unknown, asserted on the **outcome** — which value survives the next round, i.e. whether the user's merged text is discarded. Mutations **T009-M1a** (1 kill), **T009-M1b** (1 kill). |
| **M2** | media | The equal-value branch (`compareFields` deciding which side's field travels) survived "always keep local": every prior equal-value pair carried equal mtimes. Keeping the local timestamp is perspective-dependent — defect C4's class, once more. | New test `equal values with different timestamps carry the newer timestamp, from either perspective`: asserts the carried mtime, manifest commutativity, and the outcome of the next LWW round against a third device. Mutation **T009-M2** (1 kill). |
| **M3** | bassa | The retry budget of 3 was pinned only by `roundsUsed == 3` — a counter, which this table's own standard rejects as a sole guard. | New test `the retry budget bounds the uploads dispatched, not only a counter`: the observable cost the budget exists to bound (FR-7's own rationale) is uploads per commit session — initial + exactly 3. Mutation **T009-M3** (2 kills: the outcome test and the counter test). T009-C1 grew 7→8 from this test's blast radius. |
| **L1** | bassa | `allAssociations` claimed "every association" at 4 sides while enumerating 3 of the 5 full parenthesizations (both folds + balanced pairing; Catalan(3)=5). The claim/enumeration mismatch is the exact overclaim shape that hid N1. | The helper now enumerates **every** full parenthesization via recursive split (`allJoins`), for the whole-merge and the notes-union tests: 24 orderings × 5 shapes at 4 operands. The claim and the enumeration are the same statement again. No new mutation — this widens existing guards. |

Test counts: convergence model 33 → **36**, full suite 858 → **861**. T009
remains `not-run`: the gate closes on PM acceptance, not on the suite
declaring itself green. *(Accepted by the PM 2026-08-21; see Sign-off.)*

| Mutation | Reverts | Tests killed | Strongest kill |
| --- | --- | --- | --- |
| expected base not re-anchored | C1 | **7** | `a writer landing after our write converges in one round` — outcome becomes `staleRemote` |
| semantic short-circuit removed | C2 | **2** | `a peer that keeps rewriting the same content still finalizes` — outcome becomes `unresolved`, budget fully spent |
| ledger not consulted | C3 | **3** | `a decision survives two consecutive divergence rounds` — outcome becomes `needsReview` |
| tie-break → prefer local | C4 | **9** | `two devices that each keep their own value stop the remote moving across sessions` — the remote alternates `alpha`/`beta` forever |
| notes union → fixed-order binary concatenation | C4b, N1 | **11** | `three devices reach the same remote state in any merge order` — six sync orders yield distinct manifests |
| non-executable read-back → finalized | C5 | **2** | `a read-back that fails on a later round is ambiguous too` |
| unknown timestamp treated as a bare tie | N3 | **2** | `an unknown timestamp does not break associativity` |
| sentinel separator → plain `\n\n---\n\n` | Q1 | **1** | `the sentinel separator leaves ordinary user text intact` — the user's own paragraphs are split, interleaved and deduplicated |
| ledger invariant guard removed (apply a decision naming neither side) | Q2 | **1** | `a ledger decision naming neither candidate reopens review instead of silently taking an operand` — outcome stops being `needsReview` and becomes operand-order-dependent |
| `compareValues` → UTF-16 `codeUnits` | R1 | **2** | `the tie-break orders by UTF-8 bytes, not by UTF-16 code units` — `U+1F600` and `U+FFFD` swap winners, and the notes segments swap order |

The R1 correction was re-measured against the two mutations it could plausibly
have weakened, since it changed the comparator both of them depend on. Both got
**stronger**, and no mutation lost a kill:

| Mutation | Before R1 | After R1 |
| --- | --- | --- |
| tie-break → prefer local (C4) | 7 | **9** |
| notes union → fixed-order concatenation (C4b, N1) | 9 | **11** |
| sentinel separator → plain `\n\n---\n\n` (Q1) | 1 | **1** |

Both gains are the two tests added for R1, which depend on the tie-break and on
the notes order respectively and therefore die under those mutations too.

The C4b/N1 row also **corrects a stale count**: this table read `7`, but the
mutation kills 9 on the pre-R1 file. The two extra kills are Q1's own tests —
`the sentinel separator leaves ordinary user text intact` and `the sentinel does
not weaken the union property` — which were added on 2026-08-15 without the C4b
row being re-measured. The guard had been stronger than recorded since then; the
number was wrong, not the guard.

Two mutations previously killed exactly one weak assertion each and were
strengthened rather than accepted:

- **C4** was killed only by the pure-function test; the system test
  `two devices tied converge instead of ping-ponging` **passed** under
  prefer-local, because the re-syncing device adopted the remote content
  wholesale and so had nothing left to flip. The new scenario keeps each device
  holding its own candidate across six alternating sessions — the ordinary case
  of two phones edited in the same second — and dies under prefer-local.
- **C2** was killed only by `roundsUsed == 0`: with a single peer write the
  session finalizes either way and only budget accounting changes. The new
  scenario has the peer re-serialize the same semantic content after every one
  of our writes, so without the arbiter the session exhausts the budget and ends
  `unresolved`. The **outcome** now depends on the short-circuit.

The two mutations added on 2026-08-15 (Q1, Q2) each kill exactly **one** test,
and that is accepted here rather than strengthened, for a reason that does not
apply to the C2 and C4 cases above. Both kills assert an **outcome** — text
present or lost, `needsReview` or an operand silently taken — not a counter,
which is the standard this table applies. Neither can be reached from a
system-level scenario:

- **Q1** is only visible when the user's own text contains the separator, which
  after the fix is a sequence no scenario can produce by writing ordinary
  Markdown; a system test would have to type the sentinel on purpose, which
  tests the sentinel rather than the correction.
- **Q2** is **unreachable by construction** while FR-4 and the session lifetime
  of the ledger hold — that is precisely the finding. A system-level scenario
  that reached it would mean one of those two constraints is already broken. The
  direct test is therefore the only instrument that can hold the invariant, and
  holding it is the whole point: the state must fail loudly if a later change
  (spec 011) makes it reachable.

The C4 and C2 cases were different in kind: those states *were* reachable from
ordinary two-device traffic, and the suite simply had no scenario that reached
them.

`C5` and `N3` are each killed by two tests covering two distinct paths (first
versus later read-back; ordering rule versus associativity under it). Their
guards are narrow because the rules are narrow — each is a single
classification — and this is recorded as accepted, not overlooked.

## Post-review corrections (2026-08-14)

An independent review of the 2026-08-13 run accepted the **NO-GO** verdict but
rejected this file as an authoritative record: it contained a fabricated
evidence citation and `passed` cells with no executed test behind them. The
corrections below were applied. `lib/` remains untouched.

| # | Finding | Correction applied |
| --- | --- | --- |
| **C1** | B1 was partly justified by "`googleapis 14.0.0` `FilesResource.update` exposes no conditional parameter". **`googleapis` is not a dependency of this project** — absent from `pubspec.yaml`, `pubspec.lock` and `.dart_tool/package_config.json`; it exists only in the machine-wide pub cache as a leftover of an unrelated project. The citation was fabricated. | Citation deleted from both places it appeared. B1 is now justified **only** by the Drive REST v3 documentation (no precondition documented on `files.update`) and by the v3 `File` resource carrying no `etag`. The real transport evidence is recorded instead: Drive is called through a raw `http.Client` that spreads its header map, so `If-Match` **can** be sent — it simply never has been. Stated explicitly as the only remaining path, to be closed by a live-network spike. A test now asserts the raw-client call shape. |
| **C2** | B2 claimed entry color **values** are unreadable. Premises true (`KdbxColor` has no RGB accessor and no `==`), conclusion false: `KdbxNode.node` is a public `final XmlElement` (`src/kdbx_object.dart:118`) exported from `kdbx.dart`, and the RGB code round-trips in it. | **B2 removed from the blocker list.** `T001 entry colors round-trip with their RGB values, not just their presence` proves it, including that a *changed* color is detectable. The canonical manifest now compares color **values** instead of presence. Matrix row corrected from `failed`/`failed` to `passed`. `xml: ^6.6.1` declared in `pubspec.yaml` — it was missing, though already resolved transitively at exactly that version. |
| **C3** | R2 held entry `AutoType` preservation to be "plausible but unproven", while the same XML mechanism was accepted as plausible elsewhere in this report — an internal inconsistency. | **R2 closed.** The fixture now authors a real `<AutoType>` node; `T001 entry AutoType survives save and reopen as an untouched XML node` asserts `DefaultSequence`, `Association`, `Window` and `KeystrokeSequence` after a save/reopen, and the manifest compares the node. Matrix row moved from `not-run` to `passed`. |
| **C4** | 8 cells in the "Unsupported detector" column read `passed`, but the implemented detector (`_validateSide`, `_crossSideKindMismatch`) covers only UUID integrity and lineage. | 7 cells moved to `not-run`: recycle bin, permanent tombstones, strings + protection, attachments, header cipher/compression, KDF parameters, original credentials. 1 cell **kept `passed` by implementing the test**: the header row relied on "the library throws `KdbxUnsupportedException`", which no test exercised (`grep -rn 'KdbxUnsupportedException' test/` was empty); `T004 unsupported KDBX major version is rejected by the library` now byte-patches the major version and asserts the refusal. That row was split into "header major version" (`passed`) and "header cipher/compression" (`not-run`), since only the version is covered. The UUID row keeps `passed`, backed by the 5 real T004 tests. |
| **C5** | `google_drive_api_service_test.dart:267` asserted `expect(file.props, isNot(contains('etag')))`. Equatable's `props` is the list of **values**, not field names, so the assertion held regardless of the model's fields. It proved nothing. | Replaced with an assertion over the model source: `DriveRemoteFile` declares exactly `id`, `name`, `modifiedTime`, `md5Checksum`, and none of `etag` / `version` / `headRevisionId`. |
| **C6** | Four holes in the writer scanner, presented as "any new writer fails the test". | (a) every operation pattern now also matches its `*Sync` variant, so a future `renameSync` cannot pass silently; (b) the scan root is now all of `lib/`, not two subtrees — this added **no** new writer, so the 14-file inventory is unchanged and now provably complete; (c) non-filesystem receivers are scrubbed from the line instead of discarding it, so a clipboard call sharing a line with a real write no longer hides it — this initially surfaced two `ClipboardGuard` false positives, and the scrub pattern was widened to `sl<ClipboardGuard>().copy(` rather than reverting; (d) the `KdbxFile.merge` guard regex, which matched *any* `merge(`, now requires a `kdbx`-containing receiver token — applied to both scan tests. A new test, `the scanner itself catches sync writers and mixed lines`, asserts (a) and (c) directly. |

Test counts: `merge feasibility` 15 → **18**, `inventory baseline` 12 → **13**,
`conditional update` 10 → **10** (rewritten, not added), full suite 551 → **555**.
No test was deleted.

Not corrected, deliberately: the `not-run` rows for platform atomicity evidence,
path canonicalization and the Gate 1 detectors. They are honest `not-run`s and
closing them is Gate 1 work, outside the Phase 0 scope.

## Sign-off

| Gate | Status | Reviewer | Date | Notes |
| --- | --- | --- | --- | --- |
| Gate 0 T001–T008 | `failed` | — | 2026-08-13 | T001–T004, T006–T008 pass; T005 partial. **One blocker open: B1. Domain freeze forbidden.** (B2 was also listed on this date; withdrawn on review — see C2 and the row below.) |
| Gate 0 T001–T008 (post-review) | `failed` | independent review | 2026-08-14 | Verdict unchanged: **NO-GO**. B2 declassed (not a blocker), R2 closed. **One blocker remains: B1.** Domain freeze still forbidden. |
| Gate 0 T005 live re-spike (B1) | `failed` | — | 2026-08-15 | B1 **measured**: Drive v3 enforces no precondition. 6 decisive probes `200` with remote bytes overwritten; 6 counter-probes exclude every alternative explanation. **Not a blocker**: spec 008 FR-7 rewritten to require only `get` + `put`. |
| ~~Gate 0 close~~ | ~~`passed`~~ | — | 2026-08-15 | **REVERTED 2026-08-15.** Declared T001–T008 complete and T201 startable. The exit criterion it measured itself against had been rewritten in the same commit, and the mechanism replacing B1 was `not-run`. Struck, not deleted: the reversal is part of the record. |
| Gate 0 amendment review | `failed` | independent review | 2026-08-15 | **Not validated, rework.** Convergence cycle non-convergent as written: no re-anchor on retry, no semantic arbiter, perspective-dependent tie-break. Five further defects. Gate 0 **reopened**; **T009 added**; T201 and domain freeze **blocked**. Drive `versionHistory` demoted to absent. |
| Gate 0 amendment review (2nd pass) | `failed` | independent review | 2026-08-15 | C1, C2, C3, C5, C6, C7 and C4b confirmed corrected; 010 validated. **One blocking defect: N1**, the notes concatenation is not associative, found by running the model at three devices. Three specification gaps N2–N4. The T009 enumeration was 2 devices while the report claimed adversarial multi-device coverage — the overclaim that hid N1. |
| Gate 0 amendment review (3rd pass) | `validated with risk` | independent review | 2026-08-15 | N1 confirmed closed by execution, the mutation table reproduced 7/7 independently, both strengthened guards confirmed strong, the semilattice claim held over 20 000 randomized trials. Three closures required, all applied here: **Q1** the `\n\n---\n\n` disclosure under-declared a second, data-loss damage and the separator is now a sentinel; **Q2** the ledger Case Q is now guarded by an asserted invariant instead of being merely unreachable; **Q3** T009's silence on deletions is declared and gated as T009b. |
| Gate 0 T009 convergence model | `not-run` | — | — | **The remaining Gate 0 blocker.** 33 model assertions pass and every correction is mutation-guarded, but the status stays `not-run` until the PM accepts the gate: a suite declaring itself green is the failure mode this row exists to prevent. Gate 0 closes when this is accepted and on no other condition. **Scope: additions only** — deletions are T009b and are not covered. |
| Gate 0 T009 convergence model | `passed` | PM | 2026-08-21 | **Accepted.** 36 tests green on `main` (PR #65); `node tool/mutation_runner.mjs --definitions=tool/mutations/008_t009_convergence.json --check` exit 0, 0 survivors, re-verified by the PM on 2026-08-21. **Scope: additions only** — deletions are T009b and are not covered. |
| Gate 0 close | `passed` | PM | 2026-08-21 | **T001–T009 all passed; Gate 0 CLOSED.** T201 and the domain freeze are unblocked. T009b remains open and gates only deletion/tombstone/attachment work. |
| Gate 1 writer/mutex/platform evidence | `not-run` | — | — | All platforms disabled |
| Gate 3 Phase 3 (round 1) | `failed` | independent tester | 2026-08-22 | **Not validated.** Three HIGH: HIGH-3 a consumed session was re-callable and, with assertions compiled out, produced duplicate UUIDs in the candidate; HIGH-2 the FR-1 parity gate had no test; HIGH-1 the DI barrier checked only `export`. Plus MEDIUM-1/2/3. All closed by replaying the tester's own mutants. |
| Gate 3 Phase 3 (round 2) | `failed` | independent tester | 2026-08-22 | **Not validated.** 7/7 round-1 mutants dead, but two HIGH remained: HIGH-1 the barrier's return-type check was inert on a `null` interpolation; HIGH-4 a third commutativity divergence written by the merge itself (`Changeable.modify` stamping `DateTime.now()`), closed by `_stampDeterministicTimes`. Sibling order and entry history declared non-commutative and pinned. |
| Gate 3 Phase 3 (round 3) | `failed` | independent tester | 2026-08-22 | **Not validated.** HIGH-6 `_unionTombstones` was add-if-missing, so two devices deleting the same record never converged; HIGH-5 `applyMerge` never merged `KdbxMeta`. Both merged rather than refused, on the KDBX per-field change clocks, which entered the canonical manifest. MEDIUM-4, LOW-2, LOW-3 closed. Frozen-contract insufficiency raised and NOT resolved: automatic metadata adoption is invisible in `MergeReviewSummary`. |
| Gate 3 Phase 3 (final) | `passed` | independent tester | 2026-08-22 | **VALIDATED.** 1293 tests green, `flutter analyze` clean, commutativity 30/30 on `main`, zero undeclared dimensions in the full-manifest diff at 0/10/25 s of skew on a metadata-divergent fixture, 15/15 regression mutants killed including `_newer` inverted and the D16 codes. HIGH-5 and HIGH-6 re-verified closed with the original probes. Four residual findings (MEDIUM-5, MEDIUM-6, LOW-4, LOW-5) — coverage gaps on verified-correct code, no data loss, handed to T401. |
| Gate 3 close | `passed` | PM | 2026-08-22 | **T301–T310 all passed; Gate 3 CLOSED.** PRs #91, #93, #96. Phase 4 is unblocked. The four residual findings plus the four previously open T401/T401a items are indexed as one list under T401 in `tasks.md`. |
