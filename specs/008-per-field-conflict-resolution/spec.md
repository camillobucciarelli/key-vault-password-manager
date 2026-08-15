# 008 — Per-field sync conflict resolution

**Status**: Draft · Gate 0 closed 2026-08-15; feature stays disabled per platform
until Gate 1 atomicity artifacts  
**Kind**: New feature  
**Depends on**: 001, 002, 005 · consumes the storage-capability port defined by
**010** (008 is the consumer; 010 owns the port)

## Approved product behavior

- Result preserves records unique to either side.
- **Prefer local** chooses local values only where both sides present a real
  conflict.
- **Prefer remote** chooses remote values only where both sides present a real
  conflict.
- Neither shortcut deletes `localOnly` or `remoteOnly` records, fields, custom
  fields, or attachments.
- Missing data is not deletion evidence. Deletion requires explicit KDBX deletion
  evidence plus explicit policy/choice.
- Shortcut acceptance is semantic, not byte-identical: encryption salts, IVs and
  serialized bytes may differ.

## Current problem

`lib/features/password_manager/data/services/database_sync_orchestrator.dart`
detects whole-file divergence with MD5 and resolves by uploading local bytes or
replacing local bytes with remote bytes. Valid changes can be discarded.

`lib/features/password_manager/data/services/vault_kdbx_service.dart` maps KDBX
to `VaultSnapshot`, but that projection is not lossless enough for merge writes.
Rebuilding from it could drop tombstones, history, attachment properties,
protected-field flags, custom icons, metadata or settings.

## Gate 0 — feasibility before model freeze

First implementation work is test-only spike against installed `kdbx` 2.4.2 and
Drive API, plus target-filesystem harness/schema definition. Gate 1 executes that
harness per platform. Gate report task **T008** is part of Gate 0 and must pass
before domain model freezes.

Spike must:

1. Round-trip KDBX 3 and 4 with password-only and password+key-file credentials.
2. Cover every construct current library supports: root/group UUIDs, hierarchy,
   moves, recycle bin, `DeletedObjects`, timestamps, history, exact attachment
   bytes/protection, plain/protected custom fields, custom data/icons,
   metadata/settings and header/KDF settings.
3. Compare canonical semantic manifests, never ciphertext bytes.
4. Prove data adapter can import one-sided group/entry and apply field choices
   without changing unrelated supported semantics.
5. Prove root UUID lineage check before diff.
6. Prove tombstones can be inspected/emitted without `KdbxFile.merge`; installed
   API marks that method unfinished and it is forbidden.
7. Measure which optional concurrency capabilities the remote backend actually
   offers — server-enforced conditional write, version history — and record the
   measurement. A negative measurement is a valid Gate 0 result: FR-7 requires
   only `get` + `put`, so absent capabilities lower the guarantee tier
   (see "Guarantee by backend category") without blocking the feature.
8. Define per-platform atomic replace/fsync artifact schema and record every
   platform as `not-run`, `passed`, `failed` or `disabled`. Gate 0 does not claim
   target evidence; Gate 1 produces it. Host macOS evidence never qualifies
   Android, iOS, Windows or Linux.
9. Produce T008 report at
   `specs/008-per-field-conflict-resolution/feasibility-report.md`: KDBX support
   matrix, measured remote-backend capabilities and the resulting guarantee tier,
   writer inventory, path-identity rules, artifact schema and
   explicit per-platform status/feature flag.

Any supported construct that cannot be preserved, or platform without passing
atomicity artifact, keeps feature disabled. Unsupported KDBX data is detected
before backup/write; never normalized silently.

**A backend without server-enforced conditional write does not keep the feature
disabled.** It selects a lower guarantee tier. This is a deliberate amendment:
the original text made conditional upload a precondition, the 2026-08-15
live-network spike measured its absence on Drive, and FR-7 was rewritten to stop
depending on it rather than to declare the problem solved. Drive still has no
compare-and-swap; the spec no longer needs one.

## Guarantee by backend category

FR-7 is expressed in `get` + `put` only, so it holds on any storage backend.
Backends that offer more raise the guarantee without changing the coordinator.

