# Contract — history operations on `VaultKdbxService`

Four additions to the service that already owns semantic KDBX reads and writes.
Every one takes the database path lock and, where it writes, goes through the
existing safe writer (FR-011).

## `loadEntryHistory`

```dart
Future<VaultEntryHistory> loadEntryHistory({
  required String databasePath,
  required String password,
  String? keyFilePath,
  required String entryId,
});
```

Returns the revisions **and** the retention limits together, from one open of
the file under one lock. The view needs both, and two separate reads could
observe two different states of the same file — a revision list from before a
sync and a limit from after it.

- Revisions newest first.
- An entry with no history yields an empty list and the limits. Not an error
  (FR-013).
- Throws if the entry does not exist, matching `_findEntryById` elsewhere.
- Retention limits come from `meta.historyMaxItems` / `meta.historyMaxSize`
  (FR-012) and are never written (D7).
- Reads only; takes the lock so it cannot observe a half-written file.

## `restoreEntryRevision`

```dart
Future<void> restoreEntryRevision({
  required String databasePath,
  required String password,
  String? keyFilePath,
  required String entryId,
  required DateTime replacedAt,
});
```

- Writes the revision's title, username, password, URL, notes and custom fields
  onto the entry using the same setters as `updateEntry`, so the pre-restore
  state lands in history through the writer (D5, FR-007). The OTP secret rides
  along in the custom fields — it is derived from them, not stored beside them.
- **Does not touch attachments** (FR-006a). Saying so here is the point: a reader
  of this contract must not assume `updateEntry`'s setters cover them, because
  they do not.
- Throws when no revision has that `replacedAt`, rather than restoring a
  neighbour.

## `deleteEntryRevision` / `clearEntryHistory`

```dart
Future<void> deleteEntryRevision({
  required String databasePath,
  required String password,
  String? keyFilePath,
  required String entryId,
  required DateTime replacedAt,
});

Future<void> clearEntryHistory({
  required String databasePath,
  required String password,
  String? keyFilePath,
  required String entryId,
});
```

- `deleteEntryRevision` removes exactly the revision with that timestamp and
  leaves the rest in order (FR-009). Throws when it is not found.
- `clearEntryHistory` empties the list (FR-010). **The dated backup is not
  written here** — it is the caller's, so that the backup and the confirmation
  stay in one place; see the coordinator contract.

## Invariants

- No method logs, returns in an error message, or puts into a `toString` any
  revision secret (FR-004).
- No method changes what future edits record in history (FR-014). Asserted by
  test, not assumed: after any of these operations, an ordinary edit still
  records exactly one new revision.
- Every write takes the path lock and goes through `_save`, and a test asserts
  it using the write-tracking harness the service tests already have
  (FR-011).
- Every write re-serializes the whole file through `_save`, exactly as the
  existing writes do.
