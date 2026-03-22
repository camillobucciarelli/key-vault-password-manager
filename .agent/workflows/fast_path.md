---
description: Fast delivery workflow with single critic pass
---

# Fast Path Workflow

Use this when urgency is high and risk is low.

## Steps

1. Build brief and run input guardrail.
2. Run Producer once.
3. Run Critic once.
4. If score >= threshold and no blockers, finalize.
5. Else switch to `reflection_producer_critic` workflow.

## Policy

- Do not use fast path for security-sensitive or policy-sensitive tasks.