| Backend category | Capabilities | Lost update prevented? | Overwritten content recovered from | Window |
| --- | --- | --- | --- | --- |
| **CAS** | conditional write (+ usually version history) | **yes**, server rejects the stale write | not needed; the write never lands | closed |
| **Versioned** | version history, no conditional write | no | the server's own previous revision, immediately | ~100s of ms |
| **Bare** | `get`/`put` only | no | the overwritten device's local merged state, on its next sync | ~100s of ms |

In every category the lost update is **detected**, and in no category is it
**destructive** — the FR-7 invariant guarantees the overwritten state still
exists locally on the device that produced it. The categories differ only in how
fast and from where the overwritten content is recovered.

The coordinator, the use cases and the merge adapter are identical across all
three. Capabilities are declared by the storage adapter (spec 010), consumed by
the data-layer repository, and never branch domain or presentation logic.

## Architecture and secret boundary

Clean Architecture dependency direction is mandatory:

```text
UI/BLoC -> SyncMergeCoordinator -> domain use cases -> SyncMergeRepository port
                                                        ^
                                                        |
                                      data repository implementation
```

- Domain defines `SyncMergeRepository` and focused use cases for start review,
  update decision, commit, cancel, invalidate, recover pending upload and load one
  transient field display.
- Data implementation resolves credentials from existing secure/local/registry/
  security data sources. It alone owns `KdbxFile`, decrypted values, attachments,
  object UUID mapping, checksums/tokens, canonical paths and private session store.
- `SyncMergeCoordinator` imports domain only. It may hold opaque session ID,
  redacted decision IDs/enums and sequencing/cancellation state. It never resolves
  credentials and never owns data repository internals, plaintext or plaintext
  handles.
- BLoC/events/state contain opaque session/decision IDs, counts, categories,
  choices and safe outcome codes only.
- Field widget obtains one `MergeFieldDisplay` directly through domain
  `LoadSyncMergeFieldDisplayUseCase(sessionId, decisionId)`. Plaintext exists only
  in widget-local ephemeral state; response is non-Equatable, non-serializable,
  redacted in `toString`, and cleared on widget disposal/lock. Coordinator and
  BLoC never receive it.
- UI, coordinator and domain never import data-layer types.

Credentials remain data-owned: data repository resolves master password from
`data/datasources/secure_data_source.dart`, persisted key-file path through
database registry/security repositories, and cached fallback through
`local_data_source.dart` only for matching active database. `VaultKdbxService`
reads key-file bytes. Password, key-file path/bytes and credential lease never
cross data port.

All secret-bearing responses are excluded/redacted from `Equatable.props`,
`toString`, logs and serialization. Errors expose safe codes only. Dart managed
memory cannot guarantee zeroization; references/copies must be minimized.

## Functional requirements

### FR-1 — Full-fidelity merge adapter

Data-layer adapter uses opened KDBX object graph or another Gate 0-proven
full-fidelity representation. It must not rebuild whole database from
`VaultSnapshot` and must not call unfinished `KdbxFile.merge`.

Preserve all library-supported semantics:

- root/group UUIDs, hierarchy, moves, order where supported, group fields/times;
- live entries, recycle-bin contents and permanent tombstones;
- all strings with presence, original key spelling and protected/plain status;
- attachment name, exact bytes, inline/reference and protection properties;
- history, times, colors, tags, override URL, auto-type and custom data;
- custom icons/references;
- metadata/settings, recycle-bin settings, history limits, header/KDF/cipher and
  original credentials.

Serialized candidate is reopened with original credentials and semantic manifest
validated before target replacement.

### FR-2 — Lineage

Local and remote root-group UUID must match before session is returned. Drive
mapping/file ID is insufficient. `wrongLineage` causes no session, backup, local
write or upload.

Before diff, data adapter validates each side independently:

- every live root/group/entry UUID is non-nil;
- live UUIDs are globally unique across every group and entry on that side, not
  only within one collection or parent;
- duplicate-entry, duplicate-group and group-entry UUID collisions are invalid;
- when one live UUID appears on both sides, object kind must match (`group` with
  `group`, `entry` with `entry`).

Violation returns `unsupportedKdbxData` before session/write/upload. Raw UUID or
object labels never enter logs/state. Tests include duplicate entry UUID,
duplicate group UUID, group-entry collision, nil UUID and cross-side kind
mismatch.

