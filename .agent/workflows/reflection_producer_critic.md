---
description: Reflection workflow with producer-critic loop and strict guardrails
---

# Reflection Producer-Critic Workflow

## Goal

Generate robust outputs in chat with low randomness and explicit validation.

## Steps

1. Build a strict brief with `Context Engineer` using `brief.schema.json`.
2. Run `Guardrail Input`; if fail, return `blocked`.
3. Run `Producer` to create `producer_output`.
4. Run `Critic` to create `critic_report`.
5. If verdict is `INACCURATE`, send `repair_instructions` to Producer and iterate.
6. Stop when score >= threshold and verdict is `ACCURATE`, or max iterations reached.
7. Run `Guardrail Output`; if fail, return `blocked`.
8. Run `Finalizer` to generate `final_output`.
9. Run `Memory Manager` to checkpoint final state.

## Defaults

- `max_iterations = 4`
- `critic_score_threshold = 0.85`
- `schema_retries_per_step = 2`

## Output Contract

Final response must conform to `.agent/schemas/final_output.schema.json`.
