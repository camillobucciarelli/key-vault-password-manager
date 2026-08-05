# 008 — Feasibility report

**Report task**: T008  
**Current status**: Template only; all executable evidence `not-run`  
**Safety rule**: `not-run`, `failed` or `disabled` never enables feature

This file is authoritative Gate 0/Gate 1 record. Update rows with command, commit,
runtime and artifact evidence. Never convert assumption into `passed`.

## Status vocabulary

| Status | Meaning | Feature flag |
| --- | --- | --- |
| `not-run` | Harness/test not executed on named target | disabled |
| `passed` | Named target artifact satisfies schema and assertions | may enable that target only |
| `failed` | Harness ran and any required assertion failed | disabled |
| `disabled` | Target intentionally unsupported or blocked | disabled |

## Gate 0 summary

| Capability | Status | Evidence/artifact | Blocking note |
| --- | --- | --- | --- |
| KDBX 3 semantic round-trip | `not-run` | — | T001/T002 |
| KDBX 4 semantic round-trip | `not-run` | — | T001/T002 |
| Password+key-file reopen | `not-run` | — | T002 |
| Full-fidelity one-sided import/mutation | `not-run` | — | T003 |
| Tombstone inspect/re-emit without `KdbxFile.merge` | `not-run` | — | T004 |
| Root UUID lineage check | `not-run` | — | T004 |
| UUID integrity validation | `not-run` | — | duplicate entry/group, group-entry collision, nil, cross-side kind mismatch |
| Drive server-enforced conditional update | `not-run` | — | T005 |
| Ambiguous transport outcome classification | `not-run` | — | T005 |
| Writer/path inventory reconciled | `not-run` | — | T007 |
| Path identity/alias design reviewed | `not-run` | — | T007 |
| Platform artifact schema recorded | `passed` | schema below | Schema only; no platform evidence |

Gate 0 may close when T001–T008 evidence is complete and every unresolved target
platform remains disabled. Platform enablement waits for Gate 1 artifact.

## KDBX support matrix

Populate one row per installed-library-supported construct.

| Construct | Read | Import/copy | Mutate | Write/reopen | Semantic verify | Unsupported detector | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| root/group/entry UUID + hierarchy/moves | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | — |
| recycle bin + tombstones | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | — |
| entry history/timestamps | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | — |
| standard/custom strings + protection/presence | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | — |
| attachments bytes/reference/protection | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | — |
| custom data/icons/references | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | — |
| metadata/settings/header/KDF/cipher | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | `not-run` | — |

Required UUID evidence includes globally unique, non-nil live UUIDs per side and
object-kind match across sides. Separate failures: duplicate entry, duplicate
group, group-entry collision, nil UUID and cross-side group/entry mismatch.

## Drive conditional/recovery evidence

| Item | Recorded value/status |
| --- | --- |
| Concurrency token selected | `not-run` |
| Metadata fields/headers | `not-run` |
| Conditional rejection proven not applied | `not-run` |
| Timeout-after-dispatch classified ambiguous | `not-run` |
| Persisted `localCommittedChecksum` recovery guard | `not-run` |
| Restart local mismatch returns `staleRecoveryLocal` before remote call/mutation | `not-run` |
| Matching-local remote triage: merged/old/third state | `not-run` |
| Evidence command/artifact | — |

## Writer inventory evidence

Baseline inventory is `plan.md` section “Complete database/path writer inventory”.
T007 records source scan command/output and reconciles every write/rename/copy/
delete site.

| Check | Status | Evidence |
| --- | --- | --- |
| Vault KDBX mutators + credential rollback covered | `not-run` | — |
| Sync replacement/backup covered | `not-run` | — |
| Import/stage/replace/create/rollback covered | `not-run` | — |
| Settings/credential/database rename covered | `not-run` | — |
| Database create/delete/export covered | `not-run` | — |
| Presentation direct database writes removed/forbidden | `not-run` | — |
| Alias and deterministic multi-path lock tests enumerated | `not-run` | — |

## Platform artifact schema

Each Gate 1 artifact is target-generated JSON plus raw harness log. Required JSON
fields:

```json
{
  "schemaVersion": 1,
  "platform": "android|ios|macos|windows|linux",
  "osVersion": "...",
  "deviceOrRunner": "...",
  "filesystem": "...",
  "flutterVersion": "...",
  "dartVersion": "...",
  "commit": "...",
  "command": "...",
  "startedAtUtc": "...",
  "completedAtUtc": "...",
  "status": "passed|failed",
  "flushSupported": true,
  "directorySyncSupported": true,
  "atomicReplaceOverExisting": true,
  "backupNoOverwrite": true,
  "cases": [
    {
      "name": "...",
      "injectedFailurePhase": "...",
      "oldChecksum": "...",
      "candidateChecksum": "...",
      "finalChecksum": "...",
      "backupChecksum": "...",
      "targetState": "old|new",
      "passed": true
    }
  ],
  "logPath": "..."
}
```

Required cases: backup same-timestamp/preexisting collision, backup create/write/
flush/verify failure, target short-write/flush/rename failure, interruption before
replace, interruption after replace dispatch and no delete-first gap.

## Platform evidence matrix

Gate 0 initializes rows. Gate 1 T111 updates status/artifact. One row never
qualifies another target.

| Platform | Status | Feature enabled | Required artifact | Command/runtime |
| --- | --- | --- | --- | --- |
| Android | `not-run` | no | `build/safety-evidence/android/safe-vault-writer.json` + log | Android app storage on named device/emulator |
| iOS | `not-run` | no | `build/safety-evidence/ios/safe-vault-writer.json` + simulator/device logs | iOS simulator plus release-target physical evidence before release |
| macOS | `not-run` | no | `build/safety-evidence/macos/safe-vault-writer.json` + log | macOS app sandbox/runtime |
| Windows | `not-run` | no | `build/safety-evidence/windows/safe-vault-writer.json` + log | native Windows runner/filesystem |
| Linux | `not-run` | no | `build/safety-evidence/linux/safe-vault-writer.json` + log | native package runner/filesystem |

## Model corrections from spike

Populate before T201:

- chosen full-fidelity adapter mechanism: `not-run`;
- unsupported KDBX constructs/detection: `not-run`;
- chosen Drive token: `not-run`;
- platform path identity/global-lock fallback: `not-run`;
- domain model corrections: `not-run`.

## Sign-off

| Gate | Status | Reviewer | Date | Notes |
| --- | --- | --- | --- | --- |
| Gate 0 T001–T008 | `not-run` | — | — | Domain freeze forbidden |
| Gate 1 writer/mutex/platform evidence | `not-run` | — | — | All platforms disabled |
