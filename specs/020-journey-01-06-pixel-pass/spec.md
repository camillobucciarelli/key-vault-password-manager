# 020 — Entry detail: one home for attachments

**Status**: Done — 2026-08-31 · **Kind**: Conformance / Design fidelity
**Created**: 2026-08-29 · **Rescoped**: 2026-08-31
**Depends on**: 019 (journey 03 and the shell chrome), 018 (FR-011, amended here)
**Source**: `specs/_design/CONFORMANCE_AUDIT.md` — finding C-04-04

## Scope

Only C-04-04 below. The pixel pass on journeys 01, 02, 04, 05 and 06 that this
spec originally reserved space for is dropped: those screens stay as they are
(decision of 2026-08-31).

## The finding

Code-verified, already attempted, and deliberately left open by spec 019.

### C-04-04 · `Attachments` exists twice on the entry detail

`Attachments` is both a row action in the header's overflow menu and a chip in
the body's `More` section, so the same affordance has two homes. The design's
normative inventory (DQ-5) is: attachments are a **section with their count**,
and the header's overflow carries object management only — `Move`, `Delete`,
`Duplicate`.

Spec 019 tried the obvious fix — delete the menu item — and reverted it. Both
reasons are load-bearing for this spec:

1. **The body chip renders only when the record already HAS an attachment**
   (`vault_entry_detail.part.dart`, the `More` block is guarded by
   `entry.attachments.isNotEmpty`). Delete the menu item and there is no way
   left to add the first attachment to a record. The fix is therefore not a
   deletion: the section must become **permanent, with its count**, showing
   zero and still offering `Manage`.
2. **Spec 018's mobile characterisation pins the menu item at every width**
   (FR-011, `vault_navigation_mobile_characterisation_test.dart`). That
   guarantee was written when the overflow was the only home. It can be
   re-negotiated, but deliberately and in a spec that says so — not by editing
   the test that protects it.

## Requirements

- **FR-001**: The entry detail MUST always show an `Attachments` section with
  the record's attachment count, including `0`, at every width.
- **FR-002**: The section MUST offer a `Manage` action that opens the existing
  attachments surface (the one today's overflow item opens). No new capability.
- **FR-003**: The detail header's overflow MUST no longer offer `Attachments`.
  Its remaining items (`Move`, `Duplicate`, `Record info`, `Delete`) are
  unchanged; `Record info` is metadata, not an attachment concern, and stays.
- **FR-004**: Adding the first attachment to a record with none MUST be
  reachable at every width in no more interactions than today (today:
  `⋯` → `Attachments` = 2; after: `Manage` = 1).
- **FR-005**: The record-row `•••` menu in the list is out of scope and MUST be
  unchanged — it has no body to host a section.
- **FR-006**: Spec 018's FR-011 is amended, in `specs/018-desktop-vault-navigation/spec.md`,
  with this exact text appended to FR-011:
  > *Amended by spec 020 (2026-08-31): `Attachments` is no longer a record
  > action in the detail header overflow at any width. It is a permanent
  > section of the detail body with its count and a `Manage` action, identical
  > across layouts. The record-row `•••` menu is unchanged. The layout-parity
  > guarantee itself stands.*
  The characterisation tests that pinned the old menu are updated to the
  amended inventory; they are not deleted.
- **FR-007** (Constitution VI): strings named here change: the `n attachment(s)`
  chip label is replaced by the section (`Attachments`, count, `Manage`). The
  `Attachments` dialog title stays byte-identical. No other copy changes.

## Success criteria

- **SC-001**: `Attachments` appears exactly once on the entry detail at 390 and
  1024 px — as the section title — and never in the header overflow.
- **SC-002**: A record with zero attachments shows `0` and `Manage` opens the
  attachments dialog, at 390 and 1024 px (widget tests).
- **SC-003**: Every golden that renders the entry detail body is re-recorded
  and the only diff is the new section: `entry_detail_hidden_{390x844_light,390x844_dark,1024x768_light}`,
  `entry_detail_revealed_totp_390x844_{light,dark}`, `entry_biometric_gate_390x844_light`,
  `entry_copy_confirmation_390x844_light`, `entry_weak_reused_390x844_light`,
  `vault_wide_record_selected_1024x768_{light,dark}`.
- **SC-004**: `flutter analyze` clean, `flutter test` green, goldens green under
  a random ordering seed.

## Non-goals

Any other screen of journeys 01–06 — left as is. Journey 03 and the shell
chrome — closed by spec 019.