### FR-3 — Entry/group diff

Match entries/groups by KDBX UUID, never title/path. One-sided records/groups are
automatic union members. Conflicting fields use newer KDBX modification time;
tie/unknown defaults local and UI marks uncertainty. Notes may choose deterministic
`local + "\n\n---\n\n" + remote`.

### FR-4 — Field-level presence semantics

Presence is independent from value. Empty string/zero-byte attachment counts as
present. Rules apply inside same entry/group UUID, including custom fields and
attachments.

| Local | Remote | Explicit field deletion evidence | Classification | Result/default |
| --- | --- | --- | --- | --- |
| present, equal | present, equal | none | identical | preserve one semantic value |
| present, different | present, different | none | `fieldConflict` | explicit local/remote choice |
| present | missing | none | `fieldLocalOnly` | preserve local automatically |
| missing | present | none | `fieldRemoteOnly` | preserve remote automatically |
| missing | missing | none | absent | emit no field |
| present | missing | remote deletion marker proven by adapter | `fieldDeletionConflict` | default preserve; explicit keep/delete |
| missing | present | local deletion marker proven by adapter | `fieldDeletionConflict` | default preserve; explicit keep/delete |

Current KDBX field/attachment absence has no built-in tombstone unless Gate 0
proves otherwise; therefore missing custom field/attachment is normally union,
not deletion. Future explicit field deletion metadata is honored only after
adapter support and policy test.

**Prefer local/remote never selects `null`, missing data, or missing plaintext
handle.** For one-sided field it preserves present side regardless of preferred
shortcut. For explicit deletion conflict it maps side state to explicit
`keep`/`delete`; it never infers delete from absence.

### FR-5 — Record deletion/tombstones

- Live one side + absent other without matching tombstone: preserve live record.
- Live one side + matching tombstone other: `deletionConflict`, default **Keep**,
  explicit **Keep/Delete** required.
- Recycle-bin one side + live other: explicit deletion/move-to-bin conflict.
- Tombstoned both sides: remain deleted; preserve newest supported deletion data.
- **Keep** emits live record and removes/neutralizes matching tombstone.
- **Delete** emits no live/recycle-bin object and retains valid tombstone.
- Recycle-bin move, permanent tombstone and ordinary absence remain distinct.
- Unclassifiable state returns `unsupportedKdbxData`; never guess or resurrect.

### FR-6 — Shortcuts

**Prefer local** and **Prefer remote** set only actual conflict decisions and jump
to confirmation. They preserve all record-level and field-level one-sided data.
Both use lineage, staleness, backup, atomicity and FR-7 write-verify gates.

### FR-7 — Staleness preconditions and write-verify-converge

Data-private session captures exact local source checksum, canonical path, remote
file identity, remote checksum, root UUID, session generation and — **only when
the storage adapter declares `conditionalWrite`** — a server concurrency token.
None appears in coordinator/BLoC state except opaque IDs.

**Founding invariant. Locally merged state is never discarded until the remote
has been read back and proven to contain it.** Every rule below exists to serve
this invariant; no optimization may weaken it.

The remote write follows one storage-agnostic cycle. It requires only `get` and
`put`, so it is implementable on every backend:

1. **Read** the remote and record its checksum as the expected base.
2. **Merge** locally against that base.
3. **Revalidate under the per-database mutex, immediately before writing**:
   recompute the local checksum and re-read the remote checksum. Local mismatch
   returns `staleLocal`; remote mismatch returns `staleRemote`, and neither
   writes anything. This step exists to shrink the race window from the duration
   of the user's review — minutes — to the few hundred milliseconds between the
   re-read and the write.
4. **Write** the merged bytes.
5. **Verify**: re-read the remote and compare its checksum to the merged
   checksum.
   - equal → the write is confirmed applied; finalize.
   - different → another writer overwrote us. Fetch that content, merge it
     against the retained local merged state, and repeat from step 3.

Step 5 is mandatory on every backend and is the only source of truth about
whether a write landed. A `2xx` response is a claim, not a confirmation.

Consequence, to be stated plainly rather than hidden: **on a backend without
conditional write the lost update is not prevented — it is made non-destructive.**
The device that gets overwritten still holds its merged state locally by the
invariant above, detects the divergence at step 5 or at its next sync, and
re-proposes it. The union converges by mutual detection rather than by mutual
exclusion.

