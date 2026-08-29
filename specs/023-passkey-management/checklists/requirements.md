# Specification Quality Checklist: Passkey management

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-29
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [ ] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Three open [NEEDS CLARIFICATION] markers, all deliberate, none with a
  defensible default:
  - **FR-015** — user presence on every assertion vs. a recent-unlock window.
  - **FR-022** — where private key material lives when the app is not running;
    this decides whether a passkey sign-in works from a locked app at all.
  - **Deferred scope** — whether Android's Credential Manager belongs in 023 or
    in its own spec.
- Named platform APIs (KeePassXC field layout, Apple credential provider
  extension) appear only where they are the interoperability target or the
  existing asset being reused — they are product constraints, not implementation
  choices, and the requirements themselves stay behaviour-level.
- Items marked incomplete require spec updates before `/speckit-plan`.
