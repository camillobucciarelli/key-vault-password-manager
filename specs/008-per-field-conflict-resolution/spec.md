# 008 — Per-field sync conflict resolution

**Status**: Draft · **Gate 0 OPEN**. The 2026-08-15 close was reverted on
independent review: the exit bar was rewritten in the same commit that declared
it met, and the replacement mechanism — the FR-7 write-verify-converge cycle — is
itself `not-run`. Gate 0 now closes on **T009**, the model validation of that
cycle. **T201 and the domain freeze stay blocked.** Feature also stays disabled
per platform until Gate 1 atomicity artifacts  
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
harness per platform. Gate report task **T008** and cycle-validation task
**T009** are both part of Gate 0 and must both pass before the domain model
freezes.

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

10. **Validate the write-verify-converge cycle as a model**, before any
    implementation depends on it. In-memory only: no network, no filesystem, no
    KDBX. Simulate N devices against a shared remote under adversarial
    interleavings and assert the cycle's properties — convergence to a stable
    state in a bounded number of rounds, no loss of one-sided records or fields
    under any interleaving, no oscillation on a timestamp tie, termination when
    the semantic union is already complete, and survival of explicit user
    decisions across a re-merge. Task **T009**; artifact
    `test/features/password_manager/data/services/sync_merge_convergence_model_test.dart`.

**A backend without server-enforced conditional write does not keep the feature
disabled.** It selects a lower guarantee tier.

This is a **proposed amendment, not a derivation.** It must be read as such: the
original Gate 0 bar was *"prove server-enforced Drive conditional upload"*, the
2026-08-15 live-network spike measured its absence, and the bar was then rewritten
to *"measure the capability; a negative measurement is a valid Gate 0 result"* —
in the same commit that declared the rewritten bar satisfied. Rewriting an exit
criterion is a legitimate response to a measurement. Declaring the new criterion
met by the act of writing it is not, and the 2026-08-15 close was reverted on that
ground.

The amendment stands or falls on item 10 above. Drive has no compare-and-swap:
measured, and not in dispute. What is not yet established is that the replacement
— a cycle expressed in `get` + `put` — actually converges. Reading the first draft
of it found three defects that each prevented convergence: an expected base that
was never re-anchored, a byte comparison with no semantic arbiter, and a
perspective-dependent tie-break. All three are corrected above, and none of them
was caught by a test, because no test existed. Gate 0 does not close on the
argument that the cycle converges; it closes on T009 executing that argument.

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

**With one condition, which belongs in this table rather than in a footnote.**
Outside the CAS row, recovery is performed *by the overwritten device*, so it
requires that device to resynchronize. A device that never returns takes its
contribution with it, permanently and silently. `versionHistory` shortens the
wait but does not remove the dependency, because nothing triggers a revision
fetch that no device reports as missing. Only the CAS row is unconditional, and
it is unconditional for a different reason: the write never lands, so there is
nothing to recover. See "Out of scope / residual limits".

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
automatic union members. Conflicting fields use newer KDBX modification time.

**The default is decided by a globally deterministic total order, never by the
observer's perspective.** "Prefer local" as a tie-break is forbidden: it makes
the merge function non-commutative, so two devices holding the same pair of
candidates choose opposite winners, write over each other and oscillate
indefinitely — across sync sessions, where the FR-7 retry budget cannot stop
them. KDBX modification times have one-second granularity, so a tie is an
ordinary event, not an exotic one.

The order is defined once, in the data layer, over the pair
`(modification time, value)`:

1. **a known modification time beats an unknown one.** An unknown timestamp is
   the absence of evidence and never outranks evidence;
2. otherwise the **newer** known modification time wins;
3. on equal known times — and when **both** timestamps are unknown — compare the
   candidate values as their **UTF-8 encoded byte sequences**, lexicographically,
   unsigned, shortest-is-smaller on a common prefix, and **the greater byte
   sequence wins.**

