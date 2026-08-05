# 005 — Plan

## Approach

Sync and Health are new destinations (shell from spec 002); their content moves
out of dialogs. Health needs one genuinely new piece of domain logic — the score
and its five categories — which goes in a domain service, not a BLoC.

Everything else is a re-layout of existing widgets against existing state:
`VaultState` already carries sync status/error/last sync, remote Drive files,
duplicate groups and recycle-bin entries.

## Files

### New

| Path | Contents |
| --- | --- |
| `.../domain/services/vault_health_service.dart` | five categories + deterministic score |
| `.../domain/models/vault_health_report.dart` | `VaultHealthReport { score, categories }` |
| `.../screens/vault/vault_health.part.dart` | FR-4 destination |
| `.../screens/vault/vault_backups.part.dart` | FR-8 |
| `.../presentation/widgets/sync/sync_status_hero.dart` | FR-1, one widget, six states |
| `.../presentation/widgets/sync/remote_file_row.dart` | FR-2 |
| `test/features/.../domain/services/vault_health_service_test.dart` | determinism + category counts |
| `test/features/.../screens/sync_status_test.dart` | enum coverage |
| `test/goldens/sync_*.png`, `health_*.png`, `dup_*.png`, `bin_*.png`, `csv_*.png` | 17 screens |

### Modified

| Path | Change |
| --- | --- |
| `.../screens/vault/vault_sync.part.dart` (created in 002) | hero states, remote picker, conflict sheet |
| `.../screens/vault/vault_duplicates.part.dart` | group cards + merge preview sheet on the kit |
| `.../screens/vault/vault_recycle_bin.part.dart` | rows + overflow + empty state |
| `.../screens/vault/vault_shared.part.dart` | CSV import preview + outcome |
| `.../data/services/vault_csv_import_service.dart` | expose the per-row skip reason it already computes |
| `.../presentation/bloc/vault/*` | add `healthReport` to `VaultState` (computed on unlock and after writes) |

## Health score

```
categories = [weak, reused, old, duplicates, unmatchable]
score = round(100 * (1 - Σ(weight_i * min(count_i, total) / total)))
weights: weak .35, reused .25, old .15, duplicates .15, unmatchable .10
```

Deterministic, no randomness, no clock beyond `lastPasswordChangedAt`
comparisons (which take an injected `now` so tests are stable). Computed on the
already-decrypted in-memory entry list — nothing is re-read from disk.

## Sequencing

```
T1 health service ── T2 health destination
T3 sync hero (6 states) ── T4 remote picker ── T5 conflict sheet
T6 duplicates ── T7 merge preview
T8 recycle bin
T9 CSV preview ── T10 CSV outcome (skip reasons) ── T11 backups
T12 tests ── T13 goldens
```

## Risks

| Risk | Mitigation |
| --- | --- |
| Health scoring on a 10k-entry vault blocks the UI | It is O(n) over in-memory entries with a hash map for reuse detection; measure once, and if > 16 ms move to `compute()` |
| Reuse detection reads plaintext passwords into a map | Hash them (`sha256`) before mapping; never keep the plaintext in the report |
| "offline" false positives from a transient 500 | Offline is only shown for connection-level failures (`SocketException`), not HTTP errors |
| Adding `healthReport` to `VaultState` triggers rebuild storms | Compute on unlock and after a write, never per keystroke; `Equatable` props include only the score and counts |

## Verification

```bash
flutter analyze
flutter test test/features/password_manager/domain/services/vault_health_service_test.dart
flutter test test/features/password_manager/presentation
flutter test test/goldens
```

Manual: walk all six sync statuses (disconnect, link, sync, force a conflict,
revoke the token for `error`, airplane mode for offline), open Health on a vault
with known weak/reused entries, merge a duplicate, empty the bin, import a CSV
with bad rows.
