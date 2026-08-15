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

That rewrite has a consequence worth naming: the sync safety model no longer
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
| **Protetto** | `conditionalWrite` present | "If another device saves at the same moment, this service refuses the second save. Nothing you saved is ever replaced without you being asked." |
| **Recuperabile** | no `conditionalWrite`, `versionHistory` present | "If two devices save at the same moment, one save can replace the other — KeyVault notices and gets the replaced version back from the service. Nothing is lost." |
| **Ricostruibile** | neither | "If two devices save at the same moment, one save can replace the other — KeyVault notices and restores the replaced version from the copy on your device. Nothing is lost, but the other device has to reconnect first." |

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
- No fear words. "base", "weak", "unsafe", "degraded" would be wrong as well as
  scary: on **all three** tiers the overwritten data is recovered, per 008's
  invariant. The tiers differ in *from where* and *how fast*, and the copy says
  exactly that.
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

**Only Google Drive is verified.** Its row is measured against the live service.
Every other row is an **expectation**, recorded so the work can be planned, and
carries no evidential weight whatsoever.

Marking an unverified expectation as fact is the exact error this gate already
made once and corrected (feasibility report, §"Post-review corrections", C1). It
is not repeated here.

| Provider | `conditionalWrite` | `versionHistory` | `atomicCreateIfAbsent` | `changeNotification` | Category | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| **Google Drive** | **no** | **yes** | **no** | to verify | **Recuperabile** | **verified** — live spike 2026-08-15 |
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
| `versionHistory` | **yes**, details `not-run` | Drive exposes a documented revisions API. **The operational details are not measured**: retention window, `keepRevisionForever` semantics, the ceiling on pinned revisions, and the quota impact of retained revisions. The Drive adapter must not depend on any of them until FR-5's spike closes them. |
| `atomicCreateIfAbsent` | **no** | Drive permits two files with the same name in the same folder, so a create cannot be conditioned on absence. |
| `changeNotification` | to verify | Drive documents a changes/watch API; not measured. |
| **Category** | **Recuperabile** | Derived: no `conditionalWrite`, `versionHistory` present. |

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
4. Do the Drive revisions details (retention, `keepRevisionForever`, pinning
   ceiling, quota) hold well enough for the **Recuperabile** promise, or does
   Drive need to be reported one tier lower until they are measured?