The convergence retry is bounded: after a spec-declared retry budget the session
ends as an unresolved conflict, retaining the local merged file and the dated
backup, and never marking the mapping synced. Convergence must not loop forever
against a remote peer writing continuously.

Optional capabilities are layered on top of this cycle without replacing it:

| Declared capability | Effect on the cycle |
| --- | --- |
| `conditionalWrite` | Step 4 sends the concurrency token; the server rejects a stale write, so the window closes entirely and step 5 confirms rather than repairs. |
| `versionHistory` | Step 5's divergence branch fetches the exact overwritten revision from the server instead of waiting for the other device to resynchronize. |
| neither | The cycle runs unchanged with the base guarantee. |

The concurrency token is **optional** and is used only where the adapter declares
`conditionalWrite`. Its absence changes the guarantee tier, never the flow. A
preflight check alone was never sufficient and still is not — on a CAS backend
the token enforces the precondition, and on every backend step 5 verifies it.

### FR-8 — Writer inventory and per-database serialization

Before mutex implementation, Gate report inventories every KDBX/database-path
writer. Inventory includes current:

- all `VaultKdbxService` mutations and credential-change rollback paths;
- `DatabaseSyncOrchestrator.syncNow` replacement/backup paths;
- `DatabaseImportService` import, staged commit/finalize/rollback, managed replace,
  move and create paths;
- `DatabaseSessionCoordinator` create/import/replace/delete flows;
- `VaultSessionCoordinator.updateDatabaseSettings` credential/settings write,
  database rename and rollback;
- direct KDBX exports/copies in `database_selection_screen.dart` and
  `vault_navigation.part.dart`.

Direct presentation-layer file writes are moved behind domain/data ports before
mutex gate can pass.

One singleton database-path mutex is shared by every inventoried KDBX mutation,
import, replace, create, delete, export snapshot, settings change, rename, manual
sync, auto-sync and merge commit.

Path identity normalizes absolute path, separators, `.`/`..`, existing symlinks,
non-existing target parent, platform case behavior and file aliases. If reliable
file identity/hard-link detection is unavailable, platform uses coarse global
database mutex rather than unsafe per-path concurrency.

Rename acquires old and new canonical identities together in deterministic sorted
order and holds them through file move plus registry/security/sync-mapping updates
and rollback. Tests cover relative/absolute aliases, symlinks, case aliases,
hard links where supported and inverse concurrent renames.

Review holds no mutex; edits may make review stale. Commit holds mutex from final
revalidation through backup, replace, upload/recovery persistence and mapping
update. Same-database edits/sync queue; different databases may proceed only when
identity resolver proves distinct.

Lock/cancel semantics:

- cancel/lock before atomic boundary aborts and writes nothing;
- after atomic replace dispatch, never roll back automatically; finish durable
  upload outcome/recovery bookkeeping while UI remains locked;
- database switch/new session invalidates stale callbacks/events.

### FR-9 — Collision-safe backup and atomic local commit

After fresh preconditions and under mutex:

1. Write backup through exclusive-create same-directory temp.
2. Final name:
   `<name>.<yyyyMMdd-HHmmss-ffffff>.<suffix>.pre-merge.kdbx`, where suffix is
   collision-resistant random or monotonic counter.
3. Final backup creation is no-overwrite. Existing backup is never truncated or
   replaced; collision retries with new suffix.
4. Flush/fsync, close, atomic finalize and verify backup size/checksum.
5. Only after verified backup, serialize/write same-directory target temp,
   flush/fsync/close, recheck session, atomically replace without delete-first.
6. Sync directory metadata where target runtime supports it.

Tests freeze clock to same microsecond and precreate colliding names; every backup
survives with unique content. Backup failure prevents target write.

**On a backend without `conditionalWrite` the verified backup is part of the
guarantee, not a precaution.** FR-7 cannot prevent a concurrent overwrite there;
it can only guarantee the overwritten state survives locally. The dated pre-merge
backup and the retained local merged file are that survival. Therefore, on such a
backend, backup verification failure is a hard stop for the whole merge — not
only for the local write — and the session ends with no remote write attempted.
Skipping or best-efforting the backup would downgrade "detected but never
destructive" to "silently destructive", which the invariant forbids.

