# 004 — Tasks

- [ ] **T0** Snapshot user-facing strings of `vault_entries_details.part.dart`,
      `vault_dialog_password.part.dart`, `vault_entries.part.dart` into
      `test/fixtures/strings_004_before.txt`.

## Entry detail

- [ ] **T1** `vault_entries.part.dart` rows → `KvListRow` + `KvLetterAvatar(38)` +
      `KvHealthDot(8)`; min height 62, internal gap 12, selected state
      `accent200`. Health dot carries a `semanticsLabel`.
- [ ] **T2** `vault_entry_detail.part.dart` header: avatar 56 (Caprasimo 22),
      title `screenTitle` 28, subtitle 13.5 `folder · host`, gap 14, 36 circle
      header actions.
- [ ] **T3** Field rows via `KvFieldRow` (Username, Password, Website, Notes),
      gap 9; "More" chips (padding 9/14, 13 px) for attachments and custom fields.
- [ ] **T4** `strength_strip.dart`: radius 20, padding 12/16, 32 circle glyph,
      12.5 text, thresholds from `_evaluatePasswordStrength` (Weak <40, Fair <60,
      Good <80, Strong), plus `lastPasswordChangedAt`. Primary "Copy password"
      pill below.
- [ ] **T5** `revealed_password_row.dart`: `attentionTint` bg, mono 16 word-break,
      4 px countdown bar.
- [ ] **T6** `RevealController` (12 s): starts on reveal, drains the bar,
      re-masks on expiry, cancelled by a manual toggle. Not disabled by
      `disableAnimations` (the bar animation is; the timer is not).
- [ ] **T7** Biometric gate `KvBottomSheet` before reveal when the database has
      biometrics on: "Unlock with biometrics" / "Use password".
- [ ] **T8** `totp_row.dart`: 38 circle with seconds 11/700, code mono 21
      +0.16em; 1 s tick, remaining derived from the URI `period`; shares the
      detail screen's single `Ticker` with T6.
- [ ] **T9** `lib/core/utils/clipboard_guard.dart`: `copy(value)` writes,
      schedules 30 s, on fire clears **only if** the clipboard still holds the
      written value. Reschedule on next copy; dispose with the screen.
- [ ] **T10** Wire every copy affordance to `ClipboardGuard` + `KvSnackbar` with
      the existing strings (`Copied password.` etc.), 1600 ms visible.
- [ ] **T11** Weak/reused strip variant in `attentionTint` linking to the
      generator, pre-filled with the entry's constraints.

## Editor

- [ ] **T12** `vault_entry_editor.part.dart` header: text-only
      `Cancel` 14 `neutral700` — title Caprasimo 16 — `Save` 14 (`textTertiary`
      disabled). Fields gap 14: Title, Username, Password, URL, Notes on
      `KvInput`; generator spark (`magic`) inside the password field.
- [ ] **T13** Optional list: three rows radius 20, padding 13/16, glyph 17,
      chevron 17 — Custom field, Attachment, One-time code. Tablet variant
      radius 20, padding 12/16, `surfaceNested` on the `surface` pane.
- [ ] **T14** Constraint-error states with the two existing literal strings,
      rendered as `KvInput` errors (2 px `accent700`, 12.5 `accent800`).
- [ ] **T15** Full-screen QR scanner (`mobile_scanner`, already a dependency) for
      `otpauth://`.
- [ ] **T16** Camera-denied screen with the `OTP URI (otpauth://…)` field as the
      manual fallback.
- [ ] **T17** Discard-changes `KvBottomSheet`.
- [ ] **T18** Saving overlay: keep `isSaving` blocking, card copy
      "Writing to the .kdbx…", backdrop 22 %.

## Generator

- [ ] **T19** `vault_generator.part.dart` sheet: gap 16; result box radius 22
      padding 16 `surface`, mono 16 break-all, 36 regenerate button; length header
      label left + Caprasimo 18 value right; `KvSlider` 8–64 default 16; four
      `KvCheckbox` rows gap 10, label 14, existing labels verbatim; live result
      above the controls; `canGenerate == false` disables the primary action.
- [ ] **T20** Tablet: generator as the editor's **third column**, same widget,
      no sheet.

## Tablet detail pane

- [ ] **T21** Detail pane: copy actions as pills; metadata grid with exactly
      three rows — Created, Updated, last password change.

## Verify

- [ ] **T22** String diff vs `strings_004_before.txt` empty.
- [ ] **T23** Tests: strength thresholds 40/60/80; TOTP 30→0 with rotation on the
      boundary; reveal re-masks at 12 s and a manual toggle cancels;
      `ClipboardGuard` clears on match and **leaves a changed clipboard alone**;
      `canGenerate == false` disables generate; tablet metadata grid has 3 rows;
      detail on tablet pushes no route.
- [ ] **T24** 13 goldens per the spec table.
- [ ] **T25** `flutter analyze` clean, `flutter test` green.
