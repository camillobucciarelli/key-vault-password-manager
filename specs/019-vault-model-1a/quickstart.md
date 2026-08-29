# Quickstart — validating spec 019

## Prerequisites

```bash
cd /Users/cbucciarelli/Documents/personal-projects/password-manager-018-desktop-nav
fvm flutter --version      # must be 3.47.1, pinned by .fvmrc
```

A vault with **nested** folders and at least one record inside a subfolder.
Without nesting, DQ-7 is untested — the tree, the inclusive counts and the
`· in <folder>` subtitle all need at least one folder inside another.

## Automated

```bash
fvm flutter analyze
fvm flutter test
fvm flutter test test/goldens --test-randomize-ordering-seed=$RANDOM
```

Expected: analyze clean, suite green, goldens green under a random seed. Then
check the churn against the plan's prediction:

```bash
git status --short test/goldens
```

Every moved file must appear in the plan's "certain" lists. A file from the
"must not move" families moving is a failure to investigate, not a golden to
accept.

## Manual — desktop, ≥ 941

```bash
fvm flutter run -d macos --dart-define-from-file=.env.dart.define.json
```

1. **Three columns** — left column titled with the database file name; first row
   `All items` with the total; every folder with its own count; `Recycle bin`
   and `Duplicates` at the foot with theirs.
2. **The list is records only** — no database status card, no folder rows.
3. **Subtree filter** — select a parent folder that has a subfolder with
   records. Its records appear too, the count line says
   `<n> items · incl. subfolders`, and the subfolder's records carry
   `· in <subfolder>` in the subtitle.
4. **Chevron ≠ filter** — collapse the selected folder. The list must not
   change.
5. **Sort** — open the sort control, pick title descending, then change folder.
   The order holds.
6. **Manage folders** — `Manage` in the column header opens a **centred
   dialog**, tree fully expanded, `New folder` at the top, `•••` per row with
   `Rename · Move… · Delete`. The confirmations must read exactly as they do on
   `main`.
7. **No actions on the column rows** — the folder column rows have no `•••`.

## Manual — phone, 390 × 844

Resize the window below 600, or run on a device.

1. **Header** — `Vault`, `<n> items · <database>.kdbx`, filter and add on the
   right. No database status card.
2. **Chips** — `Folders` first, then `All`, then first-level folders only. A
   vault with deep nesting must not lengthen this row.
3. **`Folders` sheet** — the same tree, the same expansion state as the desktop
   column, `Manage` at its head. Choosing a deep folder filters, closes the
   sheet and becomes the active chip.
4. **One-tap copy** — the copy button on a row copies the password with the
   existing confirmation and no navigation.
5. **`Manage folders`** — from the sheet's `Manage`; the same surface as the
   desktop dialog, pushed full-screen.

## Manual — the band spec 018 owns, 704–940

With a record open, drag the window across 941 and across 704. Never two
details, never two back buttons, and folders stay reachable throughout.

## The action inventory

The point of US3. Walk this list on `main` and on the branch; every item must be
reachable in no more interactions, with identical wording:

`Add record` · `Add subfolder` → `New folder` + `Move…` · `Rename` · `Move` ·
`Delete` (folder) · `Edit` · `Move` · `Attachments` · `Delete` (record) ·
`Recycle bin` · `Duplicates` · sync now · lock · change database · database
settings.

`vault_action_inventory_test.dart` pins the labels; this walk pins the reach.
