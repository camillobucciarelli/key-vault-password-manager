# 017 — Implementation plan

## Technical context

| | |
|---|---|
| **Language / runtime** | Dart 3, Flutter 3.47.1 (pinned in `.fvmrc`) |
| **Vault format** | KDBX via `kdbx: ^2.5.0` |
| **Layer entry point** | `data/services/vault_kdbx_service.dart` — already owns semantic KDBX reads and writes |
| **State** | `VaultBloc` (no new BLoC — Constitution II, D8) |
| **Sequencing** | New `EntryHistoryCoordinator` for restore and clear |
| **UI** | `presentation/screens/vault/vault_entry_detail.part.dart` plus one new part file |
| **Tests** | `flutter_test`; goldens under `test/goldens/` |
| **Unknowns** | None. Everything this plan depends on was read in the repository — see `research.md`. |

## Constitution check

| Principle | How this plan satisfies it |
|---|---|
| **I — secrets never leak** | `VaultEntryRevision` redacts `password`, `notes` and `otpUri` in `props`/`toString`, mirroring `VaultEntry`. History is loaded on demand and not held in long-lived list state (D6). Diff computation compares secrets but emits only field names. |
| **II — layering** | `presentation` → `EntryHistoryCoordinator` → `VaultKdbxService`. No new BLoC; `VaultBloc` gains events that translate and delegate. The read is a single call and stays out of the coordinator (VIII). |
| **III — design tokens** | The new UI reads `AppColors`/`AppTextStyles`/`AppSpacing`/`AppRadii`/`AppMotion`. No literal hex, family, radius or duration. |
| **IV — pixel fidelity** | Golden inventory below, at 390×844 and 1024×768, light and dark. |
| **V — accessibility** | Every text/background pairing ≥ 4.5:1 including the smallest secondary text; revision rows ≥ 44×44; 2 px focus ring on every focusable; the "password changed" signal is a label, never colour alone. |
| **VI — existing copy** | No existing string is edited. Every string in this feature is new. |
| **VII — destructive ops** | Clearing history warns first, names what is lost, and writes a dated backup before the file changes (D4). Deleting one revision warns without a backup — see the risk note below. |
| **VIII — smallest thing** | No abstraction with one implementation beyond the coordinator that Principle II requires. No retention editing (D7). No history in `VaultEntry`. |
| **IX — local verification** | `flutter analyze` and `flutter test` before every commit. |

**One deliberate tension, stated rather than smoothed over**: Principle VII names
"empty bin" and master-password changes as backup-worthy, and clearing an entry's
whole history is the same kind of act, so it backs up. Deleting a *single*
revision does not, because a dated copy of a multi-megabyte vault per revision
deleted is a worse trade than the confirmation it already gets. If review
disagrees, the change is one call in the coordinator.

## Phases

### Phase 0 — Read (US1, P1)

The MVP. Everything else acts on what this shows.

- `VaultEntryRevision`, `VaultEntryRevisionSummary`, `VaultHistoryRetention` in
  `domain/models/`, with redaction matching `VaultEntry`.
- One `loadEntryHistory` on `VaultKdbxService` returning revisions and retention
  limits together, per `contracts/vault_kdbx_service_history.md` — one open, one
  lock, one consistent reading.
- Diff computation for `changedFields` — pure, and therefore unit-tested
  directly.
- `VaultBloc`: `LoadEntryHistory`, and history state on `VaultState` that clears
  when the entry screen closes.
- New part file `vault_entry_history.part.dart` with the list, the empty state,
  the retention line, and reveal wired to the existing `RevealController` and
  `_showBiometricRevealGate` (D3).
- `vault_screen.dart` gains the `part` directive; part files inherit the
  assembler's imports.

### Phase 1 — Recover (US2, P2)

- `restoreEntryRevision` on the service, covering the fields `updateEntry`
  writes — the OTP included, since it lives in the custom fields — and
  explicitly not attachments.
