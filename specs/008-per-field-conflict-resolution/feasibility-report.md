# 008 — Feasibility report

**Report task**: T008
**Current status**: Gate 0 **closed 2026-08-15**. B1 measured and **confirmed
`failed`**; it is no longer a blocker because spec 008 FR-7 no longer depends on
it. Feature stays disabled on every platform, on the platform-atomicity rows.
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

> **Read "Post-review corrections" at the end of this file first.** An
> independent review of the 2026-08-13 run found one fabricated evidence
> citation and a set of `passed` cells with no executed test behind them. The
> verdict is unchanged (**NO-GO**) but the supporting record was rewritten. Every
> row below is the corrected version.

**Toolchain caveat (environment, not a spec finding).** `flutter pub get` cannot
resolve on this checkout: `pubspec.yaml` pins `analyzer: ^14.1.0`, which needs
`meta ^1.18.3`, while the active Flutter 3.44.8 pins `meta 1.18.0`. Every command
below therefore ran with `--no-pub` against the already-resolved
`.dart_tool/package_config.json`. This predates Gate 0 and is unrelated to spec
008, but it blocks plain `flutter analyze`/`flutter test` and must be fixed
before CI can reproduce this report.

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
| `test/features/password_manager/data/services/safe_vault_file_writer_harness_schema_test.dart` | new, harness/artifact schema (T006), 15 tests |
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

**Closed 2026-08-15.** T001–T008 completed. T005 was closed by the live-network
re-spike recorded in "B1 live-network re-spike" below.

**B1 is `failed`, not `passed`, and not withdrawn.** Google Drive REST v3 offers
no compare-and-swap on the upload path. That is now measured against the real
service, not inferred from documentation. What changed is not the finding but the
spec: 008 FR-7 was rewritten around a `get` + `put` write-verify-converge cycle
that requires no server-enforced precondition, so B1 no longer gates anything.

| # | Finding | Status | Gates the feature? |
| --- | --- | --- | --- |
| **B1** | Drive v3 does not enforce any HTTP precondition on `files.update`. Confirmed live, with byte-level counter-proof. | **`failed`** (measured) | **No.** Spec 008 FR-7 (rewritten 2026-08-15) requires only `get` + `put`. Drive lands in the **Versioned** guarantee tier: no CAS, but `versionHistory` present. See "Guarantee by backend category" in `spec.md`. |

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
| Drive backend guarantee tier | `passed` | same spike | **Versioned**: no `conditionalWrite`, `versionHistory` present (revisions API) |
| Storage-agnostic write-verify-converge cycle (`get` + `put` only) | `not-run` | FR-7 as rewritten 2026-08-15 | design accepted; implementation + tests are T4xx |
| Ambiguous transport outcome classification | `passed` | `conditional update` (10 tests) | client-side rules only, fake transport |
| Writer/path inventory reconciled | `passed` | `inventory baseline` (12 tests) | 14 writer files; 6 gaps vs FR-8 |
| Path identity/alias design reviewed | `not-run` | design drafted below | executed in Gate 1 T103/T107 |
| Platform artifact schema recorded | `passed` | `harness schema` (10 tests) | schema only; **no platform evidence** |

Gate 0 may close when T001–T008 evidence is complete and every unresolved target
platform remains disabled. **That condition is now met: T001–T008 all have
executed evidence, B1 has a measured result, and every platform row stays
`not-run`/disabled.** T201/domain freeze may start. No platform is enabled.

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

Drive therefore lands in the **Versioned** tier of `spec.md` §"Guarantee by
backend category": no `conditionalWrite`, `versionHistory` present. See
`specs/010-multi-cloud-storage/spec.md` for the capability taxonomy.

Not measured by this spike, and therefore **not** claimed: the details of Drive's
revisions API — retention policy, `keepRevisionForever` semantics, the ceiling on
pinned revisions and the quota impact. `versionHistory` is recorded as present
for Drive on the strength of the documented revisions API, and its operational
details are `not-run`. Spec 010 requires a dedicated spike before any adapter
relies on them.

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
| Presentation direct database writes removed/forbidden | **`failed`** | 5 presentation writers still exist (`presentation layer still mutates database files directly`) — Gate 1 T102 |
| Alias and deterministic multi-path lock tests enumerated | `not-run` | enumerated below; executed in Gate 1 T107 |
| No shared path mutex shipped by Gate 0 | `passed` | `no shared database path mutex exists yet` |

## Path identity design (input to Gate 1 T103/T104)

Design recorded, **not executed** (`not-run`).

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
| Android | `not-run` | no | `build/safety-evidence/android/safe-vault-writer.json` + log | Android app storage on named device/emulator |
| iOS | `not-run` | no | `build/safety-evidence/ios/safe-vault-writer.json` + simulator/device logs | iOS simulator plus release-target physical evidence before release |
| macOS | `not-run` | no | `build/safety-evidence/macos/safe-vault-writer.json` + log | macOS app sandbox/runtime |
| Windows | `not-run` | no | `build/safety-evidence/windows/safe-vault-writer.json` + log | native Windows runner/filesystem |
| Linux | `not-run` | no | `build/safety-evidence/linux/safe-vault-writer.json` + log | native package runner/filesystem |

No artifact file exists under `build/safety-evidence/`; asserted by
`no platform artifact exists yet`.

## Model corrections from spike

Input to T201. **T201 must not start while B1 is open.**

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
  what the rewritten FR-7 actually needs. T401 is unblocked and is respecified
  as "implement the write-verify-converge cycle", not "select a token".
- **platform path identity/global-lock fallback**: design recorded above;
  `identityConfidence` flag with coarse global lock fallback. Per-platform
  decision `not-run`.
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
1a. Drive revisions API operational details — retention window,
   `keepRevisionForever` semantics, ceiling on pinned revisions, quota impact.
   `versionHistory` is recorded as present for Drive from its documented API;
   none of these details was measured. `not-run`. Required by spec 010 before an
   adapter relies on them.
1b. Every non-Drive provider's capabilities. Nothing was measured. Spec 010
   lists them as **to verify** and requires a per-adapter spike.
2. Detection of malformed non-UUID constructs — recycle bin, tombstones,
   strings/protection, attachments, cipher/compression, KDF parameters,
   credential shapes. Round-trip evidence exists for all of them; **detector**
   evidence does not. All `not-run`.
3. Atomicity, flush and rename semantics on **every** platform including macOS —
   nothing was executed; all rows `not-run`.
4. Path canonicalization and case/hard-link behaviour — designed, not executed.
5. Behaviour of the merge adapter under a `kdbx` patch upgrade — the spike
   depends on non-exported symbols; no upper bound is pinned in `pubspec.yaml`
   beyond `^2.4.2`. R1.
6. Whether the `<AutoType>` node survives a round-trip performed by **another**
   KeePass implementation. Proven here for `kdbx 2.4.2` only.

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
| Gate 0 close | `passed` | — | 2026-08-15 | T001–T008 all have executed evidence. Domain freeze (T201) may start. **No platform is enabled**; every platform row stays `not-run`. |
| Gate 1 writer/mutex/platform evidence | `not-run` | — | — | All platforms disabled |
