# Duplicate Management — Design Spec

**Date:** 2026-04-17
**Status:** Approved

---

## Summary

Add a duplicate-detection and resolution feature to the vault. A duplicate is defined as two or more entries sharing the same normalized URL **and** the same normalized username. Users can resolve duplicates by deleting one entry (sending it to the recycle bin) or merging the two entries (copying missing fields from the secondary into the primary, then deleting the secondary).

Entry points: a badge counter in the sync strip and a "Manage duplicates" item in the Settings bottom sheet.

---

## Detection Rules

Two entries are duplicates when:

```
normalize(entry.url) == normalize(other.url)
AND
normalize(entry.username) == normalize(other.username)
```

**URL normalization:**
1. Lowercase
2. Strip scheme (`https://`, `http://`, `ftp://`)
3. Strip `www.` prefix
4. Strip trailing slash
5. Keep only host + path (ignore query string and fragment)

**Username normalization:**
1. Trim whitespace
2. Lowercase

**Exclusions:**
- Entries with an empty URL are excluded entirely (no URL = no URL-based duplicate).
- Entries in the recycle bin are excluded.

A `DuplicateGroup` contains 2+ entries sharing the same normalized key.

---

## Architecture

### New file: `lib/features/password_manager/data/services/vault_duplicate_service.dart`

Pure Dart service — no Flutter dependency, fully unit-testable.

**Responsibilities:**
- `List<DuplicateGroup> findDuplicates(List<VaultEntry> allEntries)` — groups entries by `normalizedUrl:normalizedUsername`, returns only groups with 2+ entries, sorted by group size desc then by URL asc.
- `MergePreview previewMerge(VaultEntry primary, VaultEntry secondary)` — returns which fields would be copied (for the confirmation dialog).
- `Future<void> mergeEntries({...})` — writes the merged fields onto the primary in the kdbx file, then moves the secondary to the recycle bin.

### New model: `lib/features/password_manager/domain/models/duplicate_group.dart`

```dart
class DuplicateGroup extends Equatable {
  final String sharedUrl;       // human-readable normalized URL
  final String sharedUsername;
  final List<VaultEntry> entries; // 2+ entries, sorted newest first
}
```

### New model: `lib/features/password_manager/domain/models/merge_preview.dart`

```dart
class MergePreview extends Equatable {
  final VaultEntry primary;
  final VaultEntry secondary;
  final bool willCopyNotes;
  final bool willCopyOtp;
  final List<String> customFieldKeysToCopy; // keys from secondary missing in primary
  final bool willCopyAttachments;
  bool get hasAnythingToCopy; // convenience getter
}
```

### Changes to `VaultState`

New fields:
```dart
List<DuplicateGroup> duplicateGroups = const []
bool isDuplicatesLoading = false
```

Convenience getter:
```dart
int get duplicateGroupCount => duplicateGroups.length;
```

### New events in `VaultEvent`

```dart
class LoadDuplicates extends VaultEvent { const LoadDuplicates(); }

class DeleteDuplicateEntry extends VaultEvent {
  const DeleteDuplicateEntry(this.entryId);
  final String entryId;
}

class MergeDuplicateEntries extends VaultEvent {
  const MergeDuplicateEntries({
    required this.primaryId,
    required this.secondaryId,
  });
  final String primaryId;
  final String secondaryId;
}
```

### VaultBloc changes

Register handlers for the three new events.

`_onLoadDuplicates`: emits `isDuplicatesLoading = true`, calls `VaultDuplicateService.findDuplicates(state.allEntries)`, emits result.

`_onDeleteDuplicateEntry`: calls existing `deleteEntry` kdbx logic (reycle bin), then recomputes duplicates from updated `allEntries`.

`_onMergeDuplicateEntries`: calls `VaultDuplicateService.mergeEntries(...)`, then recomputes duplicates and reloads the vault snapshot.

**Automatic recomputation** (after these existing events):
- `InitializeVault` (after vault loads)
- `RefreshVault`
- `ImportVaultEntriesFromCsv`

No recomputation after ordinary `CreateEntry`/`UpdateEntry`/`DeleteEntry` — badge staleness is acceptable for non-duplicate-specific operations.

---

## UI

### Badge in `_SyncStatusStrip`

Shown only when `state.duplicateGroupCount > 0`. Small chip with warning color (amber) displaying the count, placed next to the database name. Tap dispatches `LoadDuplicates` and opens the duplicates dialog.

### Settings menu item

Added to the "Tools" section of `_VaultSettingsSheet`:

```
[icon: copy] Manage duplicates
             "3 pairs found"  /  "No duplicates"
```

Tapping it dispatches `LoadDuplicates` and opens the dialog.

### `vault_duplicates.part.dart` (new part file)

Follows the same pattern as `vault_recycle_bin.part.dart`.

**Dialog structure:**

- Title: "Duplicate records"
- Subtitle: "N pairs with same URL and username" (or "No duplicates found" when empty)
- Scrollable list of `DuplicateGroup` cards
- Close button

**`_DuplicateGroupCard`** — one card per group:
- Header: human-readable URL + username
- Entry sub-cards (compact): title, folder path, masked password (`••••••••`), last modified date
- Entry sub-cards are sorted newest first
- Actions row:
  - **"Delete older"** — one-tap, no confirmation, sends the oldest entry to recycle bin
  - **"Merge"** — opens `_MergeConfirmDialog`

**`_MergeConfirmDialog`:**
- Shows primary (newest) and secondary (oldest) titles
- Lists fields to be copied: "Notes, OTP code" etc.
- If `!mergePreview.hasAnythingToCopy`: "No additional data — the older entry will be deleted."
- Actions: Cancel / Merge

**Groups of 3+ entries:**
- No "Merge" button — only per-entry "Delete" buttons on each sub-card
- "Delete older" still available (deletes all but the newest)

**Post-action UX:**
- Resolved groups are removed with a fade+slide animation
- When all groups are resolved: empty state with a success icon ("No duplicates found")

---

## Merge Logic (detail)

Primary = entry with the most recent `updatedAt` (or `createdAt` as fallback).

Fields copied from secondary **only if empty/missing in primary:**

| Field | Copy condition |
|-------|---------------|
| `notes` | primary.notes is empty |
| `otpUri` | primary.otpUri is null |
| `customFields` | per-key: key absent in primary |
| `attachments` | per-filename: filename absent in primary |

Primary's `title`, `username`, `password`, `url` are never overwritten.

After copying fields, the secondary entry is moved to the recycle bin via the existing `deleteEntry` kdbx path. The kdbx file is saved once at the end.

---

## Out of Scope

- Fuzzy matching (e.g., `github.com` ≈ `github.com/login`) — exact normalized match only
- Title-based duplicate detection
- Automatic resolution without user action
- Merging 3+ entries into one in a single operation