- `EntryHistoryCoordinator.restore`.
- Copy wired to the existing `ClipboardGuard`, matching the current password's
  toast and clearing.
- Confirmation dialog naming what is replaced (FR-008).
- Reload and success message through `VaultBloc`.

### Phase 2 — Remove (US3, P3)

- `deleteEntryRevision` and `clearEntryHistory` on the service.
- `EntryHistoryCoordinator.clearHistory`, including the dated backup before the
  write.
- Two confirmations: one for a single revision, one for a clear that names what
  is destroyed and says a backup will be written.

### Phase 3 — Verification

Goldens, contrast assertions, the quickstart run, and the redaction sweep.

## Files touched

**New**

- `lib/features/password_manager/domain/models/vault_entry_revision.dart`
- `lib/features/password_manager/presentation/coordinators/entry_history_coordinator.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_entry_history.part.dart`
- `test/features/password_manager/domain/models/vault_entry_revision_test.dart`
- `test/features/password_manager/presentation/coordinators/entry_history_coordinator_test.dart`
- `test/goldens/vault_entry_history_*_test.dart`

**Modified**

- `lib/features/password_manager/data/services/vault_kdbx_service.dart` — five methods
- `lib/features/password_manager/presentation/bloc/vault/{vault_event,vault_state,vault_bloc}.dart`
- `lib/features/password_manager/presentation/screens/vault_screen.dart` — one `part`, one import
- `lib/features/password_manager/presentation/screens/vault/vault_entry_detail.part.dart` — the entry point into history
- `lib/features/password_manager/di/password_manager_presentation_di.dart`
- `test/features/password_manager/data/services/vault_kdbx_service_test.dart`

## Golden inventory (Constitution IV)

| Golden | Size | Theme |
|---|---|---|
| `vault_entry_history_list` | 390×844 | light, dark |
| `vault_entry_history_list_wide` | 1024×768 | light, dark |
| `vault_entry_history_empty` | 390×844 | light |
| `vault_entry_history_revealed` | 390×844 | dark |

The revealed golden uses a fixed fake secret, never a real one. Widget
assertions cover the omitted axes: the 44 dp row height, the focus ring, the
retention line's text, and that a masked revision renders no secret characters.

## Test strategy

- **Pure, unit-tested**: the diff computation and the newest-first ordering.
- **Service-level, against a real temporary `.kdbx`**: load, restore, delete,
  clear — following the pattern the existing `vault_kdbx_service_test` uses,
  including its write-tracking harness, which is what checks FR-011. The restore
  test asserts the *pre-restore* password is in history afterwards, because D5's
  reversibility is a property of the dependency, not of our code; it also asserts
  that an OTP in the custom fields comes back and that attachments do not move.
- **Coordinator, with fakes**: locked vault refuses; the backup precedes the
  write; a failed write leaves the backup and reports it.
- **Redaction**: `props` and `toString` of a revision contain no secret, the same
  assertion `VaultEntry` already carries.
- **Goldens**: as inventoried, with `warmUpGoldenAssets()` in `setUpAll` and no
  `di.sl<T>()` in `dispose()` — the two rules that keep goldens order-independent.

## Risks

| Risk | Handling |
|---|---|
| A revision's `replacedAt` collides after a merge from another device | Identity is `(entryId, replacedAt)` and merge preserves timestamps; the service throws rather than acting on an ambiguous match. |
| A user expects a restore to bring back an attachment | It does not, and the confirmation says so when the attachments differ (FR-006a). Silently leaving a file behind is the failure mode this avoids. |
| The feature quietly changes what the writer records | Asserted after every destructive operation: an ordinary edit still produces exactly one revision (FR-014). |
| A long history makes the file slow to open | Not introduced here — the file is already read whole. Only the screen changes, and it loads on demand (D6). |
| Deleting a revision has no backup | Deliberate, argued above. One call to change if review disagrees. |
| Historical secrets in a crash report | Same redaction discipline as `VaultEntry`, asserted by test, swept in quickstart E. |
