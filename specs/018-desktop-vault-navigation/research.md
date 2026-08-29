# Research: Desktop vault navigation and entry actions

**Phase 0** · spec 018 · 2026-08-28

No `NEEDS CLARIFICATION` entered the Technical Context. Every question was
either answered by the spec's clarify pass, settled by the 2026-08-28 design
decision, or resolved by reading the code directly. This file records what was
read and what was concluded, so the plan's claims are traceable.

---

## R1 - Where does the wide-window detail actually come from?

**Read**: `vault_entries.part.dart:598-650`, `vault_shell.part.dart:940-985`,
`vault_shell_router.dart:336-352`.

**Finding**: two independent mechanisms, both live.

1. `_EntriesCardState` runs its own `LayoutBuilder` and sets
   `showInlineDetail = constraints.maxWidth >= Breakpoints.mobile`, measured on
   **its own column**, not the window. When true it renders
   `Row(list | _EntryDetailPanel)` from a private `_selectedEntryId`.
2. `_VaultNavigationLayout._railBody` reserves a detail slot showing
   `activePane` (published by `VaultShellRouter`) or `_EntryDetailEmptyState`.

**Decision**: keep the router, delete the inline split.

**Rationale**: the router already owns nested-surface stacks, parent/child
cancellation, discard guards and the push/sheet/pane switch. The inline split
owns none of them, which is exactly why D6 and D8 appear only on the wide path.
Keeping both would mean reimplementing four mechanisms twice.

**Alternatives considered**: keep the inline split and stop routing
`EntrySurface` (rejected - the router loses dismissal and nesting ownership,
and mobile push would need a third path); keep both with a documented boundary
(rejected - that is the present failure mode, restated).

---

## R2 - Why do the width rules disagree?

**Read**: `breakpoints.dart`, `vault_shell.part.dart:3-8, 72-90, 940-985`,
`vault_shell_router.dart:336`.

**Finding**: three different measurements against four different numbers.

| Site | Measures | Compares against |
|---|---|---|
| `presentationFor` | `MediaQuery.sizeOf(context).width` | hard-coded `600` |
| `_VaultNavigationLayout` | shell body `constraints.maxWidth` | `Breakpoints.mobile`, bare `708`, `Breakpoints.tablet` |
| `_EntriesCardState` | the entries card's **own** constraints | `Breakpoints.mobile` |
| `_VaultLayoutSpec` | shell body width | `Breakpoints.mobile`, `tabletMax`, `compactPhone` |

The `708` is undocumented. It is numerically `76 + 330 + 300 + 2`, i.e. the
width at which the old (rail 76) columns first fit - correct arithmetic, no
stated derivation.

**Decision**: one `VaultLayoutClass`, computed once by the shell from the
window width, passed down. `presentationFor` takes it as a parameter and stops
reading `MediaQuery`.

**Rationale**: any widget that can measure its own constraints can reach a
different answer; that capability *is* the defect. Removing it makes FR-002
testable as "no descendant computes a presentation".

---

## R3 - Which column widths are normative?

**Read**: live Claude Design project `5151eacb-…` via the DesignSync MCP
(`03`, `04-06`, `PIXEL_SPEC.md`), verified byte-identical to the repo copies
(md5 `cc9200f7…`, `1029a46d…`).

**Finding**: the artboards disagreed at the same 1024x768 size, and the
disagreement could not be averaged - `76 + 236 + 330 + 290 + 4 = 936` leaves an
88px editor.

**Decision** (design, 2026-08-28): model 1a normative; single values rail 72,
folders 236, list 330, detail flex min 300, generator 290; folder column
conditional on width. Recorded in spec.md "Design decisions".

**Derived widths, verified**:

```
folder-collapse      72 + 236 + 330 + 300 + 3 = 941
pushed-detail        72       + 330 + 300 + 2 = 704
generator-as-column  72       + 330 + 300 + 290 + 3 = 995
folders + generator  72 + 236 + 330 + 290 + 300 + 4 = 1232
detail at 1024       1024 - 72 - 236 - 330 - 3 = 383   (>= 300 OK)
editor at 1024 + gen 1024 - 72 - 330 - 290 - 3 = 329   (>= 300 OK)
```

