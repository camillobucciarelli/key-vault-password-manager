# Implementation Plan: 019 — Vault journey 03 to navigation model 1a

**Branch**: `feat/019-vault-model-1a` | **Date**: 2026-08-29 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/019-vault-model-1a/spec.md`

## Summary

The vault's content still renders navigation model 1c. This plan replaces the
one widget that carries 1c — the folder/record tree — with the three surfaces
1a specifies (folder tree as a *filter*, records list, `Manage folders`), moves
folder filtering from the widget into the BLoC where the rest of the filtering
already lives, and corrects the rail chrome.

The shape of the change is **subtraction plus relocation**, not addition.
`_EntriesCard` currently does four jobs: it builds the folder tree, it filters
and groups records, it owns folder actions, and it renders the record list.
Three of those move to where the app already keeps that kind of work — folder
filtering to `VaultBloc` beside the search and sort filters, folder actions to a
single routed surface beside every other vault surface, the folder tree to its
own widget consumed by two containers. What is left is a list of rows.

No new BLoC (Constitution II) and no new capability (FR-020). The one genuinely
new mechanism is a fourth surface presentation, `VaultDialogPresentation`,
required because DQ-6 asks for a centred dialog and the router's vocabulary has
only route, sheet and pane.

## Technical Context

**Language/Version**: Dart / Flutter 3.47.1, pinned exactly by `.fvmrc`

**Primary Dependencies**: `flutter_bloc`, `get_it`, `equatable`,
`shared_preferences` (already in `injection_container.dart`), `flutter_svg` for
the vendored Lucide set

**Storage**: the `.kdbx` itself via `VaultKdbxService`; `SharedPreferences` for
the per-database folder expansion state added by FR-006g

**Testing**: `flutter_test` — widget tests under
`test/features/password_manager/presentation/`, goldens under `test/goldens/`,
BLoC tests under `test/features/password_manager/presentation/bloc/`

**Target Platform**: all six Flutter targets; the surfaces in scope are the
vault shell, which is shared

**Project Type**: single Flutter application

**Performance Goals**: the vault must stay responsive with 400+ records
(spec edge case). Folder counts and the descendant set are derived per build
today; they must be computed once per state change, not once per row.

**Constraints**: spec 018's layout classification, width thresholds, surface
presentation rules and single selection owner are consumed unchanged (FR-019).
Every reused user-facing string stays byte-identical (FR-021, Constitution VI).

**Scale/Scope**: two shell part files rewritten, two new part files, two new
widgets, one new router surface and presentation, one BLoC filter, one
preference key, one vendored glyph. Roughly 15 test files touched or added, and a golden inventory
of 12 new files with a predicted 10–18 re-recorded.

## Constitution Check

*GATE: passed before Phase 0. Re-checked after Phase 1 — see the bottom of this
section.*

| Principle | Verdict | Note |
| --- | --- | --- |
| I · Secrets never leak into the shell | **Pass** | Nothing in scope touches a secret. The one-tap copy of FR-010 reuses the existing copy path and its existing confirmation; it neither widens nor lengthens the plaintext window, because the value is read at the moment of the copy exactly as the detail screen reads it. |
| II · Clean architecture layering holds | **Pass** | No new BLoC. Folder filtering joins the search and sort filters already inside `VaultBloc`. `Manage folders` is a routed surface, not a coordinator: it is a single screen over existing events, with no multi-step sequencing or rollback. |
| III · Design tokens are the only source of colour, type and metric | **Pass** | Every metric comes from `PIXEL_SPEC` via `AppColors` / `AppSpacing` / `AppRadii` / `AppMotion` and the widths from `VaultColumns`. The plan adds no hex, no font family, no bare radius. `_VaultUiTokens` keeps only what is genuinely local. |
| IV · Pixel fidelity is testable | **Pass** | Golden inventory named below, 390×844 and 1024×768 in light and dark for the root layouts; state variants name their omitted axes and supply widget assertions. |
| V · Accessibility floor | **Pass, with two obligations** | The chip row and the tree rows are new focusable surfaces: each needs its 2 px focus ring, a ≥ 44 px target even where the glyph is 17, and a `Semantics` selected state. The health dot is already paired with words. The chevron being a separate target from the row (FR-006f) must not produce two overlapping ≥ 44 px targets in a 62 px row — see research R5. |
| VI · Existing behaviour and copy preserved unless marked | **Pass** | The spec marks exactly two changes (`Add record`, `Add subfolder`) with reasons. Every other string is reused verbatim; T-VERBATIM below pins them with a test. |
| VII · Destructive operations ask first and back up | **Pass** | `Delete folder` keeps its existing confirmation and its existing path. This plan moves where the action is invoked from; it does not touch what it does. |
| VIII · Ship the smallest thing | **Pass, with one justified addition** | `VaultDialogPresentation` — see Complexity Tracking. Everything else is a move or a deletion. The folder tree widget is extracted because it has **two** call sites (column, phone sheet) plus a variant (management), which is the second-use rule, not speculation. |
| IX · Verification is local | **Pass** | `flutter analyze` and `flutter test` before every commit; goldens additionally re-run under a randomised seed because this change touches golden harnesses. |

**Post-Phase-1 re-check**: unchanged. The Phase 1 contracts introduced no new
dependency, no new layer crossing and no new persisted secret. The single
`SharedPreferences` key holds a list of group ids, which are not secrets — the
same ids already travel in `VaultState.expandedGroupIds` today.

## Project Structure

### Documentation (this feature)

```text
specs/019-vault-model-1a/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── folder-tree.md   # the tree's behavioural contract, shared by 3 hosts
│   └── vault-surfaces.md# router additions and the presentation table
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks output, not created here
```

### Source Code (repository root)

```text
lib/
├── core/
│   ├── responsive/breakpoints.dart          # consumed unchanged (spec 018)
│   └── widgets/
│       ├── kv_folder_tree.dart              # NEW — the tree, three hosts
│       └── kv_filter_chip.dart              # NEW — the phone chip row's chip
└── features/password_manager/presentation/
    ├── bloc/vault/
    │   ├── vault_bloc.dart                  # folder filter joins search/sort
    │   ├── vault_event.dart                 # SelectVaultFolder, expansion events
    │   └── vault_state.dart                 # derived counts, selected folder
    ├── navigation/vault_shell_router.dart   # ManageFoldersSurface + dialog
    └── screens/vault/
        ├── vault_shell.part.dart            # rail chrome, pane composition
        ├── vault_folders.part.dart          # NEW — column, phone sheet, chips
        ├── vault_manage_folders.part.dart   # NEW — the one management surface
        ├── vault_entries.part.dart          # loses the tree; becomes a list
        └── vault_navigation.part.dart       # the 1c status strip leaves the list

