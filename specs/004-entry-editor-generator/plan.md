# 004 — Plan

## Approach

Three surfaces, three passes: detail, editor, generator. Each is rebuilt on the
`Kv*` kit and mounted through `VaultShellRouter` (spec 002). The two adopted
proposals (12 s reveal auto-hide, 30 s clipboard clear) are behaviour, not
styling — they get their own tasks and their own tests, and they are the only
logic added in this spec.

`vault_entries_details.part.dart` (45.9 KB) is split while it is being rewritten:
detail, editor and generator each get their own part file.

## Files

### New

| Path | Contents |
| --- | --- |
| `.../screens/vault/vault_entry_detail.part.dart` | FR-1, FR-2, FR-4 |
| `.../screens/vault/vault_entry_editor.part.dart` | FR-5 |
| `.../screens/vault/vault_generator.part.dart` | FR-6 |
| `.../presentation/widgets/entry/strength_strip.dart` | strength strip + weak/reused variant |
| `.../presentation/widgets/entry/totp_row.dart` | 38 ring + 21 mono code |
| `.../presentation/widgets/entry/revealed_password_row.dart` | accent-100 row + 4 px countdown |
| `lib/core/utils/clipboard_guard.dart` | copy + 30 s conditional clear |
| `test/features/.../entry_detail_test.dart`, `entry_editor_test.dart`, `generator_test.dart` | |
| `test/core/utils/clipboard_guard_test.dart` | |
| `test/goldens/entry_*.png`, `editor_*.png`, `generator_*.png` | 13 screens |

### Modified

| Path | Change |
| --- | --- |
| `.../screens/vault/vault_entries_details.part.dart` | reduced to the list↔detail glue; content moves to the three new parts |
| `.../screens/vault/vault_dialog_password.part.dart` | generator moves out; file deleted if empty |
| `.../screens/vault_screen.dart` | new `part` directives |
| `.../screens/vault/vault_entries.part.dart` | rows use `KvListRow` + `KvLetterAvatar` + `KvHealthDot` |

## Behaviour additions

### 12 s reveal auto-hide

A `RevealController` (plain `ChangeNotifier`, not a BLoC) holding
`revealedUntil`. Starting a reveal sets it to `now + 12 s`; the countdown bar
reads the remaining fraction; expiry re-masks. A manual toggle cancels. Respects
`AppMotion.duration` for the bar only — the timer itself is not an animation and
is **not** disabled by `disableAnimations`.

### 30 s clipboard clear

`ClipboardGuard.copy(value)` writes, remembers the value, and schedules a 30 s
timer. On fire it reads the clipboard and clears **only if** the content still
equals what it wrote. Never clears blindly. Cancelled and rescheduled on the next
copy. Held in the widget layer, disposed with the screen so a backgrounded app
does not leak a timer.

## Sequencing

```
T1 list rows ── T2 detail shell ── T3 field rows ── T4 strength strip
                                        │
                        T5 reveal + countdown ── T6 biometric gate
                        T7 TOTP row
                        T8 clipboard guard ── T9 snackbars
                                        │
T10 editor shell ── T11 optional list ── T12 QR / camera-denied ── T13 discard / saving
                                        │
T14 generator sheet ── T15 tablet third column
                                        │
T16 tablet detail pane + metadata grid ── T17 tests ── T18 goldens
```

## Risks

| Risk | Mitigation |
| --- | --- |
| Clipboard clear fights a password manager's own autofill flow | Only clear on exact match; never clear if the app is not foreground-owner of the last write |
| 12 s auto-hide annoys users typing a password manually into another app | It re-masks the UI only; the value is still one tap away, and the clipboard path is unaffected |
| TOTP timer + reveal timer both ticking per second | One `Ticker` in the detail screen drives both |
| Splitting a 46 KB part file mid-rewrite loses a branch | Snapshot the string list (as in spec 003) and diff after |

## Verification

```bash
flutter analyze
flutter test test/features/password_manager/presentation/screens/vault
flutter test test/core/utils/clipboard_guard_test.dart
flutter test test/goldens
```

Manual: reveal a password and wait 12 s; copy and check the clipboard at 29 s and
31 s; scan an `otpauth://` QR; deny camera and paste a URI; discard an edit;
save a large entry and watch the overlay.
