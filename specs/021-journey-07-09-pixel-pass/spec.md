# 021 — Pixel pass on journeys 07–09

**Status**: Done — closed by the manual pass of 2026-08-31 (see `tasks.md`) · **Kind**: Conformance / Design fidelity
**Created**: 2026-08-29
**Depends on**: 019 (the shell chrome these screens sit inside)
**Source**: `specs/_design/CONFORMANCE_AUDIT.md` — proposed remediation table

## Closure

Journeys 07–09 were reviewed by hand on the running desktop build on
2026-08-31 and the drift found was fixed in the same day and shipped in
v0.4.0 (PR #180): the sync status hero was rebuilt on `surface` /
`surfaceNested` with a provider tile so more providers can be added, the Drive
file picker got the vault card hover/selection recipe with a contextual link
action, the local checksum is now real, and the conflict sheet became
pane-aware on desktop. No screenshot pass is planned; anything still off is a
bug report.

## Why this was a draft

Journeys 07, 08 and 09 have **not** been pixel-audited. The audit that produced
specs 019 and 020 is code-verified for journey 03 and the shell only; every
other journey was marked `[visual]` on purpose, because reading source and
guessing at pixels is how the drift being fixed here was introduced.

**What unblocks this spec**: screenshots of each screen — light and dark, phone
and desktop — compared against the artboards in the Claude Design project
(`5151eacb-bbf2-44aa-921c-6a0e2d231d12`).

## Scope

- **07** — Sync status and Drive connection
- **08** — Sync conflict resolution
- **09** — Import / export

## What is already known

Spec 019 changed these screens' surroundings, not their content: the rail and
tab bar glyphs, and the removal of the database status card from above the
records list. Their goldens moved for that reason alone. Any finding this spec
records is therefore about the screens themselves.

## Non-goals

Behaviour. This is a fidelity pass: if a screen is wrong in what it *does*, that
is a bug report or its own spec, not a line here.
