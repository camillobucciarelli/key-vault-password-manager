# 019 — Vault journey 03 to navigation model 1a

**Feature Branch**: `feat/019-vault-model-1a`

**Created**: 2026-08-29

**Status**: Draft

**Input**: User description: "Bring vault journey 03 (list, folders, search) to the adopted navigation model 1a, and correct the shell chrome, per specs/_design/CONFORMANCE_AUDIT.md findings C-SH-03 and C-03-01..C-03-14."

## Context

The vault is the app's home. The restyle chose navigation **model 1a** — spec
002 is titled "Navigation shell (model 1a)", and spec 018 re-confirmed it as
DQ-1 when two artboards disagreed about the column strip.

Model 1a was never applied to the vault's own content. The rail, the tab bar and
the surfaces around it moved; the folder column, the records list and the mobile
header did not. They still render **model 1c** — "strip evoluta", the option the
project explicitly did not choose: a database status card on top of a card that
mixes folders and records in one expandable tree.

The audit at `specs/_design/CONFORMANCE_AUDIT.md` records 17 findings behind
that one sentence. This spec closes them. It is a **conformance** change: no new
capability is invented, and every action reachable today stays reachable.

Two findings in the audit are deliberately **not** in scope. `C-04-05`
(`Duplicate` record action) is a new feature the design catalogue's own
assumption forbids. `C-04-03`/`C-04-04` belong to the entry detail panel, which
this spec does not touch.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The desktop vault reads as three columns (Priority: P1)

Someone opens their vault on a laptop. The left column tells them which database
is open and lists their folders with how much is in each, plus the two hygiene
shortcuts. The middle column is the records: a search field that says how many
records it is searching, the count and the current sort, then the records
themselves — one row per record, nothing else. The right column is the record
they picked.

**Why this priority**: This is the screen the user reported as wrong, and it is
where the divergence is most visible: the middle column currently carries a
database status card and a folder tree, so records compete for space with
navigation that already has its own column.

**Independent Test**: Open a vault at 1024 × 768. The three columns can be
described from the design artboard alone, without the reader having seen the
code.

**Acceptance Scenarios**:

1. **Given** a vault with folders, **When** it is opened at 1024 × 768, **Then**
   the left column is titled with the database file name, its first row is
   `All items` with the total record count, each folder row carries its own
   record count, and `Recycle bin` and `Duplicates` sit at the bottom with their
   counts.
2. **Given** the vault at 1024 × 768, **When** the user looks at the middle
   column, **Then** it contains a search field, a count line with the sort
   control, and record rows only — no database status card and no folder rows.
3. **Given** a folder is selected in the left column, **When** the user selects
   `All items`, **Then** the middle column shows every record in the vault.
4. **Given** a record is selected, **When** the user selects a different folder,
   **Then** the detail pane behaves exactly as spec 018 defined it — the
   selection is dropped only when the record is no longer visible.

---

### User Story 2 - The phone vault is a list, not a file browser (Priority: P1)

On a phone the user sees `Vault`, how many records there are and which database
they are in, a search field, their folders as a row of filter chips, then their
records. Tapping a record opens it; tapping the copy button on a row copies the
password without opening anything.

**Why this priority**: Equal to US1 — it is the same divergence on the surface
that is used most. The catalogue's second principle is "the search is the home"
and "one-tap copy from the list"; today the first thing on the screen is a
database status card and the rows lead only to a menu.

**Independent Test**: Open a vault at 390 × 844 and copy a password without
opening the record.

**Acceptance Scenarios**:

1. **Given** a vault on a phone, **When** it is opened, **Then** the screen
   starts with the `Vault` title, `<n> items · <database>.kdbx` beneath it, and
   the filter and add buttons on the right — not a database status card.
2. **Given** the phone vault, **When** the user reads the search field, **Then**
   its placeholder states how many records it searches.
3. **Given** a vault with folders, **When** the user taps a folder chip, **Then**
   the list shows that folder's records and the chip is the selected one; `All`
   returns to every record.
4. **Given** a record row, **When** the user taps its copy button, **Then** the
   password is copied and the existing confirmation appears, with no navigation.
5. **Given** any record row, **When** it is displayed, **Then** it carries the
   password-health dot, and the dot is never the only signal of a problem.

---

### User Story 3 - Every action that exists today still has a home (Priority: P1)

Nothing the user can do today disappears. Creating, renaming, moving and
deleting a folder; moving a record; opening the recycle bin, the duplicates
view, the database settings and the sync actions — all remain reachable, and the
user is not asked to learn a second place for something they already know.

