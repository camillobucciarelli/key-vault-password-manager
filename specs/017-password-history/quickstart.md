# 017 — Validation quickstart

How to prove password history works. Everything here is runnable on a desktop
build; nothing needs hardware.

## Prerequisites

- A vault with an entry edited at least three times, including two password
  changes and one title-only change.
- One other KeePass client (KeePassXC is enough) to confirm the file stays
  interoperable.

```bash
flutter run --dart-define-from-file=.env.dart.define.json -d macos
```

## A — Read (US1)

1. Open the entry, open its history.
   **Expect**: revisions newest first, each dated, each labelled with which
   fields changed. Passwords masked.
2. Reveal one revision's password.
   **Expect**: on a database with biometric protection enabled, the same gate as
   revealing the current password; on one without, an immediate reveal that
   auto-hides on the same timer.
3. Open the history of an entry that has never been edited.
   **Expect**: an empty state saying there are no previous versions. Not an
   error, not a blank panel.
4. Read the stated retention limit and compare it with the file's
   `historyMaxItems` in another client.
   **Expect**: the same number.

## B — Recover (US2)

1. Copy a revision's password.
   **Expect**: the same toast and the same clipboard clearing as copying the
   current password.
2. Restore the newest revision.
   **Expect**: a confirmation naming what is replaced; afterwards the entry holds
   the restored values, **and the pre-restore password is now the newest
   revision** — restore the newest revision again and you are back where you
   started.
3. Restore a revision on a locked vault (lock it from another window first).
   **Expect**: nothing written, and the reason stated.
4. Restore a revision of an entry that has an attachment, where the revision's
   attachments differ.
   **Expect**: the confirmation says attachments are not restored, and afterwards
   the entry's attachments are exactly as they were.
5. Restore a revision whose custom fields held an `otpauth://` value.
   **Expect**: the OTP comes back with the custom fields — it is stored in them,
   not beside them.

## C — Remove (US3)

1. Delete one revision.
   **Expect**: it is gone, the others keep their order, and reopening the file in
   KeePassXC shows the same list.
2. Clear an entry's whole history.
   **Expect**: a warning naming what is destroyed **before** anything happens, a
   dated backup on disk afterwards, and an empty history.
3. Open the backup from step 2 in KeePassXC.
   **Expect**: the revisions are still there — the backup is what makes the
   destruction survivable.
4. Delete an entry with history, restore it from the recycle bin.
   **Expect**: its history comes back with it, and the time spent in the bin is
   not shown as a password change.
5. Change the master password, then reopen any entry's history.
   **Expect**: the revisions are unchanged, and no entry reads as freshly
   changed because of the rekey.
6. After any of the above, make one ordinary edit to the entry.
   **Expect**: exactly one new revision — this feature did not change what the
   writer records (FR-014).

## D — Long history (SC-002)

1. Script 200 edits to one entry, then open the entry screen.
   **Expect**: it opens no slower than an entry with no history, because history
   is not loaded until asked for.
2. Open that entry's history.
   **Expect**: it lists 200 revisions, or the retention limit's worth, and says
   which.

## E — Redaction (FR-004, SC-003)

With everything above done in one session:

```bash
flutter run --dart-define-from-file=.env.dart.define.json -d macos 2>&1 | grep -iE "password|secret"
```

**Expect**: no line containing a real password value, historical or current.
Any hit fails the gate.

## Local gate before commit

```bash
dart format --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

All three clean and green (Constitution IX).
