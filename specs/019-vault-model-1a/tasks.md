---

description: "Task list for spec 019 — vault journey 03 to navigation model 1a"
---

# Tasks: Vault journey 03 to navigation model 1a

**Input**: Design documents from `specs/019-vault-model-1a/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: REQUIRED. Constitution IV and V make pixel fidelity and the
accessibility floor part of the definition of done, and US3 is a pure
non-regression story. Test tasks are first-class here.

**Organization**: grouped by user story. Phase 2 is deliberately heavy: it
contains both the characterisation that pins what must not change **and** the
BLoC and widget work that US1, US2 and US3 all sit on. Splitting that across the
stories would mean three of them each half-building the same tree.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on incomplete work)
- **[Story]**: the user story the task serves (US1…US5)

## Path conventions

Flutter app. Production code under `lib/`, tests mirror it under `test/`,
goldens in `test/goldens/`. All paths are repo-relative to the worktree
`password-manager-018-desktop-nav`.

---

## Phase 1: Setup

**Purpose**: confirm the toolchain and capture the baseline the golden-churn
prediction is checked against.

- [ ] T001 Verify the pinned toolchain in the worktree: `fvm flutter --version` is 3.47.1 per `.fvmrc`, then `fvm flutter pub get`
- [ ] T002 Record the pre-change baseline outside `specs/` (that directory is tracked and feeds the Projects #2 sync): `fvm flutter analyze`, `fvm flutter test`, the passing count, and `ls test/goldens/*.png | sort`, so the plan's churn prediction is checked by diff rather than by memory

---

## Phase 2: Foundational

**Purpose**: pin today's behaviour before any production file moves, then build
the three things US1, US2 and US3 all consume — the folder filter in the BLoC,
the persisted expansion state, and the one tree widget.

**⚠️ BLOCKING**: no user-story phase starts until T003–T014 are done.

### Characterisation — must pass against unchanged code first

- [ ] T003 [P] Write `test/features/password_manager/presentation/screens/vault/vault_action_inventory_test.dart`: enumerate mechanically — not from memory — every action reachable from the vault at `HEAD` (every `PopupMenuItem` label, `IconButton` tooltip and pill label under `lib/features/password_manager/presentation/screens/vault/`), assert each is present with its exact string. Run it against `HEAD` and confirm green; this is the US3 guarantee and FR-021's enforcement
- [ ] T004 [P] Extend `test/features/password_manager/presentation/screens/vault/vault_surface_presentation_baseline_test.dart` to assert contract S1: every pre-existing row of `presentationFor` is unchanged at the spec-018 boundary widths 599/600/703/704/940/941/994/995
- [ ] T005 [P] Confirm `test/features/password_manager/presentation/screens/vault/vault_navigation_mobile_characterisation_test.dart` (spec 018 VR-003) is green unchanged, and record that it must stay green **without edits** — an edit to it is a regression, not a test that needed updating
- [ ] T006 [P] Pin the readers of the collections whose meaning changes: assert in `test/features/password_manager/presentation/bloc/vault/vault_visible_entries_readers_test.dart` that `allEntries` still feeds the duplicate service, the health report and the autofill publisher unchanged, so the `visibleEntries` change cannot leak into them (research R1)

### The BLoC learns about folders

- [ ] T007 Add the derived folder aggregates to `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart`: one post-order walk of `groups` over `allEntries` producing `folderCounts` (inclusive of descendants), `totalCount` excluding the recycle bin, and `descendantIds(groupId)` — computed once per state change, never per row (plan Performance Goals)
- [ ] T008 Surface those aggregates on `lib/features/password_manager/presentation/bloc/vault/vault_state.dart` per `data-model.md`, keeping `VaultState` equatable and its `props` free of any entry value
- [ ] T009 Add `SelectVaultFolder(String? groupId)` to `lib/features/password_manager/presentation/bloc/vault/vault_event.dart` and its handler to `vault_bloc.dart`: sets `currentGroupId` (`null` = `All items`) and recomputes `visibleEntries`. It MUST NOT touch expansion (FR-006f)
- [ ] T010 Teach `_computeVisibleEntries` in `vault_bloc.dart` the folder filter, applied before search and sort, using `descendantIds` so a selected folder shows its subtree (FR-006h)
- [ ] T011 [P] Write `test/features/password_manager/presentation/bloc/vault/vault_folder_filter_test.dart` (T-FILTER): subtree filtering, counts inclusive of subfolders, `All items` equals the whole vault minus the bin, and folder + search + sort composing in every order
- [ ] T012 Add `SetVaultFolderExpanded(String groupId, bool expanded)` to `vault_event.dart` and `vault_bloc.dart`, persisting the set through the already-registered `SharedPreferences` under one key per database, and restoring it at unlock (FR-006g, research R3)
- [ ] T013 [P] Write `test/features/password_manager/presentation/bloc/vault/vault_folder_expansion_test.dart`: expansion survives a lock/unlock cycle, is per-database, and never changes `visibleEntries`

### The one tree widget

- [ ] T014 Create `lib/core/widgets/kv_folder_tree.dart` implementing every guarantee in `contracts/folder-tree.md` — `filter` and `manage` modes, chevron only on nodes with children and only calling `onToggleExpanded`, one selected-row style, one `•••` recipe, one indentation level per depth
- [ ] T015 [P] Write `test/core/widgets/kv_folder_tree_test.dart` (T-ONE-TREE) asserting G1–G8 by name, including G7: the chevron and the row are both ≥ 44 × 44 and their hit areas do not overlap (research R5, Constitution V)
- [ ] T016 [P] Create `lib/core/widgets/kv_filter_chip.dart` for the phone chip row, with the 2 px focus ring, a ≥ 44 px target and a `Semantics` selected state (Constitution V)

**Checkpoint**: the BLoC answers "which records are visible" and one tree widget
exists. The UI phases now only compose.

---

## Phase 3: User Story 1 — The desktop vault reads as three columns (P1) 🎯 MVP

**Goal**: the 1024 × 768 vault is the folder column, the records list and the
detail pane the artboard draws.

**Independent test**: open a vault at 1024 × 768 and describe the three columns
from the artboard alone.

- [ ] T017 [US1] Create `lib/features/password_manager/presentation/screens/vault/vault_folders.part.dart` and register the part in `lib/features/password_manager/presentation/screens/vault_screen.dart`
- [ ] T018 [US1] Build the desktop folder column in `vault_folders.part.dart`: database file name as the title (FR-001), `All items` with the total as the first and default row (FR-002), `KvFolderTree` in `filter` mode with per-folder inclusive counts (FR-003), and `Manage` in the header as the single entry point (FR-006a)
- [ ] T019 [US1] Add the hygiene shortcuts `Recycle bin` and `Duplicates` at the foot of the column with their counts from `recycleBinEntries.length` and `duplicateGroups.length`, opening the surfaces they open today (FR-004)
- [ ] T020 [US1] Replace `_VaultFolderPane` in `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart` with the new column, deleting the literal `'Folders'` title and the raw `ListTile`s (C-03-07, C-03-11)
- [ ] T021 [US1] Strip the tree out of `lib/features/password_manager/presentation/screens/vault/vault_entries.part.dart`: delete `_EntryTreeNode`, the grouping walk, the per-folder rows and the folder actions. The card renders `state.visibleEntries` as rows and nothing else (FR-007, C-03-03)
- [ ] T022 [US1] Add the count line above the list in `vault_entries.part.dart`: `<n> items`, and `<n> items · incl. subfolders` when a folder with descendants is selected (FR-006i), with the sort control's slot reserved for US5
- [ ] T023 [US1] Give the search field the count-bearing placeholder `Search <n> items` (FR-008, C-03-05), keeping the existing search event and behaviour
- [ ] T024 [US1] Add `· in <folder>` to the subtitle of a record shown because it lives in a subfolder of the selection (FR-006j)
- [ ] T025 [US1] Remove `_VaultSyncStatusStrip` from the vault pane composition in `vault_shell.part.dart` so no database status card appears inside the records list at any width (FR-013, C-03-12). Its actions are rehomed in US3 — do not delete them here
- [ ] T026 [P] [US1] Write `test/features/password_manager/presentation/screens/vault/vault_folder_surface_test.dart`: the column's structure, `All items` default, inclusive counts, hygiene shortcuts, subtree filtering end to end, and that folders stay reachable in the 704–940 band (plan Risks)
- [ ] T027 [P] [US1] Write `test/features/password_manager/presentation/screens/vault/vault_records_list_test.dart`: the list contains no folder row at any width, the count line reads correctly with and without a subtree, and the placeholder carries the count
- [ ] T028 [US1] Add `vault_1a_wide_1024x768_light.png`, `vault_1a_wide_1024x768_dark.png` and `vault_1a_wide_folder_selected_1024x768_light.png` to `test/goldens/vault_shell_test.dart` with an exact-inventory assertion, per the plan's golden inventory

**Checkpoint**: US1 is independently demonstrable at 1024 × 768.

---

## Phase 4: User Story 2 — The phone vault is a list, not a file browser (P1)

**Goal**: the 390 × 844 vault is the header, the search, the chips and the rows.

**Independent test**: copy a password at 390 × 844 without opening the record.

- [ ] T029 [US2] Build the phone screen header in `vault_shell.part.dart`: `Vault`, `<n> items · <database>.kdbx`, the filter affordance and the add affordance (FR-014, C-03-01)
- [ ] T030 [US2] Build the chip row in `vault_folders.part.dart` using `KvFilterChip`: `Folders` first, then `All`, then first-level folders only — deep nesting must never lengthen the row (FR-005)
- [ ] T031 [US2] Build the `Folders` sheet in `vault_folders.part.dart`: the same `KvFolderTree` in `filter` mode, the same expansion state as the desktop column, `Manage` at its head; choosing a folder filters, closes and becomes the active chip (FR-005a, FR-006a)
- [ ] T032 [US2] Add the one-tap password copy to the record row in `lib/features/password_manager/presentation/screens/vault/vault_entries_details.part.dart`, reusing the existing copy path and its existing confirmation string verbatim — the row keeps its health dot (FR-010, C-03-04, Constitution I)
- [ ] T033 [P] [US2] Extend `vault_records_list_test.dart`: the copy affordance copies without navigating, the confirmation string is the existing one byte for byte, and the health state is announced in words as well as colour (Constitution V)
- [ ] T034 [P] [US2] Extend `vault_folder_surface_test.dart`: the chip row carries first-level folders only for a deeply nested vault, the sheet and the column share one expansion state, and a deleted selected folder falls back to `All items` (spec edge case)
- [ ] T035 [US2] Add `vault_1a_phone_390x844_light.png`, `vault_1a_phone_390x844_dark.png` and `vault_1a_phone_folders_sheet_390x844_light.png` to the golden inventory

**Checkpoint**: US1 and US2 both demonstrable; the vault looks like model 1a.

---

## Phase 5: User Story 3 — Every action that exists today still has a home (P1)

**Goal**: `Manage folders` exists as one surface at every width, and nothing
that was reachable before this spec is unreachable after it.

**Independent test**: walk the inventory in `quickstart.md` before and after.

- [ ] T036 [US3] Add `ManageFoldersSurface` and `VaultDialogPresentation` to `lib/features/password_manager/presentation/navigation/vault_shell_router.dart`, with `presentationFor` returning the dialog when `layout.hasDetailPane` and the pushed route otherwise (contract `vault-surfaces.md`, research R4)
- [ ] T037 [US3] Host the dialog presentation in the router beside the existing route and sheet hosts, so `ManageFoldersSurface` participates in sessions, cancellation and results like every other surface (contract S3)
- [ ] T038 [US3] Create `lib/features/password_manager/presentation/screens/vault/vault_manage_folders.part.dart`: `KvFolderTree` in `manage` mode — always fully expanded, no subtitles — `New folder` in the header, and the per-row `•••` with `Rename · Move… · Delete` (FR-006, FR-006b)
- [ ] T039 [US3] Wire the three row actions to the events the folder tree rows dispatch today, reusing their existing confirmations and strings verbatim (FR-006d, Constitution VI and VII)
- [ ] T040 [US3] Rehome the actions displaced from the status card — sync now, lock, change database, database settings, recycle bin, duplicates — so each is reachable in no more interactions than today with byte-identical wording (FR-015)
- [ ] T041 [US3] Point the add affordance at record creation in the currently selected folder, absorbing today's `Add record` row action, and delete that row action (spec §Behaviour this spec deliberately changes)
- [ ] T042 [US3] Delete `_FolderAction.addSubfolder` and its call sites; the path becomes `New folder` then `Move…` (spec §Behaviour this spec deliberately changes)
- [ ] T043 [US3] Remove `ToggleVaultGroupExpanded` from `vault_event.dart` and `vault_bloc.dart` now that every caller uses `SetVaultFolderExpanded`, so one thing has one event (`data-model.md`)
- [ ] T044 [P] [US3] Write `test/features/password_manager/presentation/screens/vault/vault_manage_folders_test.dart`: the same surface at both widths, exactly one entry point per width (contract S4), the tree always fully expanded, and the `•••` recipe identical in both containers
- [ ] T045 [US3] Re-run `vault_action_inventory_test.dart` from T003 and make it green by rehoming, never by relaxing an assertion. The two spec-marked changes are the only permitted edits, and each carries a comment naming the spec section that authorises it
- [ ] T046 [US3] Add `manage_folders_dialog_1024x768_light.png`, `manage_folders_dialog_1024x768_dark.png`, `manage_folders_screen_390x844_light.png` and `manage_folders_row_menu_390x844_light.png` in `test/goldens/vault_folders_test.dart`

**Checkpoint**: the restyle has cost the user nothing.

---

## Phase 6: User Story 4 — The rail and tab bar say what they are (P2)

**Goal**: the chrome matches `ICONS.md`.

**Independent test**: compare the rail against the artboard and `ICONS.md`.

- [ ] T047 [P] [US4] Replace the rail's `AppGlyph.key` tile child in `vault_shell.part.dart` with the KeyVault mark artwork at 38 × 38 / r13, adding the asset to `pubspec.yaml` if it is not already declared (FR-016, C-SH-03)
- [ ] T048 [P] [US4] Correct `VaultDestination.glyph` in `vault_shell.part.dart`: Vault → `lock`, Sync → `refresh-cw`; Health and Settings are already right (FR-017, C-03-13, DQ-4)
- [ ] T049 [US4] Give the selected destination a filled tile in both `_VaultRail` and `_VaultTabBar`, keeping the existing `Semantics(selected:)` — the fill is in addition to it, never instead of it (FR-018, C-03-14, Constitution V)
- [ ] T050 [P] [US4] Write `test/features/password_manager/presentation/screens/vault/vault_chrome_test.dart`: the glyph asset name per destination, the mark present in the rail, the selected fill, and the selected state still announced
- [ ] T051 [US4] Add the `lock` row to `specs/_design/ICONS.md` and its `docs/` copy if the earlier edit has not already landed, and tick the corresponding audit findings

---

## Phase 7: User Story 5 — The user can choose the order (P3)

**Goal**: the orphaned sort becomes reachable.

**Independent test**: change the sort and watch the list re-order.

- [ ] T052 [US5] Add the sort control to the count line in `vault_entries.part.dart`, dispatching the existing `SetVaultSort` with the existing `VaultEntrySort` values and marking the active one. No new ordering (FR-009, research R2)
- [ ] T053 [P] [US5] Extend `vault_records_list_test.dart`: exactly three orders offered, the active one marked, and the choice surviving a folder change and a search
- [ ] T054 [US5] Add `vault_1a_sort_menu_1024x768_light.png` to the golden inventory

---

## Phase 8: Polish & cross-cutting

- [ ] T055 Re-record the goldens the change legitimately moves, then diff the actual churn against the plan's prediction. Any file from the "must not move" families that moved is investigated as a regression before the diff is accepted
- [ ] T056 [P] Verify the accessibility floor across the new surfaces: every text/background pairing ≥ 4.5:1, every focusable has its 2 px ring, every target ≥ 44 × 44, no state signalled by colour alone (Constitution V)
- [ ] T057 [P] Confirm no hard-coded hex, font family, radius or duration entered the new files, and that every metric traces to `PIXEL_SPEC` through a token (Constitution III)
- [ ] T058 Close the audit ledger: mark `C-SH-03` and `C-03-01`…`C-03-14` resolved in `specs/_design/CONFORMANCE_AUDIT.md`, each naming the task that closed it, and re-record any finding that turned out to be wrong rather than quietly dropping it (SC-001)
- [ ] T059 Run `fvm flutter analyze` and `fvm flutter test`, then `fvm flutter test test/goldens --test-randomize-ordering-seed=$RANDOM`, and report the counts against the T002 baseline (Constitution IX, SC-006)
- [ ] T060 Walk `quickstart.md` manually on macOS at ≥ 941, in the 704–940 band and at phone width, including the action-inventory walk
- [ ] T061 Tick every box in this file in the change that lands the work and run `PROJECT_NUMBER=2 tool/sync_spec_project.sh`, reporting the board state

---

## Dependencies

```
Phase 1  Setup
   ↓
Phase 2  Foundational  ← BLOCKING for every story
   ↓
   ├─ Phase 3  US1 (P1)  ─┐
   ├─ Phase 4  US2 (P1)  ─┤  US2 needs T030/T031 to consume the tree from T014,
   │                       │  and T032 is independent of both
   ├─ Phase 5  US3 (P1)  ─┤  needs US1's column (T018) for its entry point
   ├─ Phase 6  US4 (P2)  ─┤  fully independent of US1–US3
   └─ Phase 7  US5 (P3)  ─┘  needs T022's reserved slot
   ↓
Phase 8  Polish
```

US4 depends on nothing in this spec and can be done at any point after Phase 1.
US5 is the smallest and is the natural first thing to drop if scope must be cut.

## Parallel opportunities

- **Phase 2 characterisation**: T003, T004, T005, T006 — four different test
  files, no production code touched.
- **Phase 2 widgets**: T015 and T016 once T014 exists.
- **Phase 3**: T026 and T027 while the golden task T028 is written.
- **Phase 6**: T047, T048 and T050 are three separate concerns in one file plus
  one test; T049 must follow T048 so the fill is asserted against the right
  glyph.
- **Phase 8**: T056 and T057 are independent audits.

## Implementation strategy

**MVP**: Phase 1 + Phase 2 + Phase 3. That is a desktop vault that matches the
artboard, with every existing action still reachable through the surfaces US1
leaves in place — US3 has not moved them yet, so nothing is lost mid-flight.

**The one ordering rule that matters**: T003 must be written and green
**against unchanged code** before T021 deletes anything. Spec 018's most
expensive lesson was a test suite that passed against the unfixed code; a
characterisation test written after the change characterises the change.

**Incremental delivery**: US1 → US2 → US3 are each demonstrable on their own.
US4 can land first if a quick visible win is wanted; it touches one file.
