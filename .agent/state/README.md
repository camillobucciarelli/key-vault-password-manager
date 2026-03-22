# Runtime State

This folder stores runtime memory artifacts for chat-native reflection workflows.

## Runtime files

- `current_task.json`: latest high-level task status.
- `checkpoints/<task_id>/iter_<n>.json`: per-iteration checkpoints.
- `decision_log.jsonl`: append-only decision trace.

## Notes

- Runtime artifacts should not be committed.
- Keep this README tracked as documentation.