The encoding in rule 3 is **UTF-8, and no other**. Naming it is not pedantry: it
is the difference between two distinct total orders. UTF-16 — which is what a
Dart `String`'s `codeUnits` are, and what a naive implementation reaches for —
encodes an astral character as a surrogate pair in `U+D800..DFFF`, which sorts
**below** the BMP range `U+E000..FFFF`; the same character's UTF-8 bytes, and its
code point, sort **above** it. So an emoji in a notes or title field, compared
against a character in `U+E000..FFFF`, elects **opposite winners** under the two
encodings. Two devices that disagree on the encoding disagree on the winner, and
the tie-break's whole purpose — that both sides pick the same value from the same
unordered pair — is gone. UTF-8 is chosen because it is order-preserving over
code points, so the byte order and the code-point order are one relation.

Rule 1 is not decoration. Treating an unknown timestamp as a bare tie — sending
the pair straight to the value comparison — makes the relation non-transitive,
and a non-transitive relation is not a total order, so the merge stops being
associative. With `A = (t5, "x")`, `B = (unknown, "y")` and `C = (t3, "z")`,
`(A ⊔ B) ⊔ C` yields `"z"` and `A ⊔ (B ⊔ C)` yields `"x"`: two devices that
merged the same three sides in different orders hold different values, which is
the failure mode set out for notes below.

The choice of "greater" in rule 3 is arbitrary by design; what matters is that
the order is fixed, total and computed from the data alone. Both devices compare
the same unordered pair `{A, B}` and therefore select the same winner, so the
merge function is commutative on ties and the cycle converges. Equal values with
equal timestamps are not a conflict, so the order is strict wherever it is
consulted.

**The winning side's timestamp travels with the winning value**, so the merged
field is itself a member of the ordered set and can be merged again without
special-casing.

Comparison uses the decrypted value bytes and therefore runs inside the data
layer only; no candidate value, and no indication of which side won, crosses the
domain port. The UI still marks the decision as uncertain and still offers an
explicit override — the tie-break governs only the **default**, and an explicit
user choice supersedes it under FR-7's sticky-decision rule.

Ordering by the involved object UUIDs is explicitly rejected: in a field
conflict both candidates sit under the same entry UUID and the same field key,
so the UUID does not discriminate them. Only the values do.

#### Notes are an ordered union of segments, not a concatenation

Notes may keep both sides. The operation is **not** a binary concatenation. It is
an **ordered, deduplicated union of segments**:

1. split each side on the separator `"\n\n---\u241E---\n\n"` into segments;
2. take the **set** union of the segments of both sides, discarding empty ones;
3. sort the result by the same total order used for the tie-break — rule 3
   above, over the segments' UTF-8 bytes. It is the **same comparator**, not a
   second string ordering that happens to agree: a segment order that drifted
   from the tie-break order would make two devices disagree on the merged notes
   while agreeing on every other field;
4. join with the same separator.

A concatenation whose operand order is merely *fixed* is deterministic and still
**not associative**, which is enough for two devices and wrong for three. With
three tied notes `zeta`, `alpha`, `mike`, a fixed-order concatenation gives
`(A‖B)‖C = alpha‖zeta‖mike` and `A‖(B‖C) = alpha‖mike‖zeta`. Two devices that
merged the same three sides in a different order then hold different Notes
values, so their canonical manifests differ, **the FR-7 semantic short-circuit
stops firing**, and the following merge concatenates the concatenations and
**duplicates text the user wrote**. On a password manager, Notes is where
recovery codes are kept; silent duplication of that field is not cosmetic.

An ordered deduplicated union is associative, commutative and idempotent — a
join-semilattice — which is exactly the property the convergence cycle needs.
Idempotence is the part that stops the duplication: merging an already-merged
value with either of its inputs, or with itself, returns it unchanged.

Concatenating as `local + remote` remains forbidden for the perspective reason
above; it is now also forbidden as a *shape*, whatever the operand order.

##### The separator is a sentinel, and why

The separator is **not** a plain Markdown thematic break. It is
`"\n\n---\u241E---\n\n"`, carrying `U+241E SYMBOL FOR RECORD SEPARATOR` (`␞`)
between two rules.

