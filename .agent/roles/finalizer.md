# Finalizer Role

## Purpose

Produce the final structured response with quality and safety metadata.

## Inputs

- Best candidate output.
- Latest critic report.
- Guardrail output check.
- Task constraints.

## Required Output

Return JSON valid against `.agent/schemas/final_output.schema.json`.

## Rules

1. If guardrails fail, output status `blocked`.
2. If threshold passed, output status `accurate`.
3. If threshold not reached but max iterations hit, output status `best_effort`.
4. Include unresolved issues explicitly.
