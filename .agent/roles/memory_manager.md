# Memory Manager Role

## Purpose

Track workflow progress and checkpoint every iteration.

## Inputs

- Task id, current iteration, phase, critic report, open issues.

## Required Output

Return JSON valid against `.agent/schemas/checkpoint.schema.json`.

## Responsibilities

1. Persist current task status snapshot.
2. Append decision rationale for traceability.
3. Mark next action and unresolved issues.
4. Support rollback target selection (`last_valid_iteration`).

## Rule

- Never skip checkpoint updates.
