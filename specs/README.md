# KeyVault specs

Spec-kit style specifications for the **KeyVault restyle** (Organic design
system) plus the **two new features** the design package introduces.

Source of the design: Claude Design project
`5151eacb-bbf2-44aa-921c-6a0e2d231d12`, folder `design_handoff_keyvault_restyle/`.
Imported 2026-08-05.

## Layout

```
.specify/memory/constitution.md   non-negotiable rules
specs/_design/                    the design handoff, verbatim (numbers of record)
  HANDOFF.md                      journeys, tokens, behaviour, state
  PIXEL_SPEC.md                   every measurement, per surface
  ICONS.md                        app mark geometry + Lucide mapping
  tokens.css                      Organic handoff source; 001 records mandatory accessibility deviations
  keyvault-mark*.svg              vector masters of the new app mark
specs/NNN-slug/spec.md|plan.md|tasks.md
```

## Specs

| # | Spec | Kind | Depends on |
| --- | --- | --- | --- |
| 001 | [Organic design system](001-organic-design-system/spec.md) | Restyle foundation | — |
| 002 | [Navigation shell (model 1a)](002-navigation-shell/spec.md) | Restyle foundation | 001 |
| 003 | [Database selection & unlock](003-database-and-unlock/spec.md) | Restyle (journeys 01–02) | 001, 002 |
| 004 | [Entry, editor, generator](004-entry-editor-generator/spec.md) | Restyle (journeys 04–06) | 001, 002 |
| 005 | [Sync, health, import/export](005-sync-health-import/spec.md) | Restyle (journeys 07–09) | 001, 002 |
| 006 | [Security, autofill, extension](006-security-autofill-extension/spec.md) | Restyle (journeys 10–12) | 001, 002 |
| 007A | [App icon family — asset generation](007-app-icon-family/spec.md) | Restyle asset work | — |
| 007B | [App icon family — UI/badge integration](007-app-icon-family/spec.md) | Restyle integration | 001, 002, 007A |
| 008 | [Per-field sync conflict resolution](008-per-field-conflict-resolution/spec.md) | **New feature** | 001, 002, 005 |
| 009 | [In-page autofill overlay](009-in-page-autofill-overlay/spec.md) | **New feature** | 006 |
| 011 | [Master password session scope](011-master-password-session-scope/spec.md) | **Security fix** | 003, 006 |

Journey 03 (navigation models) resolved into spec 002; journey 14 (dark mode) is
not a separate spec — the dark token mapping lands in 001 and every screen spec
carries dark acceptance criteria.

## Suggested order

1. **007A** asset generation may run independently or alongside **001**. It
   produces reviewed assets only; no launcher, in-app or badge integration.
2. **001** then **002** establish tokens and shell. Constitution governance makes
   both prerequisites for every later UI integration, including **007B**.
3. **003 → 004 → 005 → 006** may then proceed; 004 is the highest-traffic surface.
4. **007B** follows 001, 002 and 007A. **008** follows 005; **009** follows 006.
5. **011** is a security fix, independent of the restyle sequence, and takes
   priority over new-feature work: it removes an unbounded plaintext lifetime
   that violates constitution principle I and blocks the accurate privacy claim
   required for store submission.

## Definition of done, every spec

- `flutter analyze` clean, targeted tests green, then `flutter test` green before
  commit.
- Exact named golden inventory in the spec is green. Responsive root layouts use
  390×844 and 1024×768, light and dark; explicitly listed state variants may use
  a representative axis with widget-test coverage for omitted axes.
- No hard-coded hex, font, radius or duration in migrated files. Compatibility
  aliases are allowed only for untouched call sites and are tracked to zero.
- Every text/background pairing declared by the spec passes ≥4.5:1 contrast;
  accessibility-approved handoff deviations are documented. Remaining
  accessibility floor from the constitution is met.
