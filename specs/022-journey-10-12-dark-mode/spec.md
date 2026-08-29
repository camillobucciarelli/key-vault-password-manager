# 022 — Pixel pass on journeys 10–12 and dark mode

**Status**: Draft — blocked on screenshots · **Kind**: Conformance / Design fidelity
**Created**: 2026-08-29
**Depends on**: 019 (the shell chrome these screens sit inside)
**Source**: `specs/_design/CONFORMANCE_AUDIT.md` — proposed remediation table

## Why this is a draft

Journeys 10, 11, 12 and 14 have **not** been pixel-audited, for the same reason
as 021: the audit is code-verified for journey 03 and the shell, and everything
else was marked `[visual]` rather than guessed at.

**What unblocks this spec**: screenshots of each screen — light and dark, phone
and desktop.

## Scope

- **10** — Security and master password
- **11** — Autofill (Apple, Android)
- **12** — Desktop browser extension
- **14** — Whatever the catalogue's last journey covers (confirm against
  `00 Catalogo & Piano` before starting; the audit lists it among the
  unaudited but never names it)

### Dark mode as its own axis

Every journey's dark variant is collected here rather than spread across 020,
021 and 022. Dark is not "light with swapped tokens" in this design: the
surface/ground inversion changes which elevation reads as a card, and the
audit never checked a single dark artboard against a single dark screen.

If the dark pass turns out to be large, split it into its own spec at that
point — do not let it ride along half-done.

## Non-goals

Behaviour, and any journey covered by 020 or 021.