All six re-checked by hand before adoption.

**Consequence**: the code's `708` is superseded by `704`. It was near-right for
the wrong reason (it used the now-corrected rail width 76).

---

## R4 - Why do record actions silently do nothing?

**Read**: `vault_entries.part.dart:210-256` (`_handleEntryAction`), `257-286`
(`_openEntry`).

**Finding**: two distinct bugs sharing one function.

1. **Stale entry (D4)**: `_handleEntryAction(context, entry, action)` takes a
   `VaultEntry` value. The pushed path deliberately re-reads the current entry
   from the bloc before calling it (with a comment explaining the deactivated
   ancestor problem); the inline path passes the build-time `selected` snapshot.
   Edit therefore writes fields captured before a previous edit landed.
2. **Dropped action (D5)**: every branch guards `if (… && mounted)` where
   `mounted` is `_EntriesCardState.mounted`, then dispatches through
   `this.context.read<VaultBloc>()`. When the action was started from a pushed
   surface and the entries list rebuilt or unmounted underneath, the guard is
   false: the dialog was confirmed and the event is never dispatched. No error,
   no message.

**Decision**: take an entry **id**; re-read from the bloc at confirmation time;
capture the bloc before the first `await`; guard on the surface context.

**Rationale**: the id is the only stable handle. Capturing the bloc before the
await removes the dependency on any widget still being mounted afterwards - the
bloc outlives every surface in the stack.

---

## R5 - Why does a deleted record leave a dead pane?

**Read**: `vault_entry_detail.part.dart:21-35`.

**Finding**: when the entry disappears, `_EntryDetailsPage` schedules
`Navigator.pop(context)` guarded by `Navigator.canPop(context)`. That is
correct only for `VaultRoutePresentation`. Under `VaultPanePresentation` no
route was pushed - `canPop` refers to an unrelated route, so the pane is either
left in place or an unrelated route is popped.

**Decision**: complete the session through `VaultOperationScope.of(context)`.

**Rationale**: `_buildScoped` wraps every session in a `VaultOperationScope`
regardless of presentation, and `_finish` already cancels child sessions - so
completing the scope dismisses the detail *and* any surface stacked on it,
satisfying FR-008's third scenario without extra code.

---

## R6 - Where does the editor go on a wide window?

**Read**: `vault_entry_editor.part.dart:18-40`, design `04-06` artboards.

**Finding**: `_showEntryDialog` opens an `EntrySurface`, which at wide widths
becomes a pane - the same slot the record's detail occupies. The editor
therefore replaces the record, and on completion the slot returns to the empty
state.

The design's editor artboard shows rail 72 | list 352 (dimmed) | editor flex |
generator 290, i.e. the editor **does** belong in that slot; what is missing is
the record's identity in the header and the return to the record afterwards.

**Decision**: keep the slot, add the record title to the editor header, keep
the selection alive during the edit, restore the record's detail on completion.

**Rejected from the design**: the 50% dimming of the records list. A dimmed
interactive column fails the contrast floor and misrepresents itself as
inactive (Constitution V). The design confirmed on 2026-08-28 that the dimming
is a drawing device and is not normative.

---

## R7 - Which goldens move?

**Read**: `test/goldens/` listing, `vault_shell_test.dart`,
`vault_shell.part.dart:947` (`railWidth`).

**Finding**: the vault rail is 76 only when the vault destination is selected
(`selectedDestination == VaultDestination.vault ? 76.0 : 72.0`). Correcting it
to a flat 72 therefore moves the vault goldens and leaves `health_`,
`settings_`, `sync_success_` and the non-vault 1024 goldens untouched.

**Decision**: five 1024 goldens re-recorded, six added, every 390x844 golden
frozen. The `editor_generator_sheet_1024x768_light` case is renamed, because at
1024 >= 995 the generator is now a column and the old name asserts the wrong
thing.

**Verification requirement**: diff the golden file list before and after rather
than trusting this analysis (recorded as a risk in plan.md).