Atomic capability is platform-qualified. Each enabled platform must produce its
own harness artifact showing process interruption and injected temp-write/flush/
rename failures leave old or full new target, never missing/truncated. macOS host
unit tests do not qualify any other platform. Feature defaults disabled per
platform until matching artifact passes.

### FR-10 — Remote write outcomes and restart recovery

Before the FR-7 step-4 write, persist non-secret `pendingUpload` recovery record
containing merged checksum, expected old remote checksum, local committed
checksum and — only on a `conditionalWrite` adapter — the expected old token.
Then attempt the write.

The three outcome classes are unchanged. What changed is which of them a given
backend can produce, and what the client is allowed to conclude from each.

| Outcome | Available on | Meaning | Mandated action |
| --- | --- | --- | --- |
| **Certain rejection** | **`conditionalWrite` adapters only** | Server refused a stale precondition; certainly not applied | Refetch and surface stale/new conflict. Never retry against the freshly observed token. |
| **Apparent success** | every backend | The response claims success; on a non-CAS backend it also carries no proof that a concurrent writer did not land between our read and our write | **Not** terminal. Run FR-7 step 5. Equal checksum → finalize mapping and clear the recovery record. Different → convergence retry. |
| **Ambiguous** | every backend | Transport timeout/disconnect after dispatch; the request may have applied | Never blindly retry, never mark failure or success. Enter the recovery triage below. |

Two amendments follow from this table and must not be read past:

- A certain rejection **only exists on a CAS backend**. On any other backend the
  absence of a rejection is not evidence that nothing was overwritten, and the
  client must never treat it as such.
- A success response is renamed from "definite success" to "apparent success"
  precisely because it is not definite. The FR-7 step-5 read-back — not the
  response status — is what promotes it to confirmed.

Ambiguous recovery, including after app restart. The triage is unchanged in
substance; only its **trigger** widens. It previously ran on a transport
ambiguity alone; it now also runs whenever an apparent success fails its step-5
verification and the session is interrupted before the convergence retry
completes. Both entry points execute the same steps:

1. Acquire same per-database mutex used by every writer.
2. Read current local bytes and compare checksum to persisted
   `localCommittedChecksum` **before remote fetch/triage and before any vault
   mutation**.
3. Local mismatch -> `staleRecoveryLocal`; perform no upload, retry,
   finalization, mapping-success update or vault mutation. Retain dated backup and
   pending evidence, then require fresh conflict from current local/remote state.
4. Only when local checksum matches, refetch remote metadata/bytes.
5. Remote checksum equals merged checksum -> upload applied; finalize mapping.
6. Remote checksum still equals the expected old value -> the write was not
   applied; safely re-enter FR-7 from step 3. On a `conditionalWrite` adapter the
   token is re-sent; on any other adapter the re-read at step 3 plus the
   verification at step 5 carry the safety.
7. Any third checksum state -> remote changed independently; retain local
   merged file + dated backup and open new conflict. On a `versionHistory`
   adapter the overwritten revision is additionally fetched and offered as the
   remote side of that new conflict, instead of waiting for the other device.

Recovery record clears only after verified finalization or handoff to new
conflict. Mapping never claims synced while ambiguous, and never claims synced on
an unverified apparent success. Local merge is never auto-rolled back — this is
the invariant, restated at its most dangerous point.

### FR-11 — UI, scale and golden inventory

UI/goldens start only after data safety gates pass. Review states one-sided data
is preserved and nothing written yet. Conflict status remains persistent; auto
sync never opens modal while typing. At >200 conflicts show shortcuts only.
Scale test generates data in memory unless binary fixture is required by KDBX
coverage.

Exact golden inventory:

| # | Filename | State | Size | Theme |
| --- | --- | --- | --- | --- |
| 1 | `sync_merge_review_phone_light.png` | mixed one-sided/field/deletion review | 390×844 | light |
| 2 | `sync_merge_review_phone_dark.png` | same review | 390×844 | dark |
| 3 | `sync_merge_field_text_phone_light.png` | text conflict + same timestamp | 390×844 | light |
| 4 | `sync_merge_field_secret_phone_dark.png` | protected values masked | 390×844 | dark |
| 5 | `sync_merge_field_attachment_phone_light.png` | one-sided attachment preserved | 390×844 | light |
| 6 | `sync_merge_ready_phone_light.png` | Prefer local + union summary | 390×844 | light |
| 7 | `sync_merge_recovery_phone_dark.png` | ambiguous upload recovery | 390×844 | dark |
| 8 | `sync_merge_scale_phone_light.png` | 250 conflicts, shortcuts only | 390×844 | light |
| 9 | `sync_merge_review_tablet_light.png` | mixed review, two-pane | 1024×768 | light |
| 10 | `sync_merge_review_tablet_dark.png` | mixed review, two-pane | 1024×768 | dark |
| 11 | `sync_merge_field_tablet_light.png` | field diff, two-pane | 1024×768 | light |
| 12 | `sync_merge_ready_tablet_light.png` | ready summary | 1024×768 | light |

Golden test declares one case table and asserts `cases.length == 12` before
matching all filenames. Dynamic behavior uses named widget assertions instead:

- `merge progress hides cancel after atomic boundary`;
- `field plaintext is absent after widget dispose and lock`;
- `background conflict remains status and opens no modal`;
- `Prefer local and Prefer remote never remove one-sided rows`.

Required layout/semantics matrix supplements goldens. Every named test pumps exact
size/theme, calls `tester.takeException()` after settle and asserts no
`RenderFlex overflowed` or other layout exception plus listed semantic roles.

| Exact test name | Screen | Size | Theme | Required semantic roles |
| --- | --- | --- | --- | --- |
| `review phone light has no overflow and exposes merge review roles` | review | 390×844 | light | review heading, preserved-one-sided status, Prefer local, Prefer remote, conflict sections, nothing-written status |
| `review phone dark has no overflow and exposes merge review roles` | review | 390×844 | dark | review heading, preserved-one-sided status, Prefer local, Prefer remote, conflict sections, nothing-written status |
| `review tablet light has no overflow and exposes merge review roles` | review | 1024×768 | light | review heading, preserved-one-sided status, Prefer local, Prefer remote, conflict sections, nothing-written status, two-pane container |
| `review tablet dark has no overflow and exposes merge review roles` | review | 1024×768 | dark | review heading, preserved-one-sided status, Prefer local, Prefer remote, conflict sections, nothing-written status, two-pane container |
| `field phone light has no overflow and exposes field decision roles` | field | 390×844 | light | field heading/category, local choice, remote choice, preserved-missing status, masked-secret action |
| `field phone dark has no overflow and exposes field decision roles` | field | 390×844 | dark | field heading/category, local choice, remote choice, preserved-missing status, masked-secret action |
| `field tablet light has no overflow and exposes field decision roles` | field | 1024×768 | light | field heading/category, local choice, remote choice, preserved-missing status, masked-secret action, two-pane container |
| `field tablet dark has no overflow and exposes field decision roles` | field | 1024×768 | dark | field heading/category, local choice, remote choice, preserved-missing status, masked-secret action, two-pane container |
| `ready phone light has no overflow and exposes merge commit roles` | ready | 390×844 | light | ready heading, union counts, editable decisions, backup status, remote-write verification status, commit action |
| `ready phone dark has no overflow and exposes merge commit roles` | ready | 390×844 | dark | ready heading, union counts, editable decisions, backup status, remote-write verification status, commit action |
| `ready tablet light has no overflow and exposes merge commit roles` | ready | 1024×768 | light | ready heading, union counts, editable decisions, backup status, remote-write verification status, commit action, two-pane container |
| `ready tablet dark has no overflow and exposes merge commit roles` | ready | 1024×768 | dark | ready heading, union counts, editable decisions, backup status, remote-write verification status, commit action, two-pane container |

Parameterized widget test asserts matrix length `12`, unique names and execution
of all rows. “Heading” requires header semantics, actions require enabled/disabled
button or radio semantics as appropriate, statuses require labeled read-only
semantics (live region only for changing progress), and two-pane requires both
navigation/list and detail landmark containers.

## Acceptance criteria