The first draft used `"\n\n---\n\n"`, and the cost of that choice was declared
here as "a merge may reorder them". That declaration was **incomplete**, and
under-declaring a data-loss defect is worse than not declaring it. The plain
separator inflicted **two** distinct damages on a user who wrote a thematic
break in their own notes:

1. **Insertion, not merely reordering.** The other device's text was sorted
   *between* the user's own paragraphs. With local
   `"Zeta account recovery codes ¶ --- ¶ Alpha backup email"` and remote
   `"Mike says rotate this quarterly"`, the result is
   `alpha backup email · mike says… · zeta account recovery codes`: the peer's
   sentence lands in the middle of a note the user wrote as one block.
2. **Silent deletion.** The union is over a **set**, so segments the user
   legitimately repeated collapse. `"TODO ¶ --- ¶ rotate key ¶ --- ¶ TODO"`
   merged against `"zzz"` returns three segments, not four: one of the two
   `TODO`s is gone. This is not reordering — it is loss of text the user wrote,
   in the field where recovery codes are kept.

The union property is a property of the **set union**, not of the delimiter, so
restricting the delimiter costs nothing: associativity, commutativity and
idempotence are unaffected. `U+241E` is chosen because it is printable — so the
fused field still reads as a rule rather than running two notes together
invisibly — while appearing on no keyboard layout and carrying no meaning in
prose, so it does not occur in a notes field by accident. The `---` on either
side keeps the merged result legible.

With the sentinel, ordinary user text splits into exactly **one** segment. The
field is an atom: it cannot be opened and interleaved, and none of its
paragraphs can be deduplicated against another. Both damages above are
eliminated for it. Asserted in the T009 model as "the sentinel separator leaves
ordinary user text intact", with each damage paired against a demonstration
that it was real under the old separator.

No compatibility question arises: no implementation has ever written the old
separator — FR-3 is behind Gate 0 and the notes merge exists only as a model —
so there is no stored data to migrate.

Residual cost, now stated completely:

- a user who types `␞` between two rules is still split into segments, and for
  that text both damages above remain possible. Nothing eliminates this; the
  sentinel makes it a case that cannot be reached by writing ordinary Markdown;
- splitting is only ever applied to a field that is **already in conflict**, and
  a field with no conflict is never rewritten;
- the operation is idempotent, so it does not degrade further on each sync.

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

1. **Read** the remote and record its checksum as the **expected base**.
2. **Merge** locally against that base.
3. **Revalidate under the per-database mutex, immediately before writing**:
   recompute the local checksum and re-read the remote checksum. Local mismatch
   returns `staleLocal`; a remote checksum differing from the **current expected
   base** returns `staleRemote`, and neither writes anything. This step exists
   to shrink the race window from the duration of the user's review — minutes —
   to the few hundred milliseconds between the re-read and the write.
4. **Write** the merged bytes.
5. **Verify**: re-read the remote and compare its checksum to the merged
   checksum. The comparison is on **bytes**, deliberately: a byte comparison
   detects an overwrite with no false negatives, which a semantic comparison
   could not.
   - **equal** → the write is confirmed applied; finalize.
   - **not executable** — the re-read times out, disconnects or otherwise fails
     to yield a checksum → the outcome is neither equal nor different. It is
     classified **`ambiguous`** and enters the FR-10 recovery triage. It is never
     finalized and never treated as a divergence.
   - **different** → run the divergence branch below.

Step 5 is mandatory on every backend and is the only source of truth about
whether a write landed. A `2xx` response is a claim, not a confirmation.

#### The divergence branch — how the cycle actually converges

Reaching this branch means the bytes at the remote are not the bytes we wrote.
Three things must happen, in this order, and each exists to stop a specific way
the cycle would otherwise fail to terminate.

1. **Re-anchor the expected base.** The expected base becomes the checksum of
   the content just observed at step 5. It is *not* the base recorded at step 1.
   Without this re-anchoring the retry aborts at its own step 3 — the remote no
   longer matches a base captured before the other writer landed, so every retry
   returns `staleRemote` and the session always terminates as an unresolved
   conflict. The re-anchor is what makes the loop a loop.
