# 017 — Data model

No new persisted data. Everything here is a read-side projection of what the
`.kdbx` file already holds.

## VaultEntryRevision

One previous version of an entry, as recorded by the KDBX writer.

| Field | Type | Notes |
|-------|------|-------|
| `entryId` | `String` | The parent entry's UUID. Shared by every revision of that entry — it does not identify the revision. |
| `replacedAt` | `DateTime` | The revision's last-modification time, in UTC. Doubles as the revision's identity (D2). |
| `title` | `String` | |
| `username` | `String` | |
| `password` | `String` | **Secret.** Redacted in `props` and `toString` (Constitution I). |
| `url` | `String` | |
| `notes` | `String` | **Secret.** Same treatment as the current entry's notes. |
| `customFields` | `List<VaultCustomField>` | Protected fields keep their protected flag. |
| `attachmentNames` | `List<String>` | Names only. Attachment bytes are never read for a revision, and a restore does not move them (FR-006a). |
| `otpUri` | `String?` | **Secret.** *Derived*, not stored: `_resolveOtpUri` reads it out of `customFields`, exactly as `VaultEntry` does. It is therefore restored by restoring the custom fields, and needs no separate handling. Redacted; presence reported as a boolean. |

Mirrors `VaultEntry`'s existing redaction discipline: `VaultEntry` already wraps
`password` and `notes` in `RedactedValue` for `props` and reports `otpUri` as
`<redacted>`. A revision is not less sensitive than the entry it came from.

**Ordering**: newest first, by `replacedAt` descending. The KDBX list is oldest
first; the reversal happens at the boundary, once.

**Identity**: `(entryId, replacedAt)`. Two revisions of the same entry cannot
share a last-modification time, because each is produced by a distinct
modification.

## VaultEntryRevisionSummary

What the list shows without revealing anything.

| Field | Type | Notes |
|-------|------|-------|
| `replacedAt` | `DateTime` | |
| `changedFields` | `Set<VaultEntryField>` | Which fields differ from the revision that replaced this one — the next newer revision, or the current entry for the newest. |
| `hasSecretChange` | `bool` | Whether `password` or `otpUri` is among them. Lets the UI say "password changed" without touching the value. |

`changedFields` is computed by comparing values, which means comparing secrets in
memory. It never surfaces them: only the field names leave the comparison.

## VaultHistoryRetention

| Field | Type | Notes |
|-------|------|-------|
| `maxItems` | `int?` | From `meta.historyMaxItems`. `null` when the file does not state one; a negative value means unlimited, per KDBX. |
| `maxSizeBytes` | `int?` | From `meta.historyMaxSize`. |

Read-only (D7).

## Relationships

```
VaultEntry 1 ──── 0..n VaultEntryRevision      (ordered, newest first)
VaultEntryRevision 1 ──── 1 VaultEntryRevisionSummary
KdbxFile 1 ──── 1 VaultHistoryRetention
```

## State transitions

An entry's revision list changes in exactly four ways:

1. **Any edit to the entry** — the KDBX writer appends the pre-edit state. Not
   this feature's doing, and not modified by it (FR-014).
2. **Restore** — an edit like any other, so the pre-restore state is appended
   (D5). The restored revision itself stays in the list. Attachments do not
   move (FR-006a), so an entry's attachment set is unchanged by a restore.
3. **Delete one revision** — removed from the list; the others keep their order.
4. **Clear** — the list becomes empty, after a dated backup (D4).

A merge can also add revisions from another device; that path is owned by the
merge adapter and is out of scope.
