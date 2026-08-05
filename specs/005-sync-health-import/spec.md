# 005 — Sync, vault health, import/export (journeys 07–09)

**Status**: Draft · **Kind**: Restyle · **Depends on**: 001, 002
**Design source**: `07-09 Sync, igiene, import-export.dc.html`,
`specs/_design/PIXEL_SPEC.md` §4 (Sync, Health, Duplicates), `14 Dark mode.dc.html`.

> The per-field conflict resolution shown in the same design file is **spec 008**,
> not this one. This spec styles the existing three-way conflict sheet; 008
> replaces it with a flow.

## Why

Three destinations' worth of content (Sync, Health, and Settings → Backups &
import) currently live as dialogs inside `vault_dialogs.part.dart` and
`vault_navigation.part.dart`. The design gives each a first-class surface, and
puts the six `DatabaseSyncStatus` values on screen instead of hiding five of them
behind a snackbar.

## Screens

| # | Screen | Form | Golden |
| --- | --- | --- | --- |
| 1 | Sync — `disconnected` | destination | 390×844 L+D |
| 2 | Sync — connected, not linked | destination | 390×844 L |
| 3 | Sync — remote file picker | screen / pane | 390×844 L |
| 4 | Sync — `success` | destination | 390×844 L+D, 1024×768 L |
| 5 | Sync — `syncing` | destination | 390×844 L |
| 6 | Sync — offline (proposal) | destination | 390×844 L |
| 7 | Sync — `error` + Reconnect | destination | 390×844 L |
| 8 | Sync — `conflict` sheet | bottom sheet | 390×844 L |
| 9 | Health — score + 5 categories | destination | 390×844 L+D, 1024×768 L |
| 10 | Duplicates — groups | screen / pane | 390×844 L |
| 11 | Merge preview | bottom sheet | 390×844 L |
| 12 | Duplicates — empty | screen | 390×844 L |
| 13 | Recycle bin | screen / pane | 390×844 L |
| 14 | Recycle bin — empty + confirm | screen + sheet | 390×844 L |
| 15 | CSV import — preview | screen | 390×844 L |
| 16 | CSV import — outcome | screen | 390×844 L |
| 17 | Backups | screen | 390×844 L |

## Functional requirements

### FR-1 · Sync status hero

Radius 26, padding 20, 52 circle glyph, title Caprasimo 20, meta 12.5, plus a
key/value list at 12.5 with `space-between`. One hero per
`DatabaseSyncStatus` value — all six of `idle`, `syncing`, `success`, `error`,
`conflict`, `disconnected` are rendered states, none is a snackbar-only state.

| Status | Hero content |
| --- | --- |
| `disconnected` | Explains the security model **before** asking for Drive access — what is uploaded (the encrypted `.kdbx` only), what Google can see (nothing decryptable), what scope is requested |
| connected, not linked | Two paths: create a new Drive file — literal copy **"A new file will be created in My Drive root."** — or pick an existing one. Auto-sync toggle (`KvSwitch`) |
| `syncing` | `KvSpinner` 34 + progress copy |
| `success` | last sync time, local checksum (mono 11, truncated), unlink action |
| `error` | the error text + **"Reconnect Google Drive"** as a persistent action, not a transient snackbar |
| `conflict` | routes to the conflict sheet (FR-3), and to spec 008's flow once shipped |

**Proposals in this journey**: the recent-activity list under `success`, and the
offline state. Both adopted — activity rows are compact (padding 11/14) and read
from data the app already stores; offline is derived from a failed request, not a
new connectivity dependency.

### FR-2 · Remote file picker

One row per `DriveRemoteFile`: name, `modifiedTime`, size, and an
already-linked warning tag when the file is mapped to another local database.

### FR-3 · Conflict sheet (pre-008)

Two version cards, radius 20, padding 14/16, each with a 40 square glyph, the
truncated checksum in mono 11 and `remoteModifiedTime`. The three real
resolutions from `SyncConflictResolution` — **Keep local**, **Use remote**,
**Cancel** — each labelled with which side is which. Semantics unchanged.

### FR-4 · Vault health

Score circle **64** with Caprasimo 22; five category rows (standard `KvListRow`)
each with a Caprasimo 18 count before the chevron. Every category is computed
from data the app already has — no new scanning, no network:

1. Weak passwords (entropy < 40 bits, existing `_evaluatePasswordStrength`)
2. Reused passwords (same password across ≥ 2 entries)
3. Old passwords (`lastPasswordChangedAt` older than the threshold)
4. Duplicates (existing `VaultDuplicateService` groups)
5. Entries without a URL or username (autofill can never match them)

The score is a single number derived from the five counts; the exact formula is
an implementation decision, but it must be deterministic and unit-tested.

### FR-5 · Duplicates

Group card radius 24 padding 14; inner entry rows radius 16 padding 11/13.
Groups come from `sharedUrl` + `sharedUsername` (`DuplicateGroup`).
**Keep** = `MergePreview.primary`, **Merge** = `MergePreview.secondary`.
The "Some data will be copied" strip (radius 14, padding 9/12, 12 px text)
appears when `MergePreview.hasAnythingToCopy`.

Merge preview lists **exactly the four `MergePreview` flags**:
`willCopyNotes`, `willCopyOtp`, `customFieldKeysToCopy`, `willCopyAttachments`.
Merge action is full-width, padding 11, radius 999.

Empty state: no-duplicates screen.

### FR-6 · Recycle bin

Restore inline on the row; **Delete permanently** in the row overflow;
`Empty bin (n)` as the screen action with its existing literal string. Empty
state + the existing confirm strings, both unchanged.

### FR-7 · CSV import

Preview screen with the four counters — **Detected format**, **Rows found**,
**Valid records**, **Skipped rows** — plus the **Avoid duplicates** toggle.

**Proposal adopted**: the outcome screen lists per-row skip reasons. The importer
(`vault_csv_import_service.dart`) already knows why it skipped a row; surface it
instead of a bare count.

### FR-8 · Backups

One screen collecting the three existing export actions, unchanged in behaviour.

## Acceptance criteria

1. All 17 goldens match.
2. Every `DatabaseSyncStatus` value has a rendered hero; a test iterates the enum
   and asserts a non-empty hero for each.
3. `disconnected` explains the security model before any Drive-permission call is
   made (assert no auth call on first render).
4. Remote picker shows the already-linked warning when the file id exists in
   another `DatabaseSyncMapping`.
5. Merge preview shows exactly the four `MergePreview` flags — no more, no fewer.
6. Health score is deterministic: same vault → same score (unit test with a fixed
   fixture).
7. `Empty bin (n)` and the recycle-bin confirm strings are byte-identical to today.
8. CSV outcome shows a reason for every skipped row.

## Out of scope

- Per-field conflict resolution — **spec 008**.
- Any change to the sync algorithm or checksum comparison.
- A connectivity package: offline is inferred from request failure.