2. **Short-circuit on semantic equivalence.** Before merging anything, compare
   the **canonical semantic manifest** of the observed remote content against the
   manifest of our retained merged state, using the same manifest that FR-1
   validates — salts, master seed, IVs, ciphertext and `HeaderHash` excluded.
   - manifests **equal** → the union is already complete on the remote. This is
     not a divergence: the other writer's bytes carry exactly our semantic
     content. Finalize, and do not write again. Without this test two devices
     whose merged content is semantically identical still produce different bytes
     — different salts and IVs on every serialization, as required by
     "Approved product behavior" — see each other as divergent forever, and burn
     the whole retry budget re-writing a conflict that does not exist.
   - manifests **different** → continue to step 3 below.
   The byte comparison remains the **detector**; the semantic manifest is the
   **arbiter**. Neither replaces the other.

   **Safety invariant — manifest completeness.** The correctness of this
   short-circuit rests entirely on the canonical manifest covering every
   semantically meaningful field defined by FR-1. **Any semantic field omitted
   from the manifest is a field on which a real divergence is finalized in
   silence**, because two states differing only in that field compare equal here
   and the round ends without merging it. The manifest is therefore defined by
   exclusion from a closed list — salts, master seed, IVs, ciphertext,
   `HeaderHash` — and never by inclusion of a hand-maintained field list. Adding
   a semantic field to FR-1 without adding it to the manifest is a data-loss
   defect, not an omission.
3. **Re-merge, preserving the user's decisions.** Merge the observed remote
   content against the retained local merged state, then repeat from step 3 of
   the cycle against the re-anchored base.

#### Explicit user decisions are sticky across a re-merge

The re-merge in the divergence branch is automatic, and FR-3's LWW default must
never be allowed to silently reverse a choice the user already made under FR-4.

- Every explicit user decision is recorded in a session-lived decision ledger
  keyed by the object UUID plus the field key or attachment name, and is
  **re-applied after every re-merge**. LWW, the FR-3 deterministic tie-break and
  the shortcuts all lose to a recorded explicit decision. A decision the user
  made once is never silently reversed by a later automatic round.
- **Invariant — a replayed decision must name one of the two candidates now on
  the table.** Formally: for every ledger entry applied to a field, `decided ∈
  {local.value, remote.value}`. The replay is implemented as "the side whose
  value equals the decision"; if the decision matches **neither** side, that
  reduces to *"take whichever side is second"* — a result that depends on which
  device is called local, which is defect C4's class of error relocated into the
  ledger branch, and which discards the user's recorded decision **in silence**.
  Measured on the model: 22678/30000 randomized pairs violate commutativity in
  that state, against 0/30000 when the decision is live on one side.

  This state is **unreachable today**, and it is unreachable for exactly two
  reasons, neither of which is a property of the ledger code itself:

  1. **FR-4** guarantees a recorded decision is always one of the two values
     presented to the user;
  2. the ledger is **session-lived**, so it cannot carry a decision forward to a
     later pair of candidates it was never taken over.

  **Changing either one reopens the defect**, and it reopens as silent data
  loss rather than as an error. Any proposal to extend the ledger beyond the
  commit session — spec `011-master-password-session-scope` is the live example
  — must re-establish this invariant before it lands.

  **Behaviour when the invariant is violated: the field returns to review**, as
  an undecided conflict, carrying both candidates. It is never resolved by
  picking an operand. Reopening review is chosen over throwing because a stale
  entry is a bookkeeping fault, not a corrupt vault: aborting the commit would
  discard a valid merge and lose the session's work, whereas review is the path
  FR-7 already defines for a conflict the user has not decided, it is
  non-destructive, and it puts the choice back where the invariant says it
  belongs. Silently discarding the decision is the one unacceptable option.
  Asserted in the T009 model as "a ledger decision naming neither candidate
  reopens review instead of silently taking an operand".

