# Design conformance audit — implementation vs. Claude Design project

**Date**: 2026-08-29
**Design source**: project `5151eacb-bbf2-44aa-921c-6a0e2d231d12`, mirrored
byte-identical in `docs/design_handoff_keyvault_restyle/` (verified 2026-08-28).
**Normative documents**: `00 Catalogo & Piano`, the per-journey artboards,
`PIXEL_SPEC.md`, `ICONS.md`, and the DQ-1…DQ-3 decisions recorded in
`specs/018-desktop-vault-navigation/spec.md` §Design decisions.
**Method**: artboard + pixel spec read against the shipped Flutter code; every
finding below cites the file that contradicts the design. Findings marked
*[visual]* still need a screenshot of the running app to confirm or close.

## Summary

The restyle landed as **components** but not as **structure** for journey 03.
`lib/core/widgets/` holds the full design kit (`KvListRow`, `KvHealthDot`,
`KvLetterAvatar`, `KvPillButton`, `KvFieldRow`, `KvBottomSheet`, `KvSlider`,
`KvSwitch`, `KvCheckbox`, `KvTag`) and journeys 04–06 use it faithfully. The
vault **shell** — rail, folder column, list column, mobile header — was never
rebuilt to model 1a; it still renders the pre-restyle "strip + folder tree card"
structure, which is model **1c**, the model that was *not* chosen.

| Journey | State |
| --- | --- |
| 01 Database, 02 Unlock | *[visual]* — components in place, structure not re-checked |
| **03 Vault: list, folders, search** | **Divergent — 14 findings, the bulk of this audit** |
| 04 Entry detail | Conforms to the 04-06 artboard; 2 findings |
| 05 Editor, 06 Generator | Conforms; *[visual]* pass owed |
| 07–09 Sync, health, import | *[visual]* — screens exist, not pixel-checked |
| 10–12 Security, autofill, extension | *[visual]* — screens exist, not pixel-checked |
| 13 Icon family | 1 finding (in-app mark) |
| 14 Dark mode | *[visual]* |
| Shell chrome (cross-journey) | 3 findings, one of them a visible defect |

---

## A. Shell chrome — cross-journey

### C-SH-01 · Two back buttons whenever a pushed surface is open · **defect**

`_VaultPaneHost` (`vault_shell.part.dart:1173`) unconditionally renders its own
`IconButton` above every pushed pane. The pane it hosts — `_EntryDetailsPage` —
draws its *own* back chevron whenever `allowsPop` is true, which spec 018 made
`!layout.hasDetailPane`, i.e. exactly the band where `_VaultPaneHost` is used.
Both are therefore always on screen together below 704 px. Reported by the user
with a screenshot at ~670 px; also visible after resizing a window down with a
record open.

**Design**: one back affordance, a 36 px circle icon button in the screen
header (`PIXEL_SPEC` §2 Buttons, §4 Entry detail).

### C-SH-02 · The host back button is unstyled

The same `IconButton` is a bare Material button: no 36 px circle, no
`neutral-100`/`neutral-200` fill, no 44 px hit area. `PIXEL_SPEC` §2 requires a
36 × 36 circle with a 17–19 px glyph inside a 44 px target. Closing C-SH-01 by
deleting the host chrome closes this too.

### C-SH-03 · Rail mark is a glyph, not the app mark

`_VaultRail` (`vault_shell.part.dart:1140`) draws `AppGlyph.key` inside a
38 × 38 / r13 tile. `ICONS.md` §1 "In-app usage of the mark" requires the
**Combinatore mark** itself at 38 × 38 / r13 in the tablet rail (and 40/14 in the
database list header, 88/26 on Welcome, 76/24 on the lock overlay). The mark
ships already (`specs/_design/keyvault-mark.svg`, spec 007A raster set).

---

## B. Journey 03 — Vault: list, folders, search

The adopted model is **1a** (spec 002's own title; re-confirmed as DQ-1 in spec
018). None of the structure below is a matter of taste: 1a is what the repo
chose and what every later artboard assumes.

### Mobile (390 × 844)

### C-03-01 · No screen header

**Design**: `Vault` (Caprasimo 28–30) with `128 items · Personal.kdbx` beneath,
a filter icon button and an `accent-300` add button on the right.
**Implemented**: the pre-restyle `_SyncStatusStrip` card — a database name, a
sync icon and an overflow menu inside a `Card`
(`vault_navigation.part.dart:3`). This is model 1c's status strip, which 1a
replaces with the header plus the Sync tab.

### C-03-02 · No folder filter chips