**Why this priority**: The structures being removed are the *only* path to
several of these actions today: folder management lives in the tree rows'
overflow menus, and the database actions live in the status card's overflow.
Removing the container without rehoming its contents would be a regression, not
a restyle. Constitution VI makes this non-negotiable.

**Independent Test**: Walk the list of actions reachable before the change and
reach each one after it.

**Acceptance Scenarios**:

1. **Given** the reworked vault, **When** the user wants to create, rename, move
   or delete a folder, **Then** `Manage folders` is the one place to do it,
   reached from `Manage` in the header of the folder surface — a dialog on the
   desktop, a pushed screen on the phone, the same surface either way.
2. **Given** the reworked vault, **When** the user wants the recycle bin or the
   duplicates view, **Then** both are reachable in one interaction from the
   vault screen at every width.
3. **Given** the reworked vault, **When** the user wants to sync now, lock, or
   change database, **Then** each is reachable, and its user-facing wording is
   byte-identical to today's.
4. **Given** any action moved by this spec, **When** it is invoked, **Then** it
   behaves exactly as before — same events, same confirmations, same messages.

---

### User Story 4 - The rail and tab bar say what they are (Priority: P2)

The rail shows the KeyVault mark, and the four destinations use the glyphs the
icon specification assigns them. The destination the user is on is visibly
filled, not merely tinted.

**Why this priority**: Visible on every screen and cheap, but it costs the user
nothing today beyond a wrong first impression — the destinations work.

**Independent Test**: Compare the rail against the design artboard and
`ICONS.md`.

**Acceptance Scenarios**:

1. **Given** the vault at a width that shows the rail, **When** the user looks at
   the top of the rail, **Then** it shows the KeyVault mark at 38 × 38 with a
   13 px radius, not a generic glyph.
2. **Given** the rail or the tab bar, **When** the destinations are rendered,
   **Then** Vault uses `lock`, Health uses `shield-check`, Sync uses
   `refresh-cw` and Settings uses `settings`.
3. **Given** a selected destination, **When** it is rendered, **Then** it sits on
   a filled tile, and the selected state is announced to assistive technology as
   it is today.

---

### User Story 5 - The user can choose the order (Priority: P3)

The count line carries the current sort, and tapping it offers the orders the
vault already supports.

**Why this priority**: Smallest of the five and the least costly to defer, but
it is nearly free: the ordering is already built and the user simply cannot
reach it.

**Independent Test**: Change the sort and observe the list re-order.

**Acceptance Scenarios**:

1. **Given** a populated vault, **When** the user opens the sort control, **Then**
   it offers exactly the orders the vault already implements — title ascending,
   title descending, username ascending — and shows which one is active.
2. **Given** a chosen sort, **When** the user changes folder or searches, **Then**
   the chosen sort still applies.

---

### Edge Cases

- **Empty vault**: the count reads zero, the list shows the existing empty
  state, and the folder column still shows `All items` with a zero count.
- **No folders**: the chip row and the folder column have `All items` only; the
  chip row does not occupy space it cannot use.
- **Nested folders**: resolved by DQ-6 — the folder column and the phone
  `Folders` sheet show the same collapsible tree; the chip row shows the first
  level only. Selecting a node filters that node **and its descendants**.
- **Very long folder name / very large counts**: rows truncate rather than wrap
  or overflow.
- **400+ records**: the list scrolls without the header, search or count line
  scrolling away from the user's reach.
- **Search active with a folder chip selected**: the two compose — the search
  runs inside the selected folder — and the count line says what is being
  counted.
- **A folder is deleted while its chip is selected**: the selection falls back to
  `All items` rather than leaving an empty list under a chip that no longer
  exists.
- **The record under the detail pane stops being visible** (folder change,
  search, delete): unchanged from spec 018 — the shell drops the selection.

## Requirements *(mandatory)*

### Functional Requirements

#### The folder surface

- **FR-001**: The folder column MUST be titled with the open database's file
  name.
- **FR-002**: The folder surface MUST offer `All items` as its first entry,
  carrying the vault's total record count, and it MUST be the default selection.
- **FR-003**: Every folder entry MUST carry the number of records it contains.
- **FR-004**: The folder column MUST offer `Recycle bin` and `Duplicates` at its
  foot, each with its count, reaching the same surfaces they reach today.
