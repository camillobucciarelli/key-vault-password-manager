# Contract — `EntryHistoryCoordinator`

Sequencing for the two operations that are more than one step. Reading is a
single service call and does not belong here (Constitution VIII).

```dart
Future<EntryHistoryRestoreResult> restore({
  required String databasePath,
  String? keyFilePath,
  required String entryId,
  required DateTime replacedAt,
});

Future<EntryHistoryClearResult> clearHistory({
  required String databasePath,
  String? keyFilePath,
  required String entryId,
});
```

## `restore`

1. Refuse if the session holds no secret — the vault locked between the
   confirmation and the act. Report it; write nothing.
2. Call `restoreEntryRevision`.
3. Report what happened so the caller can reload and tell the user.

The confirmation itself (FR-008) is the caller's: it is a UI question, and the
coordinator must stay callable from a test without one.

## `clearHistory`

1. Refuse on a locked session, as above.
2. **Write a dated backup of the `.kdbx` before touching it** (FR-010,
   Constitution VII), using the same dated-backup mechanism as the pre-rekey
   backup.
3. Call `clearEntryHistory`.
4. If the write fails after the backup exists, leave the backup in place and say
   so — a stray backup is recoverable, a missing one is not.

## Results

```dart
enum EntryHistoryOutcome { done, vaultLocked, failed }
```

Both results carry the outcome and, for a clear, the backup's path so the UI can
name it. Neither carries a secret.
