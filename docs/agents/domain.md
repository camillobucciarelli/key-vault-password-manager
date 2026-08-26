# Domain Docs

How engineering skills consume this repository's domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repository root.
- Relevant ADRs under `docs/adr/`.

If these files don't exist, proceed silently. `/domain-modeling`, `/grill-with-docs`, and `/improve-codebase-architecture` create them lazily when terms or decisions are resolved.

## Layout

This is a single-context repository:

```text
/
├── CONTEXT.md
└── docs/
    └── adr/
```

## Use glossary vocabulary

When output names a domain concept, use the term defined in `CONTEXT.md`. Avoid synonyms the glossary rejects.

A missing concept may indicate invented language or a genuine gap for `/domain-modeling`.

## Flag ADR conflicts

Surface conflicts with existing ADRs explicitly rather than silently overriding them:

> Contradicts ADR-0007, but worth reopening because...
