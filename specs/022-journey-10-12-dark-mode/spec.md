# 022 — Dark mode verification

**Status**: Done — 2026-08-31, every journey rendered in dark and reviewed; one finding (F-001) fixed · **Kind**: Conformance / Design fidelity
**Created**: 2026-08-29 · **Rescoped**: 2026-08-31
**Depends on**: 019 (the shell chrome these screens sit inside)
**Source**: `specs/_design/CONFORMANCE_AUDIT.md` — proposed remediation table

## What can be verified today

No dark artboard has ever been compared against a dark screen. Two things
exist already and make a pass possible without new screenshots:

- the dark token mapping (`HANDOFF.md` §Dark theme) — already pinned by
  `test/core/theme/app_theme_test.dart` (semantic roles + contrast);
- the `14 Dark mode` artboard with six key screens: vault list, entry detail
  with reveal + TOTP, health, field diff, settings with the theme selector,
  extension popup.

Everything else is checked against the handoff's dark rule: surfaces move up
one ramp step, tinted backgrounds go to the `800` step with text at `100–200`,
pastel accents identical to light, shadow `0 12px 32px rgba(0,0,0,.5)`.

## Scope

Dark mode only. The pixel pass on journeys 10, 11, 12 and 14 that this spec
originally carried is dropped: those screens stay as they are (decision of
2026-08-31).

### Dark mode as its own axis

Every journey's dark variant is collected here. Dark is not "light with
swapped tokens" in this design: the surface/ground inversion changes which
elevation reads as a card, and the audit never checked a single dark artboard
against a single dark screen.

## Non-goals

Behaviour, and light-mode fidelity of any journey.
