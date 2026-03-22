# Wave 9 Staging Plan

This plan stages only database-refactor files and keeps unrelated workspace
changes out of the commit.

## 1) Stage refactor paths

```bash
git add "docs/database_flows_refactor.md" "docs/refactor_workspace_hygiene.md" "docs/refactor_wave9_staging_plan.md" "lib/features/password_manager" "test/features/password_manager"
```

## 2) Unstage unrelated paths (if accidentally included)

```bash
git restore --staged ".agent" ".lh" ".github" ".gitignore"
```

## 3) Verify staged scope

```bash
git diff --cached --name-only
```

Expected: only `docs/` + `lib/features/password_manager/` +
`test/features/password_manager/` refactor files.

## 4) Final local quality gate before commit

```bash
flutter analyze
flutter test
```
