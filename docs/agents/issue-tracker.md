# Issue Tracker: GitHub

This repository uses GitHub Issues through the `gh` CLI. It has two distinct issue surfaces.

## Ordinary requests

Bugs, enhancements, triage work, and standalone implementation tickets are ordinary GitHub issues.

- Create: `gh issue create --title "..." --body "..."`
- Read: `gh issue view <number> --comments`
- List: `gh issue list --state open`
- Comment: `gh issue comment <number> --body "..."`
- Label: `gh issue edit <number> --add-label "..."`
- Close: `gh issue close <number> --comment "..."`

Infer the repository from `git remote -v`.

Ordinary issues are not added to Project #2 unless the user explicitly requests it.

## Roadmap specs

Issues labelled `spec` are generated mirrors of repository files, not editable planning records.

Source of truth:

- `specs/NNN-slug/spec.md` defines identity and title.
- `specs/NNN-slug/tasks.md` defines checklist and completion.
- `specs/README.md` indexes specs.
- `tool/sync_spec_project.sh` updates generated issues and Project #2.

Never edit a generated spec issue body, state, title, or Project status manually. Change repository files, then run:

`PROJECT_NUMBER=2 tool/sync_spec_project.sh`

The workflow `.github/workflows/spec-project-sync.yml` also runs after relevant pushes to `main` and pull-request lifecycle changes.

## Skill routing

- `/to-spec`: create the next `specs/NNN-slug/spec.md`, update `specs/README.md`, then run the spec sync. Do not create the generated issue directly or apply triage labels to it.
- `/to-tickets` for a roadmap spec: write approved tasks into that spec's `tasks.md` using column-zero `- [ ]` rows, then run the spec sync. Do not create one GitHub issue per task.
- `/to-tickets` for ordinary work: create ordinary GitHub issues with native dependency links where available.
- `/triage`: operate on ordinary issues only. Ignore issues carrying the `spec` label.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Bare issue references

GitHub shares one number space across issues and pull requests. Resolve `#42` with `gh pr view 42`, then fall back to `gh issue view 42`.
