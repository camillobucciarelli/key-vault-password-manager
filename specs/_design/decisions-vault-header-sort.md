# Decision — OQ-1: header button in the phone vault (journey 03, model 1a / artboards 1a, 2b)

decided: 2026-08-29 · unblocks `specs/019`

## Answer: hypothesis 1

The button is the **phone sort control** — the mobile equivalent of the desktop
list-header row `128 items · Username ↑`. It is not a folder filter (folders
live in the Folders chip per DQ-6/DQ-7 — no second affordance), and it is not
advanced search (there is one search and it already covers all fields).

## Sheet contents (exact)

A bottom sheet titled **Sort** with a single radio group of the three values
that exist in code (`VaultEntrySort` in `vault_state.dart:15`):

1. Title A→Z (`titleAsc`)
2. Title Z→A (`titleDesc`)
3. Username A→Z (`usernameAsc`) — **default** (state default in code)

Nothing else. Selection applies immediately and dismisses the sheet; the
choice persists like the desktop control does (same `SetVaultSort` event).

## What is NOT in the sheet

- **Health filter** (by password-strength dot / stale password / duplicates):
  the data exists in code, but a filter UI over it is a **new feature** —
  excluded by FR-020 / catalogue principle "zero new features". Logged as a
  separate proposal to evaluate on its own, not part of spec 019.
- Folder filtering — already the Folders chip.
- Any new sort keys (URL, date, health). Three values only.

## Icon

Content is sort-only, so the glyph changes from list-filter to Lucide
**arrow-up-down** (stroke 2.75 per the system). Applied to artboards 1a and 2b
in `03 Vault - modelli di navigazione.dc.html` on 2026-08-29. Add to ICONS.md:
`arrow-up-down` → vault sort (phone header).

## Placement

Unchanged: header right, left of the `+` button, 44px hit target.
