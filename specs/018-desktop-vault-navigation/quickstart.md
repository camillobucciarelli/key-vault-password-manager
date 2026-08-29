# Quickstart: validating spec 018

**Phase 1** · spec 018 · 2026-08-28

Worktree: `/Users/cbucciarelli/Documents/personal-projects/password-manager-018-desktop-nav`
Branch: `fix/desktop-vault-navigation`

## Prerequisites

```bash
cd /Users/cbucciarelli/Documents/personal-projects/password-manager-018-desktop-nav
fvm flutter --version     # must be 3.47.1 - pinned in .fvmrc
fvm flutter pub get
```

## Run the app on a resizable window

```bash
fvm flutter run -d macos --dart-define-from-file=.env.dart.define.json
```

The OAuth ids are only needed for Drive sync; the navigation work does not
touch it. See `.env.dart.define.example.json`.

## The width bands, by hand

Resize the window and check the strip at each band:

| Width | Expect |
|---|---|
| 590 | bottom tab bar, list fills width, tapping a record pushes its detail |
| 650 | icon rail instead of the tab bar, still pushes |
| 750 | rail + list + detail pane; clicking a record fills the pane and highlights the row |
| 1000 | folder column appears (it starts at 941) |
| 1024 | opening the generator inside the editor gives a **column**, not a sheet |
| 980 | opening the generator gives a **sheet** (below 995) |

## The defects, reproduced then fixed

Each of these fails on `main` and must pass here.

1. **D4 - stale write.** Open a record on a wide window. Edit the title, save.
   Immediately edit the username, save. Both changes must be present.
2. **D5 - dropped action.** Open a record's detail. Type in the search box so
   the list rebuilds. Now run Delete from the detail and confirm. The record
   must actually be deleted.
3. **D6 - dead pane.** Open a record's detail on a wide window, delete it. The
   pane must return to the empty state with no row highlighted.
4. **D7 - editor place.** Open a record, edit it, save. You must land back on
   that record's detail, not an empty pane. The record's title must be visible
   in the editor header throughout.
5. **D3 - highlight.** At 1024, the record shown in the pane must have its row
   highlighted in the list.
6. **D1 - one detail.** At every width from 600 to 1400, exactly one detail
   surface is visible.

## Automated verification

```bash
# the full gate, in the order the constitution requires
fvm flutter analyze
fvm flutter test

# order-independence (repo rule: goldens are only checked locally)
fvm flutter test test/goldens --test-randomize-ordering-seed=$RANDOM
```

## The mobile regression check (US5)

The most important check in this spec. It is not "the suite passed" - it is
"no mobile golden moved":

```bash
git status --porcelain test/goldens/ | grep 390x844   # must print NOTHING
```

Any 390x844 golden appearing as modified, added or deleted is a **failure of
US5**, not a golden to re-record.

## Expected golden changes

Re-recorded (allowed, all 1024):

```text
vault_shell_1024x768_light.png
vault_shell_1024x768_dark.png
entry_detail_hidden_1024x768_light.png
editor_new_item_1024x768_light.png
editor_generator_sheet_1024x768_light.png   -> renamed to *_column_*
```

Added:

```text
vault_wide_record_selected_1024x768_{light,dark}.png
vault_wide_empty_detail_1024x768_{light,dark}.png
vault_wide_editor_in_pane_1024x768_{light,dark}.png
```

Anything else that moves is unplanned - investigate before accepting it.

## Regenerating goldens

```bash
fvm flutter test test/goldens --update-goldens
git status --porcelain test/goldens/      # review EVERY line against the list above
```
