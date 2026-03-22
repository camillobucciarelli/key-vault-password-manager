---
description: Safety-focused workflow with strict blocking rules
---

# Safety Hardening Workflow

## When to use

- User asks for high assurance.
- Task touches credentials, auth, or policy-sensitive content.

## Steps

1. Apply strict `Guardrail Input` with zero tolerance for jailbreak prompts.
2. Force Producer to include explicit safety self-checks.
3. Critic must add blockers for any unsafe instruction.
4. Apply strict `Guardrail Output` and block on any critical violation.
5. Finalizer must include safety violation list even when empty.

## Result

Only `accurate` or `blocked` statuses are allowed by default.
