# 017 — Research

Decisions taken before planning, each against what the repository actually does
today rather than against what would be convenient.

## D1 — History is already written; this feature only reads, restores and deletes

**Decision**: Add no writing behaviour. Treat `KdbxEntry.history` as the source
of truth exactly as the KDBX writer maintains it.

**Rationale**: `KdbxEntry.onBeforeModify` (kdbx 2.5.0,
`lib/src/kdbx_entry.dart:256`) appends a snapshot of the entry on every
modification, so every edit routed through `VaultKdbxService` already records the
previous values. `vault_kdbx_service_test` now proves it: after `updateEntry` the
previous password is present in `entry.history`. The application already reads
that list in `_resolveLastPasswordChangedAt` to decide when a password last
changed, and nowhere else.

**Alternatives considered**: maintaining a parallel history record owned by the
app. Rejected — it would duplicate state the file format already holds, drift
from what other KeePass clients see, and break the round-trip guarantee the merge
adapter depends on.

## D2 — A revision is identified by its last-modification time, not its index

**Decision**: Address a revision by the entry id plus the revision's
last-modification timestamp.

**Rationale**: history entries share the parent entry's UUID, so a UUID cannot
distinguish them. kdbx's own merge code identifies a revision exactly this way
(`_findHistoryEntry` matches on `times.lastModificationTime`). A list index is
not stable across a reload, a sync, or a concurrent edit from another device, and
this feature has destructive operations where addressing the wrong item is
unacceptable.

**Alternatives considered**: positional index (fragile); a synthetic id assigned
at load (would not survive a reload, so a delete confirmed on one screen could
hit a different revision after a background sync).

## D3 — Reveal reuses the existing per-entry gate, and adds no second concept

**Decision**: Revealing a revision's secret goes through the same path as
revealing the current password: `RevealController` plus, when the database has
biometric protection enabled, `_showBiometricRevealGate`.

**Rationale**: `vault_entry_detail.part.dart:122` already implements the whole
policy — check `getBiometricProtectionEnabledForPath`, gate if enabled, reveal
with an auto-hide ticker. A historical password is not less sensitive than the
current one, and inventing a second rule would mean two places to get it wrong.

**Alternatives considered**: always requiring authentication for history even
when the current password needs none. Rejected as inconsistent: the user can
already read the current secret without it, and the vault is already unlocked.

## D4 — Deleting a revision mutates the list directly; clearing backs up first

**Decision**: `history.removeWhere(...)` and `history.clear()` on the opened
file, then the existing `_save`. Clearing an entry's whole history additionally
writes a dated backup before the save.

**Rationale**: `KdbxEntry.history` is a plain mutable `List<KdbxEntry>`
(`kdbx_entry.dart:237`), and `VaultKdbxService._save` always re-serializes and
writes through `SafeVaultFileWriter` — there is no dirty-tracking to satisfy.
`_save` deliberately does not back up ("routine saves never produced one"), which
is right for an edit whose previous value lands in history, and wrong for an
operation whose entire purpose is to destroy history. Constitution VII names
exactly this case.

**Alternatives considered**: routing a clear through `_save` alone. Rejected —
the safe writer protects against a torn write, not against the user changing
their mind, and after a clear there is no history left to recover from.

## D5 — Restoring is an ordinary edit, so reversibility is free

**Decision**: Restore by writing the revision's values onto the entry through the
same setters `updateEntry` uses — which covers title, username, password, URL,
notes and custom fields, and therefore the OTP secret, since `_resolveOtpUri`
derives it from the custom fields rather than storing it beside them. It does
**not** cover attachments, and the restore does not move them.

**Rationale**: because those setters trigger `onBeforeModify`, the pre-restore
state is appended to history by the writer itself. FR-007 ("a restore is itself
reversible") therefore needs no code — but it needs a test, because it is a
property of a dependency rather than of this repository.

**Alternatives considered**: swapping the revision and the current entry in
place. Rejected — more code, and it would produce a history that other KeePass
clients read differently.

Also considered and rejected for now: extending the restore to attachment bytes.
`updateEntry` has no attachment parameter — `addAttachment`/`removeAttachment`
are separate operations — so this would be a second mechanism, not a wider call.
Constitution VIII says ship the smaller thing; FR-006a keeps it honest by making
the confirmation say what is not moving, which is the part that would otherwise
cost a user a file.

## D6 — History loads on demand, not with the entry

**Decision**: The entry screen does not carry history in its state. A user action
opens it, and only then is the file read for that entry's revisions.

**Rationale**: FR-015 and SC-002. `VaultEntry` has no history field today and
`loadAllEntries` returns every entry in the vault — on a 468-entry vault, adding
per-entry revision lists to that load would cost on every vault open, to serve a
screen almost never opened. Loading on demand also keeps historical secrets out
of the long-lived list state, which matters for Constitution I.

**Alternatives considered**: including history in `VaultEntry`. Rejected on both
counts above.

## D7 — The retention limit is reported, never set

**Decision**: Read `historyMaxItems` / `historyMaxSize` from the file's meta and
state the effective limit; provide no way to change it.

**Rationale**: `kdbx_semantic_manifest.dart:111` already reads both, so the
values are available. Changing them is a vault-wide policy decision with data-loss
consequences at the next save, and no user has asked for it. Constitution VIII.

## D8 — No new BLoC; the work lands in VaultBloc plus a coordinator

**Decision**: History events go to `VaultBloc`; the multi-step restore and clear
sequences go to a coordinator.

**Rationale**: Constitution II forbids a new BLoC unless a spec proves the three
existing ones cannot carry the state, and this is vault content viewed from the
vault screen. Reading is a single call and belongs in the bloc's translation
layer; restore and clear are confirm → back up → write → reload sequences, which
is what a coordinator is for.