- **The ledger records what the user has seen, not only what the user changed.**
  Confirming review writes a ledger entry for **every conflict presented in that
  review**, including the ones left at their automatic default. An absent entry
  therefore means "never shown", and only that. Without this rule a user who
  reviewed a conflict and accepted the proposed default leaves no entry, the
  re-merge classifies it as never-seen, and the same conflict reopens review on
  every divergence — the user is punished for agreeing.
- **Shortcut decisions are recorded.** FR-6's Prefer local and Prefer remote are
  explicit decisions over exactly the conflict set displayed, and each conflict
  they resolve gets its own ledger entry. Without this, every user who resolves
  by shortcut is sent back to review on each divergence, which is the whole
  population the shortcut exists to spare.
- **A commit session may return to review at most 3 times.** Beyond that the
  session ends as an unresolved conflict: the merged local file and the dated
  backup are retained, the mapping is not marked synced, nothing further is
  written. Review re-entries are counted separately from the FR-7 retry budget,
  because a retry is automatic and a re-entry is not. With the two rules above,
  every re-entry must carry a conflict genuinely never shown before, so the cap
  bites only under sustained contention — where terminating with the local state
  intact is better than an unbounded review loop.
- If a re-merge produces a conflict the user has **never** been shown — a new
  `fieldConflict`, `deletionConflict` or `fieldDeletionConflict` with no entry in
  the ledger — the round does **not** resolve it automatically. The commit ends,
  the mutex is released, no further write is attempted, and the session returns
  to review carrying the previous decisions plus the new conflicts. Only
  conflicts already decided may be replayed without asking.

The consequence is deliberate: a contended remote can send the user back to
review. That is correct. Resolving a never-seen conflict by automatic policy, in
a flow the user believes they have already confirmed, is the failure this rule
exists to prevent.

Consequence, to be stated plainly rather than hidden: **on a backend without
conditional write the lost update is not prevented — it is made non-destructive.**
The device that gets overwritten still holds its merged state locally by the
invariant above, detects the divergence at step 5 or at its next sync, and
re-proposes it. The union converges by mutual detection rather than by mutual
exclusion.

The convergence retry is bounded. **The retry budget is 3 divergence rounds per
commit session.** After the third, the session ends as an unresolved conflict,
retaining the local merged file and the dated backup, and never marking the
mapping synced. Convergence must not loop forever against a remote peer writing
continuously.

Three, and not more, because the budget is not a convergence mechanism. Each
round costs a full download, decrypt, merge, serialize and upload, so a large
budget converts a contended remote into a long unresponsive commit rather than
into a resolution. Two well-behaved devices settle in one round; a third round is
slack for an unlucky interleaving. Beyond that the contention is structural, and
the unresolved-conflict terminal state is both safe — the merged file and the
dated backup survive locally, per the founding invariant — and honest to the
user. Rounds that terminate early are not charged to the budget: a semantic
short-circuit finalizes, and a never-seen conflict returns to review.

The budget is **per commit session**, so it bounds one commit and nothing wider.
It is explicitly not a defence against a cross-session oscillation: that failure
mode is prevented at its source by FR-3's globally deterministic tie-break, which
is what makes the merge function commutative. A budget cannot substitute for
commutativity.

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
| **Ambiguous** | every backend | Either a transport timeout/disconnect after dispatch, **or** an FR-7 step-5 read-back that could not be executed at all. In both cases the request may have applied and the client cannot tell | Never blindly retry, never mark failure or success. Enter the recovery triage below. |

**The step-5 read-back has three outcomes, not two.** Equal and different are the
two branches FR-7 defines; a read-back that times out, disconnects or otherwise
returns no checksum is the third, and it is `ambiguous`. A procedure whose whole
job is to disambiguate a write must define its own ambiguous state, or an
implementer will reasonably finalize on the absence of a reported difference —
which is precisely the "a `2xx` is a claim, not a confirmation" error, displaced
one step later. A failed verification is not a passed verification.

Two amendments follow from this table and must not be read past:

- A certain rejection **only exists on a CAS backend**. On any other backend the
  absence of a rejection is not evidence that nothing was overwritten, and the
  client must never treat it as such.
- A success response is renamed from "definite success" to "apparent success"
  precisely because it is not definite. The FR-7 step-5 read-back — not the
  response status — is what promotes it to confirmed.