test/
├── core/widgets/kv_folder_tree_test.dart            # NEW
├── features/password_manager/presentation/
│   ├── bloc/vault/vault_folder_filter_test.dart     # NEW
│   └── screens/vault/
│       ├── vault_folder_surface_test.dart           # NEW
│       ├── vault_manage_folders_test.dart           # NEW
│       ├── vault_records_list_test.dart             # NEW
│       ├── vault_chrome_test.dart                   # NEW
│       └── vault_action_inventory_test.dart         # NEW — US3's guarantee
└── goldens/
    ├── vault_shell_test.dart                        # extended
    └── vault_folders_test.dart                      # NEW
```

**Structure Decision**: the existing single-feature Flutter layout is kept
exactly. The vault screen keeps its `part` assembly (`vault_screen.dart` plus
`presentation/screens/vault/*.part.dart`), so the two new surfaces are new part
files, not a new directory. `KvFolderTree` and `KvFilterChip` go to
`lib/core/widgets/` because that is where the design kit lives and because the
tree has three hosts from day one.

## Approach

### Phase A — characterise before changing

Spec 018 taught this the hard way: tests written at the wrong width passed
against unfixed code. Before any structure moves, pin what must not change —
the action inventory of US3, the mobile navigation of spec 018's VR-003, and
the current search/sort behaviour — and confirm each pins something by running
it against `HEAD`.

### Phase B — the BLoC learns about folders

`_computeVisibleEntries` filters `state.allEntries` by search and sorts. It
ignores `currentGroupId` entirely; the tree widget does the grouping. FR-006h
requires the selected folder to filter the node **and its descendants**, so the
filter belongs here, beside the other two.

This is the load-bearing change: once the BLoC answers "which records are
visible", the records list has nothing left to decide, and the tree becomes a
control that emits a selection.

### Phase C — the folder surfaces

One widget, `KvFolderTree`, with three hosts: the desktop column, the phone
`Folders` sheet, and — always fully expanded, with the `•••` menu — the
management surface. One tree, one selected-row style, one menu recipe (FR-006k)
by construction rather than by three widgets agreeing.

### Phase D — the records list becomes a list

`_EntriesCard` loses the tree, the grouping and the folder actions, and gains
the count line with its sort control and the per-row copy. This is where the
diff is most negative.

### Phase E — chrome and the phone header

DQ-8 folded the sort control into this work rather than leaving it as a later
increment: the phone header's second button *is* the sort control, so the header
cannot land without it, and the desktop count line carries the same setting. One
setting, two surfaces, one event.

Rail mark and glyphs, selected fill, the phone screen header, and the rehoming
of the status card's actions per FR-015.

### Phase F — goldens and the audit ledger

Re-record what moved, add the new inventory, and close each audit finding by id
in `specs/_design/CONFORMANCE_AUDIT.md` in the same change (SC-001).

## Golden inventory

Constitution IV requires the exact named list.

**New — root layouts, both themes:**

| File | What it pins |
| --- | --- |
| `vault_1a_wide_1024x768_light.png` | three columns, `All items` selected |
| `vault_1a_wide_1024x768_dark.png` | same, dark |
| `vault_1a_phone_390x844_light.png` | header, search, chip row, record rows |
| `vault_1a_phone_390x844_dark.png` | same, dark |

**New — state variants.** Omitted axes per Constitution IV: light theme only,
and one width each. Dark is covered for these surfaces by the root layouts
above, which share their row, chip and tree components; the omitted variants
are asserted by widget test instead (named in the table).

| File | What it pins | Widget assertion covering the omitted axis |
| --- | --- | --- |
| `vault_1a_wide_folder_selected_1024x768_light.png` | subtree filtering, inclusive count line, `· in <folder>` subtitle | `vault_folder_surface_test.dart` |
| `vault_1a_phone_folders_sheet_390x844_light.png` | the `Folders` sheet, same tree and expansion state as the column | `vault_folder_surface_test.dart` |
| `manage_folders_dialog_1024x768_light.png` | the centred dialog, tree fully expanded, `New folder` | `vault_manage_folders_test.dart` |
| `manage_folders_dialog_1024x768_dark.png` | same, dark — kept because the dialog is a surface no other golden shows | — |
| `manage_folders_screen_390x844_light.png` | the same surface pushed | `vault_manage_folders_test.dart` |
| `manage_folders_row_menu_390x844_light.png` | the one `•••` recipe: `Rename · Move… · Delete` | `vault_manage_folders_test.dart` |
| `vault_1a_sort_menu_1024x768_light.png` | the desktop sort control, active order marked | `vault_records_list_test.dart` |
| `vault_1a_phone_sort_sheet_390x844_light.png` | the phone `Sort` sheet: one radio group, three orders, the active one marked (DQ-8) | `vault_records_list_test.dart` |

**Predicted re-records.** Stated in advance so the actual churn can be checked
against it, as spec 018 did:

- Certain, the vault shell itself: `vault_shell_1024x768_{light,dark}`,
  `vault_shell_390x844_{light,dark}`, `vault_wide_empty_detail_1024x768_{light,dark}`,
  `vault_wide_record_selected_1024x768_{light,dark}`,
  `vault_wide_editor_in_pane_1024x768_{light,dark}` — 10 files.
- Certain, rail glyph and mark: every 1024×768 golden that renders the rail —
  `entry_detail_hidden_1024x768_light`, `editor_new_item_1024x768_light`,
  `editor_generator_column_1024x768_light`, and any of
  `health_1024x768_light` / `settings_1024x768_light` /
  `sync_success_1024x768_light` / `browser_setup_1024x768_light` /
  `host_not_found_diagnostic_1024x768_light` that mount the shell rather than
  the bare screen.
- Certain, tab-bar glyph: every 390×844 golden that renders the tab bar.
- **Must not move**: every golden that mounts a screen without the vault shell —
  the `db_*`, `unlock_*`, `editor_*_390x844`, `entry_*_390x844`, `dup_*`,
  `bin_*`, `csv_*` families. If one of those moves, the change reached further
  than intended and the diff is wrong, not the golden.

## Test strategy

Beyond the goldens, four tests carry requirements no image can:

- **T-VERBATIM** (`vault_action_inventory_test.dart`) — the US3 guarantee.
  A written inventory of every action reachable from the vault today, with its
  exact label, asserted still reachable and still spelled that way. This is the
  test that makes FR-021 and Constitution VI checkable rather than aspirational.
- **T-FILTER** (`vault_folder_filter_test.dart`) — subtree filtering, inclusive
  counts, and the composition of folder + search + sort in every order.
- **T-ONE-TREE** (`kv_folder_tree_test.dart`) — the same expansion state drives
  the column and the sheet, the chevron does not change the filter, and the
  management host is always fully expanded.
- **T-MOBILE** — spec 018's mobile characterisation suite is re-run unchanged.
  It must stay green without edits; an edit to it is a regression of VR-003,
  not a test that needed updating.

## Risks

| Risk | Mitigation |
| --- | --- |
| The action inventory is written from what I can find, and misses something | Build it by enumerating every `PopupMenuItem`, `IconButton` tooltip and pill label reachable from the vault at `HEAD`, mechanically, before Phase B — not from memory. |
| `visibleEntries` changing meaning breaks a caller I have not found | `state.entries` and `state.visibleEntries` have few readers, but the autofill publisher and the health report may read entry collections. Enumerate the readers in Phase A and pin them. |
| The 704–940 band has no artboard | Unchanged from spec 018: the band keeps the folder reachability the list provides. This plan must not make that band worse, and `vault_folder_surface_test.dart` asserts folders stay reachable there. |
| Golden churn hides a real regression | The "must not move" list above turns unexpected churn into a failure to investigate rather than a diff to accept. |

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| A fourth surface presentation, `VaultDialogPresentation` (Constitution VIII) | DQ-6 requires `Manage folders` to be a **centred dialog** where the folder column is visible and a pushed screen on the phone. The router's vocabulary is route, sheet and pane. | Reusing `VaultSheetPresentation`: `KvBottomSheet` caps its width at 560 on desktop but remains bottom-anchored, which is a different surface from the one drawn, and Constitution IV makes that difference testable rather than negotiable. Reusing `VaultPanePresentation` was rejected because a pane would add a column and change spec 018's width arithmetic, which DQ-6 explicitly states it must not. |
