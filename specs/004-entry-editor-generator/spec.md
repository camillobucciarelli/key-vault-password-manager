# 004 — Entry detail, editor, generator (journeys 04–06)

**Status**: Draft · **Kind**: Restyle · **Depends on**: 001, 002
**Design source**: `04-06 Voce, editor, generatore.dc.html`,
`specs/_design/PIXEL_SPEC.md` §4 (Entry detail, Editor, Generator),
`14 Dark mode.dc.html` (entry detail with reveal + TOTP).

## Why

The highest-traffic surface in the app, and today the most dialog-bound: entry
detail and the editor both live inside `vault_entries_details.part.dart` (45.9 KB)
and `vault_dialogs.part.dart`. The design turns them into a screen (mobile) /
detail pane (tablet), and gives the generator a real home instead of a nested
dialog.

## Screens

| # | Screen | Form | Golden |
| --- | --- | --- | --- |
| 1 | Entry detail — hidden | screen / pane | 390×844 L+D, 1024×768 L |
| 2 | Entry detail — revealed + TOTP | screen / pane | 390×844 L+D |
| 3 | Biometric gate before reveal | bottom sheet | 390×844 L |
| 4 | Copy confirmation | snackbar | 390×844 L |
| 5 | Weak/reused warning | screen variant | 390×844 L |
| 6 | Editor — new item | screen / pane | 390×844 L, 1024×768 L |
| 7 | Editor — generator sheet | bottom sheet / 3rd column | 390×844 L, 1024×768 L |
| 8 | Editor — constraint errors | screen variant | 390×844 L |
| 9 | QR scanner | full screen | 390×844 |
| 10 | Camera denied + OTP URI field | full screen | 390×844 L |
| 11 | Discard changes | bottom sheet | 390×844 L |
| 12 | Saving overlay | overlay | 390×844 L |
| 13 | Generator standalone | bottom sheet | 390×844 L |

## Functional requirements

### FR-1 · Entry detail

Header: letter avatar **56** (Caprasimo 22), title `screenTitle` Caprasimo 28,
subtitle 13.5 = `folder · host`, gap 14; header actions 36 circles.

Copyable field rows (`KvFieldRow`, radius 22, padding 13/16), gap 9:
**Username**, **Password**, **Website**, **Notes**.

"More" chips for attachments and custom fields: padding 9/14, 13 px.

Strength strip at the bottom: radius 20, padding 12/16, 32 circle glyph, text
12.5. Values come from the existing `_evaluatePasswordStrength`:

| Label | Entropy |
| --- | --- |
| Weak | < 40 bits |
| Fair | < 60 bits |
| Good | < 80 bits |
| Strong | ≥ 80 bits |

The strip also shows `lastPasswordChangedAt`.

Primary action: **"Copy password"** pill.

### FR-2 · Reveal and TOTP

Revealed password row: `attentionTint` (accent-100) background, monospace **16**
with word-break, and a 4 px countdown bar inside the row.

TOTP row: 38 circle with the remaining seconds in 11/700, code in monospace
**21** with +0.16em. The countdown is real today (`Timer.periodic` +
`TotpUtils`); remaining seconds derive from the URI `period`, ticking every 1 s
with no easing.

**Proposal — 12 s reveal auto-hide.** Adopted by this spec: after 12 s the
password re-masks and the countdown bar drains. Rationale: the design ships the
bar geometry, and a shoulder-surfing window is a real risk on a password manager.
The reveal toggle (`_passwordVisible`) keeps working; the timer only forces the
hidden state.

On databases with biometrics enabled, reveal goes through the biometric gate
sheet first ("Unlock with biometrics" / "Use password").

### FR-3 · Copy behaviour

Existing snackbar strings stay byte-identical: `Copied password.`,
`Copied username.`, `Copied URL.`, `Copied notes.`, `Copied one-time code.`,
`Copied <field>.` Toast visible 1600 ms (200 ms in/out).

**Proposal — 30 s clipboard clear.** Adopted: after 30 s the clipboard is
overwritten with an empty string if its content still matches what the app wrote.
Never clear a clipboard the user changed in the meantime (compare before writing).
Applies on all platforms; the snackbar copy is unchanged.

### FR-4 · Weak / reused warning

A variant of the strength strip in `attentionTint` that links to the generator
(opens the generator sheet pre-filled with the entry's constraints).

### FR-5 · Editor

Header is **text-only**: `Cancel` 14 `neutral700` — title Caprasimo 16 — `Save`
14 (`textTertiary` when disabled). No app bar, no elevation.

Fields, gap 14 — the real five plus notes: **Title, Username, Password, URL,
Notes**. The generator spark (`magic` glyph) sits **inside** the password field.

Vertical **Optional** list, three rows radius 20, padding 13/16, glyph 17,
trailing chevron 17 — **Custom field**, **Attachment**, **One-time code**.
Identical on mobile and tablet (on tablet: radius 20, padding 12/16, background
`surfaceNested` on the `surface` pane).

Variants:
- generator sheet (FR-6);
- the two literal constraint errors already produced by the editor — strings
  unchanged;
- full-screen QR scanner for `otpauth://`;
- camera-denied screen with the `OTP URI (otpauth://…)` text field as the fallback;
- discard-changes sheet;
- saving overlay: keep `isSaving` as a blocking overlay, card copy
  **"Writing to the .kdbx…"**, backdrop 22 %.

### FR-6 · Generator

Sheet gap 16. Result box: radius 22, padding 16, `surface`, monospace 16 with
break-all, 36 regenerate button. Length header: label left, value Caprasimo 18
right. Slider **8–64**, default **16** (`KvSlider`). Four character-set checkboxes
with their exact existing labels, rows gap 10, label 14. Result updates live above
the controls. `canGenerate == false` disables the primary action (all sets off).

Standalone entry point (Vault destination) uses the same sheet.

### FR-7 · Tablet

- Detail pane: copy actions become pills; a metadata grid shows **Created**,
  **Updated**, **last password change** — exactly the three rows `Record info`
  shows today.
- Editor: the generator becomes a **third column**, not a sheet.

## Acceptance criteria

1. All 13 goldens match.
2. Snackbar strings and the editor's two constraint-error strings are unchanged
   (string diff test).
3. Strength thresholds still map to Weak/Fair/Good/Strong at 40/60/80 bits.
4. TOTP: with a `period=30` URI, the ring shows 30→0 and the code rotates exactly
   on the boundary; the tick is 1 s.
5. Reveal auto-hides after 12 s; the bar reaches 0 at the same moment; a manual
   toggle before then cancels the timer.
6. Clipboard clear: 30 s after a copy, the clipboard is empty **only if** it still
   holds the copied value; a test that overwrites the clipboard in between asserts
   it is left alone.
7. `canGenerate == false` (no character set selected) disables the generate action.
8. On tablet, the metadata grid shows exactly three rows.
9. Detail and editor are a pane on tablet — no route pushed.

## Out of scope

- Changing `VaultBloc` events or the kdbx write path.
- Favicons — rows use letter avatars by design.
