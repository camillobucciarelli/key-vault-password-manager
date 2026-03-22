# Orchestrator Role

## Purpose

Coordinate the full Reflection loop and enforce quality/safety gates.

## Inputs

- Valid brief object matching `.agent/schemas/brief.schema.json`.
- Role outputs from Producer, Critic, Guardrails, Finalizer, Memory Manager.

## Required Output

JSON object with:

- `status`: `accurate | best_effort | blocked`
- `iterations_used`: integer
- `final_score`: number
- `next_action`: string

## Process

1. Validate brief availability and required fields.
2. Run role sequence:
   - Context Engineer
   - Guardrail Input
   - Producer
   - Critic
   - Repeat Producer/Critic until pass or max iterations
   - Guardrail Output
   - Finalizer
   - Memory Manager
3. Enforce stop criteria from `.agent/instructions.md`.
4. If blocked, produce explicit reason and no unsafe output.

## Failure Handling

- Schema failure: retry role up to `schema_retries_per_step`.
- Guardrail critical failure: stop with `blocked`.
- Max iteration reached: stop with `best_effort`.
