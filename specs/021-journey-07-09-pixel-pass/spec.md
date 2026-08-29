# 021 — Pixel pass on journeys 07–09

**Status**: Draft — blocked on screenshots · **Kind**: Conformance / Design fidelity
**Created**: 2026-08-29
**Depends on**: 019 (the shell chrome these screens sit inside)
**Source**: `specs/_design/CONFORMANCE_AUDIT.md` — proposed remediation table

## Why this is a draft

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
