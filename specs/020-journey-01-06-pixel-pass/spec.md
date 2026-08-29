# 020 — Pixel pass on journeys 01–02 and 04–06

**Status**: Draft — not ready for `/speckit-plan` · **Kind**: Conformance / Design fidelity
**Created**: 2026-08-29
**Depends on**: 019 (journey 03 and the shell chrome)
**Source**: `specs/_design/CONFORMANCE_AUDIT.md` — proposed remediation table

## Why this is a draft

Two of the three parts of this spec cannot be written yet, and writing them
anyway is exactly how the drift being fixed here was created: the first audit
pass guessed at pixels by reading source, and guessed wrong often enough that
journey 03 had to be rebuilt.

Journeys 01, 02, 05 and 06 have **not** been pixel-audited. Their screens exist
and use the design kit, but comparing them to the artboards needs the running
app — screenshots of each screen, light and dark, phone and desktop. Until
those exist there is nothing here to specify.

**What unblocks this spec**: screenshots. Nothing else.

## What IS ready

One finding is code-verified, already attempted, and deliberately left open by
spec 019. It can be specified today.

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

**Acceptance sketch** (to be turned into real FRs when this spec is taken up):

- The entry detail always shows an attachments section with its count,
  including `0`.
- The header overflow contains exactly `Move`, `Delete`, `Duplicate`.
- Adding the first attachment to a record with none is reachable, at every
  width, in no more interactions than today.
- Spec 018's FR-011 is amended in this spec, with the amendment written down,
  rather than the test being edited.

## Scope when the screenshots arrive

- **01** — Welcome / database list
- **02** — Unlock
- **04** — Entry detail (the remaining findings; C-04-01, C-04-03 and C-04-05
  were closed by spec 019)
- **05** — Entry editor
- **06** — Password generator

## Non-goals

Journey 03 and the shell chrome — closed by spec 019.
