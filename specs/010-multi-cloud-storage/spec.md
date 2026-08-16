# 010 — Multi-cloud remote storage

**Status**: **Draft** · **Kind**: New feature · **Depends on**: 005

> Draft only. No `plan.md`, no `tasks.md`, no implementation. This spec exists to
> freeze the port shape and the user-facing guarantee vocabulary before a second
> provider is written.

## Goal

Put every remote storage backend behind one domain port, so Google Drive becomes
one adapter among several instead of the hard-coded remote. Each adapter declares
what its backend can actually do, and the app derives a user-visible safety
category from that declaration.

Candidate providers: Google Drive, Dropbox, OneDrive, iCloud Drive,
WebDAV/Nextcloud, S3 and S3-compatible object stores, and a plain local or
network folder.

## Why now

Spec 008's Gate 0 measured Google Drive against a real network on 2026-08-15 and
found it offers **no compare-and-swap** — no `If-Match`, no `412`, no `ETag`
(`specs/008-per-field-conflict-resolution/feasibility-report.md`, §"B1
live-network re-spike"). Spec 008 responded by rewriting FR-7 around a
storage-agnostic write-verify-converge cycle needing only `get` and `put`.

That rewrite is **accepted as a direction and not yet validated**: spec 008's
Gate 0 was reopened on 2026-08-16 because the cycle was declared sufficient in
the same commit that rewrote the criterion, and reading it found three defects
that each prevented convergence. They are corrected, and 008 T009 makes the
cycle's properties executable. **This spec therefore describes a port shape, not
a shipped guarantee**, and no adapter here ships before 008's Gate 0 closes.

The rewrite's consequence is still worth naming: the sync safety model no longer
depends on any Drive-specific mechanism. Nothing about it is Drive-shaped
anymore, so nothing justifies Drive being the only backend — and the same
measurement showed that providers differ in ways the user deserves to see before
choosing one.

## Relation to 008 — dependency direction

**010 owns the port. 008 consumes it.**

```text
008 SyncMergeCoordinator
      -> 008 domain use cases
            -> 010 RemoteStoragePort  (get/put/list/delete + declared capabilities)
                  ^
                  |
            010 adapters: Drive | Dropbox | OneDrive | iCloud | WebDAV | S3 | folder
```

- 010 defines the port, the capability set and the category derivation.
- 008 defines the merge semantics and the FR-7 write-verify-converge cycle, and
  reads capabilities to decide whether it may take an optional shortcut.
- 010 **never** imports 008. It knows nothing about KDBX, merges or conflicts.
- 008's coordinator, use cases and merge adapter are **identical** for every
  adapter. Capabilities are consumed in the data layer only. No domain or
  presentation code branches on a capability. This is the architectural point of
  the whole spec: the storage-agnostic logic is what carries the guarantee, and
  capabilities are decorations that raise it silently.

## Invariant product constraint — one file, always openable

**At every instant, the vault on the remote is a single `.kdbx` file that an
external KeePass-compatible application can open directly.**

This is not an implementation preference. It is the product promise, and it is
recorded here because it has already ruled out one design and will be proposed
again:

- **no** per-device file scheme (`vault.<deviceId>.kdbx` merged on read);
- **no** sidecar lock file, marker file or journal that the vault depends on to
  be correct;
- **no** app-proprietary container, chunking, or wrapper around the `.kdbx`;
- **no** intermediate state where the remote path holds a partial, renamed or
  otherwise non-openable object.

A per-device scheme would give free write isolation and would remove the need for
any of 008's convergence machinery. It is rejected anyway: a user who opens the
file with KeePassXC on a machine without KeyVault must find their vault, not a
fragment of it. Any proposal that reintroduces multiple remote objects is out of
scope by construction, not by oversight.

Consequence for adapters: an adapter that cannot present exactly one openable
`.kdbx` at its remote path is not eligible, whatever its capabilities.

## Capability taxonomy

Base operations — `get`, `put`, `list`, `delete` — are the **minimum entry
requirement**, not capabilities. An adapter that cannot do all four is not an
adapter. Capabilities are strictly what a backend offers *beyond* that floor.

| Capability | Meaning | Consumed by |
| --- | --- | --- |
| `conditionalWrite` | The server **rejects** a write whose precondition is stale. True compare-and-swap: an observed failure proves the write did not land, and a success proves no concurrent write landed between the read and the write. | 008 FR-7 step 4; closes the race window entirely |
| `versionHistory` | Previous contents of the object are retrievable **from the server** after being overwritten. | 008 FR-7 step 5 divergence branch; recovers the exact overwritten bytes instead of waiting for the other device |
| `atomicCreateIfAbsent` | Creating an object at a path succeeds only if nothing exists there, atomically. The backend cannot end up with two objects at the same logical path. | First-time vault provisioning; protects the invariant above against a duplicate remote vault |
| `changeNotification` | Remote changes are learnable by push notification or by an efficient delta/poll, rather than by re-downloading the object. | Sync scheduling only. **Never** a safety mechanism — a missed notification must never weaken any guarantee |

Rules on declarations:

1. A capability is declared **only** when a spike has observed the behaviour
   against the real service. Documentation alone is not a declaration.
2. Declarations are conservative. When a behaviour is uncertain, the capability
   is **absent**. An absent capability costs a guarantee tier; a wrongly present
   one costs user data.
3. `changeNotification` never participates in the category derivation, because it
   affects freshness, not safety.

## User-facing safety categories

Derived from the declared capabilities, shown **in the provider list at the
moment of choice** — not in a settings screen, not behind a help link, not after
the account is connected.

| Category | Derivation | What the user is told |
| --- | --- | --- |
| **Protetto** | `conditionalWrite` present | "If another device saves at the same moment, this service refuses the second save. Nothing you save here is replaced by another device without you being asked." |
| **Recuperabile** | no `conditionalWrite`, `versionHistory` present | "If two devices save at the same moment, one save can replace the other. As long as the device that made the replaced save connects again, KeyVault gets it back from the service and nothing is lost. Until then, that save exists only on that device." |
| **Ricostruibile** | neither | "If two devices save at the same moment, one save can replace the other. As long as the device that made the replaced save connects again, KeyVault restores it from the copy kept on that device and nothing is lost. If that device never connects again, that save is lost." |

**Every string above states its condition before its reassurance, and that
ordering is a requirement, not a style choice.** The earlier drafts all ended on
an unconditional "Nothing is lost". On the two lower tiers that is false: 008's
guarantee is conditional on the overwritten device resynchronizing, and a device
that is uninstalled, lost, reset or simply never opened again takes its
contribution with it (008 §"Out of scope / residual limits", defect C6). On a
password manager an unconditional promise that does not hold is worse than a
qualified one — it is exactly the promise a user would rely on when deciding not
to keep their own backup.

**Protetto** is the one tier where C6 does **not** apply: with a true
compare-and-swap the second write is refused, so no contribution is ever
overwritten and there is no device to wait for. Its copy was still narrowed, for
a different reason: "Nothing you saved is ever replaced without you being asked"
promised more than any capability in this taxonomy delivers. `conditionalWrite`
governs **concurrent remote writes** and nothing else — it says nothing about a
local write interrupted mid-save, and 008's FR-9 local atomicity rows are
`not-run` on every platform. The string is therefore scoped to what the
capability actually guarantees: not replaced **by another device**.

### Naming rationale

The three names describe **what happens to the user's data**, and they are
ordered by how the data comes back, not by how the machinery works.

- **Protetto** — nothing is lost because nothing is overwritten.
- **Recuperabile** — something is overwritten, and it is recovered from the
  service.
- **Ricostruibile** — something is overwritten, and it is rebuilt from the copy
  on the device.

What the names deliberately avoid:

- No jargon. The strings above name no ETag, no CAS, no precondition, no
  revision, no checksum. A user choosing a cloud provider is not being asked to
  understand HTTP semantics.
- No fear words. "base", "weak", "unsafe", "degraded" would be scary and, for
  the wrong reason, imprecise: on all three tiers the overwritten data **is**
  recovered. But it is not recovered unconditionally, and the copy no longer
  pretends otherwise — on the two lower tiers recovery is performed by the
  overwritten device and therefore requires that device to come back. The tiers
  differ in *from where*, *how fast* and *on what condition*, and the strings
  now say all three.
- No false equivalence either. **Ricostruibile** states the real cost out loud —
  the other device has to reconnect — so a user who syncs from a device they
  rarely open can weigh it.

### Derivation rules — non-negotiable

1. **The category is computed from the declared capabilities. It is never a
   per-provider constant.** No adapter may hard-code, override or annotate its
   category. An adapter that gains `conditionalWrite` becomes **Protetto**
   automatically; one that loses it drops automatically.
2. An adapter therefore **cannot claim to be safer than its capabilities allow**.
   The only way to move up a tier is to declare a capability, and the only way to
   declare a capability is to pass its spike.
3. The category is visible **before** the choice: rendered on every row of the
   provider list, in the same visual weight as the provider name.
4. The category is re-derived and re-displayed whenever an adapter's capability
   set changes, and the change is surfaced to a user already using that provider.
5. The copy names consequences for data, never mechanisms.

## Candidate providers

**Exactly one cell in this table rests on measurement: Google Drive's
`conditionalWrite`, which was measured and found *absent*.** The live spike
established that Drive does **not** have the capability; "verified" here refers
to the evidence, never to the presence of the feature. Everything else in this
table — including Drive's other three capabilities — is an **expectation**,
recorded so the work can be planned, and carries no evidential weight whatsoever.

Marking an unverified expectation as fact is the exact error this gate already
made once and corrected (feasibility report, §"Post-review corrections", C1).
**It was then repeated in this spec's first draft**, which declared Drive's
`versionHistory` present from its documented API and derived a **Recuperabile**
category from it — one tier above what the evidence supported, on the strength of
a document. Corrected 2026-08-16. AC-9 already required a review to fail on
exactly this, which is why open question 4 below is closed rather than open: the
rules answered it.

| Provider | `conditionalWrite` | `versionHistory` | `atomicCreateIfAbsent` | `changeNotification` | Category | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| **Google Drive** | **no** | **no** (unmeasured) | **no** | to verify | **Ricostruibile** | `conditionalWrite` **verified absent** — live spike 2026-08-15. `versionHistory` **not measured**, therefore declared absent (see below) |
| Dropbox | to verify | to verify | to verify | to verify | *to verify* | **not measured** |
| OneDrive | to verify | to verify | to verify | to verify | *to verify* | **not measured** |
| iCloud Drive | to verify | to verify | to verify | to verify | *to verify* | **not measured** |
| WebDAV / Nextcloud | to verify | to verify | to verify | to verify | *to verify* | **not measured** |
| S3 and compatibles | to verify | to verify | to verify | to verify | *to verify* | **not measured** |
| Local / network folder | to verify | to verify | to verify | to verify | *to verify* | **not measured** |

No provider other than Drive may ship a category derived from an expected
capability. Until its spike runs, an adapter is not shippable — there is no
"assume the lowest tier and ship" path, because a wrong capability declaration is
what the tier system exists to prevent.

### Google Drive — the measured row

| Capability | Declared | Basis |
| --- | --- | --- |
| `conditionalWrite` | **no** | Measured. `If-Match` (invented, stale `version`, stale `headRevisionId`), `If-None-Match: *` and `If-Unmodified-Since` with a past date all returned `200` **with the remote bytes actually overwritten**. Counter-probes exclude a transport fault: `Range` on the read path returned `206`, so arbitrary headers do reach and are interpreted; a malformed `If-Match` returned `200` rather than `400`, so the upload path does not parse preconditions at all. No `ETag` header and no `etag` field are returned; `version` and `headRevisionId` exist but are purely descriptive. |
| `versionHistory` | **no** (`not-run`) | **Demoted 2026-08-16.** Previously declared **yes** on the strength of Drive's documented revisions API. That is a declaration from documentation, which rule 1 above forbids in as many words — *"Documentation alone is not a declaration"* — and rule 2 resolves the uncertainty against the capability: *"when a behaviour is uncertain, the capability is absent"*. Nothing was measured: not retention, not `keepRevisionForever`, not the ceiling on pinned revisions, not quota impact, and not the base claim that an overwritten revision is retrievable. The 2026-08-15 spike did not probe revisions at all. Declared **absent** until an FR-5 spike measures it. |
| `atomicCreateIfAbsent` | **no** | Drive permits two files with the same name in the same folder, so a create cannot be conditioned on absence. |
| `changeNotification` | to verify | Drive documents a changes/watch API; not measured. |
| **Category** | **Ricostruibile** | Derived: no `conditionalWrite`, no declared `versionHistory`. Down from **Recuperabile**, which the 2026-08-15 draft derived from an undeclarable capability. The demotion is cheap to reverse: one FR-5 revisions spike restores `versionHistory`, and the category follows automatically — which is the derivation rule working as intended. |

## Functional requirements

### FR-1 — The storage port

One domain port exposes `get`, `put`, `list`, `delete` over an opaque remote path
plus an immutable declared capability set. It is defined in `domain/` and
implemented once per provider in `data/`.

The port is content-agnostic: it moves bytes and never knows they are a `.kdbx`.

### FR-2 — Capabilities are declared data, not behaviour

An adapter exposes its capabilities as an immutable value read at registration.
Capability checks never take the form of feature detection at call time, `try`/
`catch` probing in production, or provider-name comparisons anywhere in the
codebase.

A capability absent from the declaration is treated as absent even if the backend
happens to support it.

**Every declared capability must be backed by a dated spike artifact, and this is
enforced structurally, not by review.** The derivation *category ← capabilities*
is already safe: one pure function, test-enforced, no override (FR-3). The link
*capabilities ← reality* is not, and that is the gap the Drive `versionHistory`
demotion came through — an adapter can declare `conditionalWrite: true` with no
spike behind it and become **Protetto** by doing so. AC-8 catches that only if a
human reviewer notices, and the bypass was in fact used before any reviewer did.

The enforceable form:

1. An adapter declares each capability as a value carrying its evidence:
   the capability, the artifact path inside `specs/010-multi-cloud-storage/`, and
   the date the spike ran. A capability cannot be declared present without one —
   it is not a separate field to remember, it is the only constructor.
2. A test enumerates every registered adapter, and for every capability declared
   present asserts that the named artifact file exists, parses, is dated, and
   names that adapter and that capability. A missing, unparseable or
   mismatched artifact fails the suite.
3. The test also asserts the converse: an artifact recording a **negative**
   result cannot accompany a present declaration.

**This test ships with the first adapter, and cannot ship before it.** There is
no adapter registry today — 010 is a draft with no code, and 008 is behind an
open Gate 0 — so the test would have an empty set to enumerate and would assert
nothing. Building a registry now, only to satisfy a test with no members, is
infrastructure disproportionate to a draft. The obligation is therefore recorded
here and in AC-13, and the one live instance of the bypass is closed by
measurement discipline instead: Drive's `versionHistory` is demoted to absent in
this revision, so no capability in this spec is currently declared without
evidence.

### FR-3 — Derived categories, no overrides

The category is a pure function of the declared capability set, defined once. No
adapter, configuration file, remote flag or build variant can override it. This
is enforced by test, not by convention.

### FR-4 — Category visible at choice time

The provider list shows each provider's category, with its plain-language
consequence sentence, before any account is connected. The category is not
reachable only through a settings screen, a tooltip, or post-connection state.

### FR-5 — Every adapter needs a capability spike

Before an adapter ships, a manual live-network spike modelled on
`tool/drive_conditional_spike.dart` must run against the real service and record
a dated artifact in this spec's folder. The spike:

1. attempts each declared capability against the live service and records the
   observed status **plus a counter-proof** — for a write, re-read the object and
   compare bytes; an accepted response is not evidence on its own;
2. includes counter-probes that exclude transport-level explanations for a
   negative result, as the Drive spike's `Range` → `206` probe did;
3. runs against a throwaway account, creates and deletes only its own probe
   object, and touches no `.kdbx` and no pre-existing file;
4. reads its credential from an environment variable only, and never prints,
   logs or persists it, not even truncated;
5. records **no** real account identifier, object ID, path or token in the
   artifact.

A capability with no passing spike is declared absent. A negative spike result is
a valid, publishable outcome — the Drive spike returned one and it produced a
better spec.

### FR-6 — The single-file invariant is adapter-enforced

Every adapter satisfies the invariant above: exactly one openable `.kdbx` at the
remote path at every instant, including mid-write where the backend allows it.
An adapter that cannot is not eligible, and this is checked before capabilities
are even considered.

### FR-7 — Credentials stay in the data layer

Per 008's secret boundary and constitution principle I: OAuth tokens, refresh
tokens, S3 keys, WebDAV passwords and every other provider credential are
resolved, held and refreshed **inside the data layer**, in existing secure
storage.

- Domain, coordinators, BLoCs and UI hold an opaque provider/account identifier
  only.
- No credential enters `Equatable.props`, `toString`, logs or serialization.
- Adding a provider never widens the surface or lifetime that holds a secret.
- Errors surfaced upward are safe codes; a provider error string is never
  forwarded verbatim, since these frequently embed tokens or signed URLs.

### FR-8 — Provider migration preserves the invariant

Switching providers uploads the current vault to the new provider and verifies
the read-back before the old mapping is dropped — the same
never-discard-before-verified rule as 008 FR-7, applied to the mapping instead of
to the merged state.

## Acceptance criteria

1. Exactly one storage port; no provider-specific type reaches domain,
   coordinator, BLoC or UI.
2. Base operations are required of every adapter and are not modelled as
   capabilities.
3. Category is derived from capabilities by one pure function; a test proves no
   adapter can declare or override a category directly, and that raising a
   category requires raising a capability.
4. Category and its plain-language sentence render on every provider-list row
   before connection. Golden and semantic assertions cover the list.
5. Category copy contains no technical term — asserted by a test over the exact
   strings, forbidding ETag, CAS, precondition, revision, checksum, hash and
   their Italian equivalents.
6. 008's coordinator, use cases and merge adapter behave identically against a
   `conditionalWrite` adapter, a `versionHistory` adapter and a bare adapter.
   Only the reported category differs.
7. No production code branches on a provider identity.
8. Every shipped adapter has a dated capability-spike artifact in this folder;
   an undeclared or unspiked capability is treated as absent.
9. The provider table in this spec separates **verified** from **to verify**, and
   a spec review fails if an unmeasured capability is stated as fact.
10. The remote path holds exactly one openable `.kdbx` at every instant, for
    every adapter, including under interrupted writes.
11. No provider credential appears in domain, coordinator, BLoC or UI types,
    logs, serialization or error strings.
12. Provider migration verifies the read-back on the new provider before dropping
    the old mapping.
13. **Capability ⇒ artifact, enforced by test.** Every capability an adapter
    declares present resolves to an existing, parseable, dated spike artifact in
    this folder naming that adapter and that capability; a negative artifact
    cannot accompany a present declaration. Ships with the first adapter. Until
    then no capability may be declared present without its artifact existing.
14. **Every category string states its condition before its reassurance.**
    Asserted over the exact strings: no tier's copy ends on an unconditional
    "nothing is lost" unless its capabilities make it unconditional, and only
    `conditionalWrite` does. **Protetto**'s copy is scoped to concurrent writes
    by another device, and claims nothing about a locally interrupted save,
    which is 008 FR-9's `not-run` territory.

## Out of scope

- **Multiple simultaneous remotes** for one vault. One vault, one remote.
- **Per-device files, sidecar locks, marker files, journals or app-proprietary
  containers.** Excluded by the invariant above, permanently, not pending a
  better design.
- **Cross-provider merge.** 008 owns all merge semantics; 010 moves bytes.
- **Building a CAS layer on a backend that lacks one.** Measured absence is
  handled by 008's convergence cycle, not simulated with client-side locking.
- **Server-side or end-to-end re-encryption.** The `.kdbx` is already the
  encryption boundary.
- **Provider-specific sharing, team drives, ACLs and quota management.**
- **Implementing any adapter.** This draft defines the port, the taxonomy, the
  categories and the spike requirement. `plan.md` and `tasks.md` follow only when
  a second provider is actually scheduled.

## Open questions

1. Which provider is second? The candidate list is unordered, and the answer
   determines which spike runs first.
2. Does S3 conditional write (`If-None-Match` on `PutObject`) satisfy
   `conditionalWrite` for our purpose, or only `atomicCreateIfAbsent`? To be
   settled by the spike, not by reading the documentation.
3. Does `changeNotification` deserve any user-visible expression at all? Current
   answer: no — it affects freshness, not safety, and mixing the two would dilute
   the three categories.
4. ~~Do the Drive revisions details hold well enough for the **Recuperabile**
   promise, or does Drive need to be reported one tier lower until they are
   measured?~~ **Closed 2026-08-16 — the spec's own rules already answered it.**
   Not one revisions behaviour was measured, so rule 1 ("documentation alone is
   not a declaration") and rule 2 ("when a behaviour is uncertain, the capability
   is absent") make `versionHistory` absent, and AC-9 requires a review to
   **fail** where an unmeasured capability is stated as fact. Drive is reported
   as **Ricostruibile**. This was never a judgement call; it was a rule already
   written down and not applied. The live question that remains is only *when the
   revisions spike runs*, and it is FR-5 work, not an open design question.

5. Which capability should the first FR-5 spike measure? Drive's
   `versionHistory` is the cheapest candidate with a user-visible payoff — it
   moves the only shipped provider from **Ricostruibile** back to
   **Recuperabile** — and it needs no new provider integration.
