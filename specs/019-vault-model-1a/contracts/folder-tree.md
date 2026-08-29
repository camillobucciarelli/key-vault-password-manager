# Contract — `KvFolderTree`

One widget, three hosts. The contract exists so FR-006k ("one selected-row
style, one `•••` recipe") holds by construction instead of by three widgets
agreeing.

## Inputs

| Input | Meaning |
| --- | --- |
| `nodes` | the flattened `FolderNode` list from `data-model.md` |
| `selectedId` | the selected group id; the root group id renders `All items` as selected |
| `onSelect(String id)` | never null — `All items` reports the root group id (FR-002a). Emitted by the **row**. |
| `onToggleExpanded(String id, bool expanded)` | emitted by the **chevron only** |
| `mode` | `filter` or `manage` |
| `onRowAction(String id, FolderAction action)` | `manage` only; `null` in `filter` |

## Guarantees

- **G1** — In `filter` mode no row carries any action affordance (FR-006c).
- **G2** — In `manage` mode every row carries the same `•••` with exactly
  `Rename`, `Move…`, `Delete`, in that order, and the tree ignores
  `isExpanded`: it renders fully expanded (FR-006b).
- **G3** — A chevron is rendered only when `hasChildren`, and activating it
  calls `onToggleExpanded` and **never** `onSelect` (FR-006f).
- **G4** — Activating a row calls `onSelect` and **never** `onToggleExpanded`.
- **G5** — Indentation is one level per depth; nothing else encodes position,
  and `manage` mode adds no subtitle (FR-006b).
- **G6** — The selected row uses one style at every host: `accent-200` fill,
  `accent-800` semibold text, an inline folder glyph and no square icon tile.
- **G7** — Both targets are ≥ 44 × 44 and do not overlap (R5, Constitution V).
- **G8** — Every row exposes its selected state to assistive technology, and
  the selection is never signalled by colour alone.

## Non-goals

The tree does not fetch, does not know about the BLoC, and does not decide what
"selected" means for the records list. It renders `nodes` and reports.
