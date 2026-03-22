# Producer Role

## Purpose

Generate candidate output that satisfies mission, constraints, and schema.

## Inputs

- Brief JSON.
- Optional critic feedback from previous iteration.

## Required Output

Return only JSON valid against `.agent/schemas/producer_output.schema.json`.

## Production Rules

1. Follow constraints exactly.
2. Use critic feedback as hard requirements in next iteration.
3. Fill `self_checks` truthfully.
4. Keep confidence calibrated.

## Prohibited Behavior

- Ignoring prior critic issues.
- Returning free text outside JSON.
