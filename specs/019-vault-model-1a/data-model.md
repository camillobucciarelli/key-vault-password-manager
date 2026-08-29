# Phase 1 — Data model

No persisted domain model changes. `VaultEntry`, `VaultGroup` and the `.kdbx`
schema are untouched. What follows is presentation state and derived values.

## Changed: `VaultState`

| Field | Change | Why |
| --- | --- | --- |
| `visibleEntries` | **meaning changes**: now filtered by the selected folder subtree as well as by search, then sorted | R1 / FR-006h. Its only reader is the records list. |
| `currentGroupId` | unchanged field, **promoted to the folder filter**. `All items` is the **root group id**, never `null` | FR-002a. `_onCreateVaultEntry` returns early on a null current group (`vault_bloc.dart:389`), so a null `All items` would make the add button a silent no-op in the default state. |
| `expandedGroupIds` | unchanged in memory; now restored at unlock and written on change | FR-006g / R3 |
| `sortBy` | unchanged | R2 — surfaced, not modified |

### Derived, computed once per state change

Never per row (Performance Goals).

- **`folderCounts: Map<String, int>`** — records per folder, **inclusive of
  descendants** (FR-006i). Built by one post-order walk of `groups` over
  `allEntries` bucketed by `groupId`.
- **`totalCount: int`** — `All items`; the length of `allEntries` excluding the
  recycle bin, so `All items` and the folder counts agree. It is also the root
  group's own inclusive count, which is what makes FR-002a's two readings the
  same number rather than two numbers that happen to match.
- **`descendantIds(groupId): Set<String>`** — the subtree used by the filter.
  Derived from the same walk.

`recycleBinEntries.length` and `duplicateGroups.length` already exist and carry
the two hygiene counts (FR-004); nothing new is needed for them.

## New events

| Event | Payload | Handler behaviour |
| --- | --- | --- |
| `SelectVaultFolder` | `String groupId` — the root group id for `All items` | Sets `currentGroupId`, recomputes `visibleEntries`. Never null (FR-002a). Does **not** touch expansion (FR-006f). |
| `SetVaultFolderExpanded` | `String groupId`, `bool expanded` | Explicit form of today's toggle, so the tree's three hosts cannot disagree about what a chevron means. Persists. |

`ToggleVaultGroupExpanded` stays for its existing callers until they are gone,
then is removed in the same change — not left as a second way to do one thing.

## Entities the UI works with

- **`FolderNode`** — id, name, count (inclusive), depth, `hasChildren`,
  `isExpanded`, `isSelected`. A flattened row produced from `groups` +
  `folderCounts` + `expandedGroupIds`; the tree widget renders a list of these,
  so the three hosts differ only by which flags they force.
- **`HygieneShortcut`** — label, count, the surface it opens. Two instances,
  `Recycle bin` and `Duplicates`.
- **`SortChoice`** — the existing `VaultEntrySort` plus its label. No new values.

## Persistence

One key: `vault.folders.expanded.<database path hash>` → a list of group ids.
Group ids are not secrets — they already travel in `VaultState` and appear in
`VaultEvent` payloads — so Constitution I is not engaged. Nothing else is
written.