Ambiguous recovery, including after app restart. The triage is unchanged in
substance; only its **trigger** widens. It previously ran on a transport
ambiguity alone; it now also runs when an apparent success fails its step-5
verification and the session is interrupted before the convergence retry
completes, **and when the step-5 read-back itself cannot be executed**. All three
entry points execute the same steps:

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
    either side's records. The same test with the retry budget of 3 exhausted
    ends as an unresolved conflict, retains the merged local file and the dated
    backup, and does not mark the mapping synced.
15e. **Re-anchor test**: after a divergence round the expected base equals the
    content observed at step 5, not the base recorded at step 1. Asserted by the
    interleaving in which a concurrent writer lands between the step-3
    revalidation and the step-4 write: the retry must proceed past its own
    step 3 instead of returning `staleRemote`.
15f. **Semantic short-circuit test**: two devices whose merged content is
    semantically identical but byte-different — different salts and IVs — finalize
    on the first divergence round, write no second time and consume no retry
    budget. The byte comparison still reports them different; the manifest
    comparison is what terminates the round.
15g. **Deterministic tie-break test**: for a field conflict with equal KDBX
    modification times, two devices holding mirrored local/remote perspectives
    select the **same** winning value, and the same holds for the deterministic
    notes concatenation operand order. A run of the same scenario in both
    perspectives produces byte-identical semantic manifests.
15h. **Sticky-decision test**: an explicit user decision survives a re-merge and
    is not reversed by LWW or by the tie-break. A conflict first introduced by a
    re-merge and never shown to the user does not resolve automatically: the
    commit ends, no further write is attempted and the session returns to review
    carrying the earlier decisions.
15i. **Step-5 non-executable test**: a re-read that times out is classified
    `ambiguous` and enters the FR-10 triage. It is never finalized, never counted
    as a divergence and never marks the mapping synced. The classification holds
    on a read-back reached after a re-anchor and a re-merge, not only on the
    first one.
15j. **Associativity test, three and four devices**: the merge produces the same
    result under every ordering and every association of three and of four
    sides, and the same holds end-to-end — three devices syncing in any of the
    six orders converge to the same remote state, a device rejoining late adds
    its contribution and nothing else, and a second pass over already-merged
    content changes nothing. Notes specifically: every segment appears exactly
    once, and a fixed-order binary concatenation is shown to fail this test, so
    it is not vacuous.
15k. **Unknown-timestamp test**: a known modification time beats an unknown one,
    two unknowns fall back to the value order, mirrored perspectives still agree,
    and a set of sides mixing known and unknown timestamps is order-independent
    at three and four devices.
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
- **"Non-destructive" is conditional on resynchronization, and the condition is
  part of the claim.** FR-7 step 5 proves the remote contained the merged state
  *at the instant it was read*. If a concurrent writer overwrites it immediately
  afterwards and **that device never comes back online** — uninstalled, lost,
  factory-reset, or simply never opened again — the overwritten contribution is
  gone from the remote permanently, and gone silently: the overwriting device
  completed its own step 5 successfully and legitimately displayed "synced".
  Nothing in the `get` + `put` cycle can detect this, because detection is
  delegated to the very device that never returns. The honest statement of the
  guarantee is therefore: **on a backend without `conditionalWrite`, no
  contribution is lost provided every device that wrote eventually
  resynchronizes.** A `versionHistory` backend narrows this window — the
  overwritten revision is retrievable from the server without the other device —
  but does not close it, because nothing prompts a fetch of a revision no device
  reports as missing. Only `conditionalWrite` removes the condition entirely, by
  refusing the overwrite in the first place. Every user-facing promise derived
  from this guarantee must state the condition before the reassurance; see spec
  010's safety-category copy.
- The FR-7 window is narrowed to the revalidate-then-write interval, not
  eliminated. Two devices writing inside that interval both converge, but the
  user may see one extra conflict round.
- The storage-capability port itself is **spec 010**. 008 consumes the
  capabilities; it does not define the multi-provider abstraction.
