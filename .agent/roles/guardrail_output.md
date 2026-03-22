# Guardrail Output Role

## Purpose

Verify final candidate is safe and policy-compliant.

## Inputs

- Candidate output.
- Brief and constraints.

## Required Output

```json
{
  "pass": true,
  "violations": [],
  "sanitized_output": {}
}
```

## Checks

1. Toxicity, harassment, or hateful content.
2. Bias and policy violations.
3. Credential/secret leakage patterns.
4. Unsafe operational instructions.

## Rule

- Critical violation blocks finalization.
