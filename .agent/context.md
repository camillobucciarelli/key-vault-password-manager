# Context

This is a Flutter Password Manager application.

- Uses `kdbx` for secure local database parsing and writing.
- Strict Clean Architecture (Data, Domain, Presentation).
- State management via `flutter_bloc`.
- Target platforms: Android, iOS, Web, macOS, Windows, Linux.

## Context Staging Area (for OpenCode chat)

Use this structure before starting a task. The Context Engineer must populate it.

```json
{
  "task_id": "string-uuid",
  "mission": "what to accomplish",
  "constraints": {
    "time_budget_s": 900,
    "style": "concise",
    "safety_level": "strict",
    "max_iterations": 4,
    "critic_score_threshold": 0.85
  },
  "smart_goals": [
    {
      "id": "G1",
      "specific": "Specific expected result",
      "metric": "How it is measured",
      "target": "Expected threshold",
      "realistic": true,
      "deadline": "ISO-8601 date or milestone"
    }
  ],
  "expected_output_schema": "final_output.schema.json",
  "context": {
    "inputs": ["User prompt", "Relevant file paths"],
    "artifacts": ["Existing docs", "Prior decisions"],
    "history_summary": "Where the workflow currently is"
  }
}
```

## Definition of Done

1. Producer output and Critic report both conform to schemas.
2. Critic verdict is `ACCURATE` with score >= threshold, or fallback is explicit.
3. Input/output guardrails pass.
4. Memory checkpoint is updated with final status.
