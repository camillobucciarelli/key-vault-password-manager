# Data model: Desktop vault navigation and entry actions

**Phase 1** · spec 018 · 2026-08-28

This feature persists nothing. The "model" is the small set of **view-state**
values whose ownership was previously split and is now single. No KDBX field,
no domain entity and no BLoC state gains a member.

---

## E1 - `VaultLayoutClass` (new value type)

The one classification every navigation decision consults. Computed once by
`_VaultViewState` from the window width; passed down, never re-derived.

| Case | Width | Columns present |
|---|---|---|
| `narrowTabBar` | `< Breakpoints.mobile` (600) | list only; bottom tab bar; detail pushes |
| `narrowRail` | `600 .. 703` | icon rail + list; detail pushes |
| `wide` | `704 .. 940` | rail + list + detail pane |
| `wideWithFolders` | `>= 941` | rail + folders + list + detail pane |

**Derived constants** (live in `lib/core/responsive/breakpoints.dart`, each
written with its arithmetic):

```dart
// 72 (rail) + 330 (list) + 300 (detail min) + 2 dividers
static const double vaultDetailPane = 704;
// 72 + 236 (folders) + 330 + 300 + 3 dividers
static const double vaultFolderPane = 941;
// 72 + 330 + 300 + 290 (generator) + 3 dividers
static const double vaultGeneratorColumn = 995;
```

**Invariants**

- I1: exactly one case holds for any width.
- I2: `isWide` (`wide` or `wideWithFolders`) is the **only** predicate that may
  select pane over push. No `MediaQuery` read decides presentation.
- I3: the class is a pure function of width - no theme, platform or state input.

**Column widths** (FR-002b): rail 72, folders 236, list 330, detail flex min
300, generator 290, dividers 1.

---

## E2 - Selected record

**Owner**: `_VaultViewState._selectedEntryId` (`String?`).
**Previously**: `_EntriesCardState._selectedEntryId` - deleted by this change.

Holds an **id only**. Never a `VaultEntry`, never a secret (Constitution I).
The entry is resolved from `VaultBloc.state.allEntries` at the point of use.

### Lifecycle

| From | Event | To |
|---|---|---|
| `null` | user activates a row | `id`, detail session opened |
| `id` | user activates a different row | `id'`, previous session completed first |
| `id` | detail session finishes (back, escape, cancel, completion) | `null` |
| `id` | entry no longer in `allEntries` | `null`, session and children cancelled |
| `id` | entry filtered out of the visible list (search / folder change) | `null` (FR-014) |
| `id` | destination changes away from Vault | `null` |
| `id` | width class changes | **unchanged** - only the presentation changes (FR-015) |

**Invariants**

- I4: the highlighted row and the detail surface always read the same id -
  they cannot disagree, because there is one field (FR-003).
- I5: a non-null selection at a wide class implies exactly one live
  `EntrySurface` session; at a narrow class it implies exactly one pushed
  route.
- I6: selection survives a width-class change; it does not survive the entry
  disappearing.

---

## E3 - Record action

`_EntryAction` is unchanged as an enum (`edit`, `move`, `attachments`,
`delete`). What changes is its **invocation contract**.

| Aspect | Before | After |
|---|---|---|
| Target | a `VaultEntry` value captured at open time | the entry **id** |
| Entry read | the captured snapshot | re-read from `VaultBloc` at confirmation time |
| Liveness guard | `_EntriesCardState.mounted` | the surface's own context |
| Bloc handle | `this.context.read<VaultBloc>()` after the await | captured **before** the first await |
| Outcome | may be silently dropped | applied, or reported (FR-006) |

### Outcome states

```text
                 +--> cancelled  -> vault unchanged, selection kept
confirm dialog --+--> applied    -> event dispatched, selection kept
                 +--> failed     -> user informed (never silent)
```

`delete` additionally transitions E2 to `null` once the entry leaves
`allEntries` - via I6, not via a special case in the delete branch.

**Invariants**

- I7: no path exists from "user confirmed" to "nothing happened and nothing
  was said".
- I8: the values written are the entry's values at confirmation time, so two
  consecutive edits compose rather than the second reverting the first (D4).

---

## E4 - Detail session (existing, unchanged)

`VaultShellRouter`'s `_VaultOperationSession` already models this and is not
modified. Recorded here because E2's lifecycle is coupled to it.

- One `EntrySurface` per selected record.
- Nested surfaces (attachments, move target, confirmation, editor, generator)
  are **children**; `_finish` already cancels children when the parent ends,
  which is what makes FR-008's third scenario free.
- Dismissal is `VaultOperationScope.complete` / `requestCancel` -
  presentation-neutral. `Navigator.pop` is no longer called by detail code
  (FR-007).

---

## Relationships

```text
VaultLayoutClass ──selects──> presentation (push | pane)
        │                              │
        │                              v
        └──────────────────> VaultShellRouter session ──owns──> nested surfaces
                                       ^
                                       │ opened/cleared by
                                       │
              _VaultViewState._selectedEntryId ──highlights──> records list row
                                       │
                                       └──resolves──> VaultEntry (from VaultBloc)
                                                          │
                                                          v
                                                    record action
```

**No entity in this model is persisted, serialised, logged, or crosses a
platform channel.**