**Design**: a horizontal chip row `All · Work · Banking · Social · Devs` under
the search field, folders acting as a filter.
**Implemented**: no chip row anywhere; folders are rows inside the list tree.
No `ChoiceChip`/`FilterChip` exists in `lib/`.

### C-03-03 · The list is a folder tree, not a flat record list

**Design**: a flat list of records; folders never appear as rows.
**Implemented**: `_EntriesCard._buildEntriesList`
(`vault_entries.part.dart:319`) builds `_EntryTreeNode`s — folder rows with
expand chevrons, per-folder `•••` menus and nested indentation. This is the
single largest structural divergence and it is what the user's screenshots
show on both mobile and desktop.

### C-03-04 · Row trailing is an overflow menu, not one-tap copy

**Design**: health dot, then a 36 px **copy** button — "copia a un tocco dalla
lista" is principle 2 of the catalogue.
**Implemented**: health dot, then `PopupMenuButton` "Record actions"
(`vault_entries_details.part.dart:290`). Everything else in the row (38 avatar,
title 15/600, subtitle 12.5, 62 min-height, `accent-200` selected state) already
matches `PIXEL_SPEC` §2.

### C-03-05 · Search placeholder and count

**Design**: `Search 128 items` — the count is in the placeholder, and repeated
as `128 items` above the list.
**Implemented**: `Search records and folders`, no count anywhere. (The string
matches the *04-06* artboard, which DQ-1 ruled is the editor's working context,
not the shell.)

### C-03-06 · The sort control is missing — the sort itself is not

**Design**: `Username ↑` at the right of the count row; the catalogue lists
`Ordinamento (title ↑↓, username)` as an existing journey-03 state.
**Implemented**: the sort is fully built and **orphaned**. `VaultEntrySort`
(`titleAsc`, `titleDesc`, `usernameAsc`), `VaultState.sortBy` defaulting to
`usernameAsc` — which is exactly what the artboard draws — the `SetVaultSort`
event and the comparator in `VaultBloc` all exist. Nothing in `lib/` dispatches
`SetVaultSort`, so the user can never leave the default. This is a missing
control, not missing behaviour.

### Tablet / desktop (1024 × 768)

### C-03-07 · Folder column has no database identity

**Design**: `Personal.kdbx` as the column title, Caprasimo.
**Implemented**: the literal string `'Folders'`
(`vault_shell.part.dart:1215`).

### C-03-08 · Folder column has no "All items" row

**Design**: `All items 128` is the first row and the default selection.
**Implemented**: only the raw group list; the root has no row of its own.

### C-03-09 · Folder column has no counts

**Design**: every row carries its record count (`Work 41`, `Banking 12`, …).
**Implemented**: `ListTile(title: Text(group.name))` — name only.

### C-03-10 · Folder column has no hygiene shortcuts

**Design**: `Recycle bin 3` and `Duplicates 4` pinned at the bottom of the
column.
**Implemented**: both are reachable only from the strip's overflow menu.

### C-03-11 · Folder column uses raw `ListTile`s

The column is a `ListView` of Material `ListTile`s, so it inherits Material's
metrics and selection colours instead of `KvListRow` / `PIXEL_SPEC` §2 (radius
22, padding 13/16, `accent-200` selected).

### C-03-12 · The list column shows the mobile status strip

At every width the vault pane is `strip card + entries card`. The design's
tablet list column is `search · count · sort · rows` with the database identity
living in the folder column instead.

### C-03-13 · Rail and tab bar destination glyphs

Resolved by the design source on 2026-08-29 (DQ-4 below): `ICONS.md` is
normative for glyph identity.

- **Vault**: must be `lock`. Implemented as `AppGlyph.folder`
  (`vault_shell.part.dart:891`). `folder` stays mapped to Groups — the folders
  are the groups, not the vault, so there is no collision.
- **Sync**: must be `refresh-cw`. Implemented as `AppGlyph.cloud`.
- **Settings**: `settings` (gear). The code is already right; the sun drawn in
  the `03` artboards is an error, not a variant — `sun` is already the theme
  selector, so using it for Settings collides inside one set.

The vendored assets are the real Lucide paths at stroke 2.75
(`assets/icons/lucide/`), so nothing is owed on the asset side.

### C-03-14 · Selected rail destination has no fill