- **FR-005**: On the phone, folders MUST be presented as a single row of filter
  chips beneath the search field: a `Folders` chip first, then `All`, then the
  **first-level** folders only. Deeper folders are reached through the `Folders`
  sheet, never by lengthening the chip row.
- **FR-005a**: The `Folders` chip MUST open a sheet showing the same tree as the
  desktop folder column, with the same expansion state and the same selected
  row. Choosing a folder MUST filter, close the sheet, and become the active
  chip.
- **FR-006**: Folder management MUST live in one surface, `Manage folders`,
  which is the **same surface at every width** — the same tree, the same
  `New folder`, the same per-row `Rename · Move… · Delete`. Only its container
  differs: a centred dialog where the folder column is visible, a pushed screen
  on the phone.
- **FR-006a**: There MUST be exactly one entry point to `Manage folders` per
  width, and it MUST sit in the header of the folder surface — `Manage` in the
  folder column's header, `Manage` at the head of the phone `Folders` sheet. No
  additional menu is added to the phone header.
- **FR-006b**: `Manage folders` MUST show the tree fully expanded, without
  subtitles: position is carried by indentation.
- **FR-006c**: The rows of the folder column and the chips MUST carry **no
  actions at all**. They are filters.
- **FR-006d**: The confirmations and user-facing strings of `Rename`, `Move…`
  and `Delete` MUST be taken verbatim from the code as it stands today
  (Constitution VI).
- **FR-006e**: A folder's parent MUST be changed only through `Move…`.

#### The folder tree

- **FR-006f**: A chevron MUST appear only on nodes that have children, and it
  MUST be a separate target from the row: expanding or collapsing MUST NOT
  change the filter.
- **FR-006g**: The expansion state MUST be shared by the folder column and the
  phone sheet, and persisted per database.
- **FR-006h**: Selecting a folder MUST filter that folder **and its
  descendants**.
- **FR-006i**: Folder counts MUST be inclusive of subfolders, and the list MUST
  say so (`<n> items · incl. subfolders`).
- **FR-006j**: A record shown because it lives in a subfolder of the selected
  folder MUST name that subfolder in its subtitle (`· in <folder>`).
- **FR-006k**: The selected row MUST use one style everywhere — the desktop
  column's — and the `•••` menu MUST use one recipe everywhere.

#### The records list

- **FR-007**: The records list MUST contain records only. Folders MUST NOT
  appear as rows in it.
- **FR-008**: The list MUST show a search field whose placeholder states the
  number of records in scope, and a count line stating the same number.
- **FR-009**: The count line MUST carry a sort control reflecting
  `VaultState.sortBy` and MUST offer every order the vault already implements.
  No new ordering may be added.
- **FR-010**: Every record row MUST show the letter avatar, title, subtitle and
  password-health dot it shows today, and MUST additionally offer a one-tap copy
  of the password.
- **FR-011**: Selecting a row MUST continue to report the selection upward
  exactly as spec 018 defined; this spec introduces no second selection owner.
- **FR-012**: The record actions available today MUST remain available from the
  list at every width.
- **FR-013**: The database status card MUST NOT appear inside the records list
  at any width.

#### The phone header

- **FR-014**: The phone vault MUST open with a screen header carrying `Vault`,
  the record count and the database name, a filter affordance and an add
  affordance.
- **FR-015**: Database-level actions displaced from the status card — sync now,
  lock, change database, recycle bin, duplicates — MUST each remain reachable in
  no more interactions than today, with byte-identical wording.

#### The chrome

- **FR-016**: The rail MUST show the KeyVault mark as the artwork itself, at
  38 × 38 with a 13 px radius.
- **FR-017**: Destination glyphs MUST be `lock` (Vault), `shield-check`
  (Health), `refresh-cw` (Sync) and `settings` (Settings), per `ICONS.md` as
  made normative by DQ-4.
- **FR-018**: The selected destination MUST be rendered on a filled tile in both
  the rail and the tab bar, in addition to — never instead of — its existing
  accessible selected state.

#### Boundaries

- **FR-019**: This spec MUST NOT change the layout classification, the width
  thresholds, the surface presentation rules or the selection ownership
  established by spec 018. It consumes them.
- **FR-020**: This spec MUST NOT add a capability the vault does not already
  have. Where the design draws something the app cannot do, the design is
  recorded as owed and not built.
- **FR-021**: Every user-facing string that exists today and is reused MUST stay
  byte-identical (Constitution VI).

### Key Entities

- **Folder entry**: a folder shown in the folder surface — its name, its record
  count, whether it is the current filter, and its place in the tree.
