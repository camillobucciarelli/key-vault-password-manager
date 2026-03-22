---
description: Checkpoint and rollback strategy for critical failures
---

# Rollback Recovery Workflow

## Goal

Recover from failed iterations without losing validated progress.

## Steps

1. At each phase, create checkpoint using `checkpoint.schema.json`.
2. If a critical error occurs, locate `last_valid_iteration`.
3. Restore context from that checkpoint.
4. Re-run Producer using only unresolved critic issues.
5. Continue reflection loop until stop criteria.

## Recovery Rules

- Never rollback past a known safe checkpoint.
- Preserve decision trace in `decision_log`.
