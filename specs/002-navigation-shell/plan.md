# 002 — Plan

## Approach

Establish typed contract and shell first. Migrate one surface family at a time,
run focused tests, then move its code into destination parts. No simultaneous
edits to shared `part` files.

## Affected files

### New

| Path | Contents |
| --- | --- |
| `lib/features/password_manager/presentation/navigation/vault_shell_router.dart` | concrete final router, sealed DTOs, operation IDs, terminal cleanup and exhaustive route/sheet/pane dispatch |
| `lib/features/password_manager/presentation/screens/vault/vault_settings.part.dart` | Settings placeholder and moved settings surfaces |
| `lib/features/password_manager/presentation/screens/vault/vault_sync.part.dart` | Sync placeholder and moved Drive/sync surfaces |
| `lib/features/password_manager/presentation/screens/vault/vault_confirmations.part.dart` | root confirmation sheet content |
| `test/features/password_manager/presentation/navigation/vault_shell_router_test.dart` | typed results, back, resize, root sheet |
| `test/features/password_manager/presentation/navigation/vault_surface_migration_matrix_test.dart` | exact named 19-current-surface matrix |
| `test/fixtures/vault_dialogs_002_before.txt` | title/body/action copy for all 19 current calls |
| `test/features/password_manager/presentation/screens/vault_shell_test.dart` | destination and width matrix |
| `test/goldens/vault_shell_test.dart` | exact four shell goldens |
| `test/goldens/vault_shell_*.png` | exact inventory from spec |

### Modified

| Path | Change |
| --- | --- |
| `lib/features/password_manager/presentation/screens/vault_screen.dart` | imports/part directives only as each split lands |
| `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart` | selected destination/surface host, mobile/rail layout, placeholders, back/resize handling |
| `lib/features/password_manager/presentation/screens/vault/vault_dialog_password.part.dart` | typed generated-password sheet result |
| `lib/features/password_manager/presentation/screens/vault/vault_dialogs.part.dart` | public typed results, then entry/group/move/sync/confirmation migration and extraction |
| `lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart` | Health routing/results |
| `lib/features/password_manager/presentation/screens/vault/vault_entries.part.dart` | entry routing |
| `lib/features/password_manager/presentation/screens/vault/vault_entries_details.part.dart` | detail/editor/metadata routing |
| `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart` | Settings routing, then cohesive extraction |
| `lib/features/password_manager/presentation/screens/vault/vault_navigation_support.part.dart` | only helpers used by multiple destination parts |
| `lib/features/password_manager/presentation/screens/vault/vault_recycle_bin.part.dart` | Vault sub-surface routing |
| `lib/features/password_manager/presentation/screens/vault/vault_shared.part.dart` | typed CSV confirmation result |

No new core tab/rail/layout widgets: each is used only by this shell and remains a
private widget in `vault_shell.part.dart`. Extract later only on second real use.
`VaultShellRouter` is likewise one concrete final class; testability comes from
its existing Flutter collaborators and widget harness, not a router interface.

## Implementation order

1. Freeze copy for all 19 calls; add typed DTOs, operation IDs, terminal cleanup
   and stale-completion tests.
2. Add exhaustive sealed route/sheet/pane dispatch from FR-6.
3. Add shell destinations, placeholders and valid width arithmetic.
4. Add back/resize and platform transition behaviour.
5. Migrate Vault entry/detail/generator/recycle surfaces.
6. Migrate Health duplicate/merge surfaces.
7. Migrate Sync/Drive/conflict surfaces, then move them to `vault_sync.part.dart`.
8. Migrate Settings/key-file/CSV surfaces, then move them to
   `vault_settings.part.dart`.
9. Move shared confirmation content to `vault_confirmations.part.dart`.
10. Pass exact 19-row migration matrix, then run vault-scoped sweep and goldens.

Each step compiles before the next; migration steps are intentionally serial because
they share `vault_dialogs.part.dart`, `vault_navigation.part.dart` and assembler
directives.

## Risks

| Risk | Mitigation |
| --- | --- |
| Private result types cannot cross router library | Promote exact DTOs before migrating callers; preserve redaction |
| Navigator result and pane callback diverge | One router-owned completer; complete/cancel exactly once in tests |
| Late callback resolves a newer operation | Never-reused operation IDs; terminal callback requires exact live ID and stale callbacks are no-ops |
| Router retains password/editor payload after close | Remove session before completion and clear all surface/result/builder refs in `finally` on every terminal path |
| Route/sheet ambiguity causes wrong mobile presentation | One exhaustive sealed switch; FR-6 matrix tests every surface at 390 and 1024 |
| Width 600–707 cannot fit list + 300 detail | Render one content pane; derive 708 threshold from minimum sums |
| Resize disposes dirty forms | Latch active presentation mode and preserve keyed session subtree |
| Large parts contain interleaved helpers | Move only destination-owned code; leave genuinely shared helpers in support part |
| Platform transition claim differs from current fade helper | Use `MaterialPageRoute` so existing `PageTransitionsTheme` is authoritative |
| One production router gains a speculative interface | Keep `VaultShellRouter` final/concrete; test real class through injected collaborators and harness |

## Verification

```bash
flutter analyze
flutter test test/features/password_manager/presentation/navigation/vault_shell_router_test.dart
flutter test test/features/password_manager/presentation/navigation/vault_surface_migration_matrix_test.dart
flutter test test/features/password_manager/presentation/screens/vault_shell_test.dart
flutter test test/goldens/vault_shell_test.dart
rg -n 'showDialog(?:<[^>]+>)?\s*\(' lib/features/password_manager/presentation/screens/vault --glob '*.dart'
```

Manual: unlock a test vault; visit four destinations at 390, 600, 707, 708,
1023 and 1024 px; open editor, resize without closing, back/cancel, then confirm
from a tablet pane. Full `flutter test` runs once before commit.