1. Gate 0 including T008 report passes before domain freeze.
2. KDBX 3/4 semantic round-trip passes with password-only and password+key file.
3. No call to unfinished `KdbxFile.merge`.
4. Coordinator imports domain only and holds no credentials, data types,
   plaintext, plaintext handles, KDBX object, path/checksum/token or private store.
5. BLoC/events/state serialization/logs contain no password, key path/bytes,
   plaintext field/attachment data or plaintext handle.
6. Wrong root UUID fails before session/write/upload.
7. Duplicate entry/group UUID, group-entry collision, nil live UUID and cross-side
   kind mismatch fail as `unsupportedKdbxData` before session/write/upload.
8. Record and field presence truth tables pass, including local-only/remote-only
   custom fields and attachments inside same entry UUID under every shortcut.
9. Missing side is never selected as null; deletion requires explicit evidence
   and explicit choice/policy. No resurrection by ambiguity.
10. Local/remote stale preconditions fail safely, and the FR-7 revalidation runs
    inside the mutex immediately before the write on every backend, with or
    without a concurrency token.
11. Writer inventory is complete; import/replace/create/settings/rename/export/
    sync/edit all share path mutex. Alias and deterministic two-path rename tests
    pass.
12. Backup same-microsecond/preexisting-name collisions never overwrite; backup
    must verify before destructive write.
13. Disk/temp/flush/rename failures preserve old or full new target; enabled
    platform has its own passing harness artifact.
14. Concurrent save/sync/auto-sync/merge serializes; lock before boundary leaves
    target untouched; post-boundary lock reaches safe terminal bookkeeping.
15. Certain rejection (CAS adapters only), apparent success and ambiguous timeout
    each follow the required FR-10 branch. An apparent success is never treated
    as terminal without the FR-7 step-5 read-back.
15a. **Invariant test**: locally merged state is never discarded before a
    read-back proves the remote contains it. Asserted on the success path, the
    divergence path, the ambiguous path and the restart path.
15b. **Convergence test**: with the remote overwritten by a simulated concurrent
    writer between step 3 and step 5, the session detects the divergence,
    re-merges against the observed remote content and converges without losing
    either side's records. The same test with the retry budget exhausted ends as
    an unresolved conflict, retains the merged local file and the dated backup,
    and does not mark the mapping synced.
15c. **Capability-parity test**: the coordinator, use cases and merge adapter
    produce identical decisions against a CAS adapter, a `versionHistory`
    adapter and a bare `get`/`put` adapter. Only the guarantee tier reported to
    the user differs. No domain or presentation code branches on a capability.
15d. On a backend without `conditionalWrite`, backup verification failure aborts
    the whole merge and attempts no remote write.
16. Restart recovery acquires database mutex and checks current local checksum
    against `localCommittedChecksum` before remote triage/mutation. Mismatch returns
    `staleRecoveryLocal`, retains backup, performs no upload/finalization and
    requires fresh conflict.
17. Matching-local restart recovery executes remote checksum triage — plus token
    triage where the adapter declares `conditionalWrite` — and finalizes,
    retries, or starts new conflict correctly.
18. Upload failure/ambiguity keeps merged local + dated backup and never marks
    synced prematurely.
19. Result reopens with original password+key file and matches semantic parity for
    chosen shortcut plus all one-sided data.
20. In-memory 250-conflict test shows shortcuts-only path.
21. Golden table count is exactly 12; 12-row size/theme semantic assertion matrix
    and named dynamic assertions pass only after criteria 1–19.

## Out of scope / residual limits

- True three-way merge requires stored common ancestor.
- Library-unsupported KDBX constructs remain merge-blocking.
- Native durability code is not added here. Failed target artifact requires
  platform specialist before enabling target.
- Dart managed secrets cannot be guaranteed zeroized.
- On a backend without `conditionalWrite` the lost update is **not prevented**.
  FR-7 guarantees only that it is detected and non-destructive. Preventing it
  would require a capability Google Drive does not offer — measured, see the
  feasibility report — and no client-side construction substitutes for it.
- The FR-7 window is narrowed to the revalidate-then-write interval, not
  eliminated. Two devices writing inside that interval both converge, but the
  user may see one extra conflict round.
- The storage-capability port itself is **spec 010**. 008 consumes the
  capabilities; it does not define the multi-provider abstraction.