**Design**: the active destination sits on an `accent-200` rounded tile (the
user's screenshot of the design shows the peach tile under the Vault icon).
**Implemented**: colour change only (`colors.linkText`).

---

## C. Journey 04 — Entry detail

Structurally conformant: header avatar/title/subtitle, 36 px circle actions,
field rows, strength strip, TOTP row and reveal countdown all exist as designed
(`vault_entry_detail.part.dart`, `widgets/entry/*`).

### C-04-01 · Empty state copy is undesigned *[visual]*

`No item selected` / `Select a record from the list to view all details and copy
fields.` (`vault_entries_details.part.dart:511`) has no artboard. The design's
empty states elsewhere use a feature circle + Caprasimo title + 13.5 body.

### C-04-02 · Action row position — **closed, code is right**

Confirmed by the design source (DQ-5): the actions belong at the top, per the
04-06 artboard. The bottom row in `03`'s 1a panel is a single exception that
`03` already contradicts itself on — its own 1c model puts the same three
actions at the top — it mixes registers (a credential action beside object
management and a counter), and `margin-top:auto` does not survive a persistent
column that scrolls.

### C-04-03 · The action row is missing `Open <host>`

**Normative inventory**: `Copy password` (primary) · `Copy username` ·
`Open <host>`, the last omitted when the record has no URL.
**Implemented**: `Copy password` and `Copy username` only
(`vault_entry_detail.part.dart:413`).

### C-04-04 · `Attachments` is in the overflow menu as well as a section

**Normative**: attachments are a section with a count and a `Manage` action;
the header overflow carries object management only.
**Implemented**: `_EntryAction.attachments` is a menu item
(`vault_entry_detail.part.dart:527`) *and* reachable from the body row, so the
same affordance exists twice.

### C-04-05 · No `Duplicate` record action — **deliberately deferred**

The normative overflow inventory is `Move / Delete / Duplicate`. Duplicating a
record does not exist anywhere in the app: no `_EntryAction`, no `VaultEvent`,
no service call. Adding it is a **new feature**, which the catalogue's own
assumption forbids ("Zero funzionalità nuove inventate"). Recorded here and not
implemented; it needs a product decision, not a conformance fix.

---

## D. Journeys not yet pixel-audited

01, 02, 05, 06, 07, 08, 09, 10, 11, 12, 14 have their screens implemented and
use the design kit. A full page-by-page pass needs the running app: the audit
above is code-verified, and guessing at pixels from source is how the first
round of drift happened. Screenshots of each screen (light + dark, phone +
desktop) close them.

---

## Proposed remediation

| Spec | Scope | Why separate |
| --- | --- | --- |
| **019** | Journey 03 to model 1a + shell chrome (C-SH-01…03, C-03-01…14) | One structural change: the vault shell. Carries the visible defect. |
| **020** | Pixel pass on journeys 01–02 and 04–06 | Needs the visual pass first |
| **021** | Pixel pass on journeys 07–09 | ditto |
| **022** | Pixel pass on journeys 10–12 and dark mode | ditto |

Spec 019 depends on spec 018's `VaultLayoutClass`, so it stacks on that branch.

---

## Design decisions taken during this audit

Answered by the design source on 2026-08-29. Normative from here on.

- **DQ-4 — glyph identity**: DQ-1's split applies by *axis*, not by file. The
  artboards are normative for **layout and geometry**; the written documents are
  normative for **glyph identity and mapping**. So `ICONS.md` wins on which
  glyph a slot uses. Consequences in C-03-13. The artboards themselves are owed
  three corrections (below).
- **DQ-5 — detail action row**: top, per 04-06. Full normative inventory for
  the detail panel: header with avatar + title + `Edit`; action row
  `Copy password` / `Copy username` / `Open <host>`; fields; `Attachments` as a
  section with its count; `Move` / `Delete` / `Duplicate` in the header's
  `more-vertical` overflow.

### Owed in the design project *(not this repo's work)*

Carried forward from spec 018's list, plus what DQ-4 adds:

- `03`: rail `76 → 72`; Settings glyph sun → `settings` in the tab bar (line 81)
  and the rail (line 94); Vault glyph redrawn from the real Lucide `lock`.
- `04-06`: list `352 → 330` in both artboards; remove `opacity:.5` from the list
  in "Editor con generatore aperto".
- Add a drawn artboard for the 704–940 folder-collapsed band.
- The hand-drawn glyph paths across the artboards (`lock`, `refresh-cw`,
  `shield-check`) are approximations, not Lucide. Under "do not mix sets" a
  redrawn padlock is effectively a third set. The real Lucide path at stroke
  2.75 is normative and the artboards follow it, not the other way round. The
  repo's vendored assets are already correct.

### Applied in this repo on 2026-08-29

- `ICONS.md` (both copies): added `— (new) | lock | Vault tab, vault slot of
  the rail`.
- `PIXEL_SPEC.md` (both copies): "Tablet columns" rewritten to the single
  values `72` / `330`, with the generator column and the derived thresholds —
  the correction spec 018 owed.