- **Hygiene shortcut**: `Recycle bin` and `Duplicates` — a label, a count and the
  existing surface each opens.
- **Record row**: unchanged — avatar, title, subtitle, health state, and now a
  copy affordance.
- **Sort choice**: the existing `VaultEntrySort`, surfaced rather than
  introduced.

## Design decisions *(resolved)*

Both questions this spec opened were referred to the design source and answered
on 2026-08-29, with four new artboards (`2a` desktop, `2b`–`2d` phone) in
`03 Vault - modelli di navigazione.dc.html` and a written record now mirrored at
`specs/_design/decisions-folder-management.md`. The repo's copy of the artboard
file is re-synced from the project.

- **DQ-6 — folder management**: one surface, `Manage folders`, identical at
  every width; only the container changes. One entry point per width, always in
  the header of the folder surface. The column rows and the chips carry no
  actions — they are filters. The dialog adds no column, so the width
  arithmetic of spec 018 is untouched.
- **DQ-7 — nesting**: a collapsible tree in the column and the phone sheet with
  shared, persisted expansion state; first-level chips only on the phone;
  the management surface always fully expanded; counts inclusive of subfolders
  and declared as such; the parent changed only through `Move…`.

### Behaviour this spec deliberately changes

The design's folder menu is `Rename · Move… · Delete`. Today's tree rows offer
two more, which lose their current home. Both are recorded here rather than
silently dropped (Constitution VI):

- **`Add record`** — the design's add affordance already creates into the folder
  the user is in ("Saved into Devs — the folder you were in", journey 05), which
  is what the row action did. It moves to the header's add button; no capability
  is lost.
- **`Add subfolder`** — becomes `New folder` followed by `Move…`, one interaction
  more than today. Accepted because DQ-6 states the parent is changed only
  through `Move…`, and a second way to set a parent is the kind of duplicated
  affordance this whole spec exists to remove.

Still owed by the design source: the 704–940 artboard (folder column collapsed,
switcher on the rail). Spec 018 already handles that band with the folder
navigation the list provides, and this spec does not regress it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-000**: Folder management is reachable from exactly one place at each
  width, and the tree, the `New folder` action, the `•••` recipe and the
  selected-row style are the same on the desktop dialog and the phone screen —
  verified by comparing the two surfaces item for item.
- **SC-001**: Every one of the 17 audit findings in scope
  (`C-SH-03`, `C-03-01` … `C-03-14`) is closed or explicitly re-recorded as
  deferred with a reason.
- **SC-002**: A reader given only the design artboard for model 1a and the
  running app at 1024 × 768 and 390 × 844 finds no structural difference between
  them.
- **SC-003**: Copying a password from the list takes one interaction from the
  vault screen, down from three today (open the record, then copy).
- **SC-004**: Every action reachable from the vault before this change is still
  reachable after it, in no more interactions, with identical wording — verified
  item by item against a written inventory.
- **SC-005**: No golden at 390 × 844 or 1024 × 768 is left un-recorded: the spec
  names its golden inventory and every named file exists and is asserted.
- **SC-006**: `flutter analyze` is clean and `flutter test` is green before any
  commit, and the suite passes under a randomised order seed.
- **SC-007**: Contrast holds at ≥ 4.5:1 for every text/background pairing the
  new surfaces introduce, and no state is signalled by colour alone.

## Assumptions

- Spec 018 is a prerequisite: its `VaultLayoutClass`, its width thresholds and
  its single selection owner are consumed unchanged.
- Model 1a is settled and is not reopened by this spec (spec 002; DQ-1).
- `ICONS.md` is normative for glyph identity and the artboards for geometry
  (DQ-4). The vendored Lucide assets are already the real paths at stroke 2.75,
  so no asset work is required.
- The KeyVault mark ships already (spec 007A); this spec consumes it and does
  not regenerate it.
- The ordering behaviour is already correct in the vault; only its control is
  missing, so no comparator changes.
- DQ-6/DQ-7 are settled and are not reopened by the plan.
- The vault already supports every folder operation this spec rehomes; nothing
  in `Manage folders` is a new capability.
- The entry detail panel is out of scope; `C-04-01`, `C-04-03` and `C-04-04`
  stay open in the audit for a later spec.
- `C-04-05` (`Duplicate` a record) is a new feature and is not built here.
- The phone tab bar, the Health, Sync and Settings destinations and every
  surface spec 018 routes are unchanged apart from their glyphs.
