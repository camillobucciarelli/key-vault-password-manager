# 003 — Plan

## Approach

Contracts first, then selection, then unlock. Preserve existing copy fixture
before code moves. First remove coordinator→data/platform imports. Extend existing
BLoCs/coordinator only where UI cannot render required typed state; coordinator
sequences workflow while use cases/repository ports own file/auth/KDBX I/O.

## Affected files

### New

| Path | Contents |
| --- | --- |
| `lib/features/password_manager/domain/models/database_selection_item.dart` | C-1 immutable metadata |
| `lib/features/password_manager/domain/models/drive_account_summary.dart` | account + `DrivePickerData` |
| `lib/features/password_manager/domain/errors/database_access_failure.dart` | typed failures C-3 |
| `lib/features/password_manager/domain/models/database_import_transaction.dart` | staged import/commit value types moved out of data |
| `lib/features/password_manager/domain/models/recent_database_removal_mode.dart` | removal enum moved out of BLoC event file |
| `lib/features/password_manager/domain/repositories/database_file_repository.dart` | file/import/key persistence port from C-7 |
| `lib/features/password_manager/domain/repositories/database_session_repository.dart` | cached path/stored-secret port from C-7 |
| `lib/features/password_manager/domain/usecases/create_database_usecase.dart` | KDBX/key creation and partial-output rollback |
| `lib/features/password_manager/data/repositories/database_session_repository_impl.dart` | existing local/secure data-source adapter |
| `lib/features/password_manager/presentation/screens/welcome_screen.dart` | welcome composition |
| `lib/features/password_manager/presentation/screens/create_database_screen.dart` | typed three-step route |
| `lib/features/password_manager/presentation/widgets/database/drive_picker_skeleton.dart` | row-shaped loading state |
| `lib/core/widgets/kv_bottom_sheet.dart` | extraction on second real use after 002 |
| `lib/core/widgets/kv_pill_button.dart` | extraction on second use inside 003 |
| `lib/features/password_manager/presentation/widgets/internal_key_file_manager_sheet.dart` | typed sheet replacement |
| `test/fixtures/strings_003_before.txt` | reviewed pre-change literal snapshot |
| `test/features/password_manager/domain/usecases/unlock_database_usecase_test.dart` | package-exception mapping |
| `test/features/password_manager/domain/usecases/create_database_usecase_test.dart` | create success/rollback through fake ports |
| `test/features/password_manager/data/repositories/database_session_repository_impl_test.dart` | local/secure data-source adapter |
| `test/features/password_manager/presentation/coordinators/database_session_coordinator_imports_test.dart` | analyzer-based import URI architecture gate |
| `test/features/password_manager/presentation/screens/database_selection_screen_test.dart` | selection behaviour/copy/layout |
| `test/features/password_manager/presentation/screens/database_unlock_screen_test.dart` | unlock behaviour/copy/layout |
| `test/goldens/database_and_unlock_test.dart` | exact 22-case harness |
| `test/goldens/db_*.png`, `test/goldens/unlock_*.png` | exact inventory from spec |

### Modified

| Path | Change |
| --- | --- |
| `lib/features/password_manager/domain/repositories/database_sync_repository.dart` | `getConnectedAccount()` contract |
| `lib/features/password_manager/domain/usecases/validate_database_usecase.dart` | typed invalid/unsupported result instead of bool-only collapse |
| `lib/features/password_manager/domain/usecases/unlock_database_usecase.dart` | typed missing/key/KDBX exception mapping |
| `lib/features/password_manager/data/services/drive_auth_service.dart` | expose mobile current account and desktop fallback, no new OAuth scope |
| `lib/features/password_manager/data/services/database_import_service.dart` | implement `DatabaseFileRepository`; typed validation/stage/commit/rollback cleanup |
| `lib/features/password_manager/data/repositories/database_sync_repository_impl.dart` | account mapping |
| `lib/features/password_manager/presentation/coordinators/database_session_coordinator.dart` | final concrete coordinator; remove one-implementation contract; depend only on domain ports/use cases |
| `lib/features/password_manager/presentation/bloc/database_selection/database_selection_event.dart` | typed locate/create-step events; secrets remain redacted |
| `lib/features/password_manager/presentation/bloc/database_selection/database_selection_state.dart` | metadata items, typed failure, non-secret create step |
| `lib/features/password_manager/presentation/bloc/database_selection/database_selection_bloc.dart` | delegate new operations to coordinator |
| `lib/features/password_manager/presentation/bloc/database_unlock/database_unlock_event.dart` | no new secret-bearing state; phase-compatible events |
| `lib/features/password_manager/presentation/bloc/database_unlock/database_unlock_state.dart` | phase/failure/progress contract |
| `lib/features/password_manager/presentation/bloc/database_unlock/database_unlock_bloc.dart` | typed mapping and decrypting transition |
| `lib/features/password_manager/presentation/screens/database_selection_screen.dart` | metadata rows, responsive root, typed route/sheets |
| `lib/features/password_manager/presentation/screens/database_unlock_screen.dart` | phase-driven composition and typed sheets |
| `lib/features/password_manager/presentation/screens/database_unlock_widgets.part.dart` | biometric/decrypting/key states |
| `lib/features/password_manager/presentation/widgets/database/recent_databases_section.dart` | reuse with `DatabaseSelectionItem`; preserve snapshotted copy |
| `lib/features/password_manager/presentation/widgets/database/database_item_tile.dart` | reuse for metadata/missing row; no replacement widget |
| `lib/features/password_manager/presentation/widgets/database/database_action_menu.dart` | reuse existing actions and add conditional Locate |
| `lib/features/password_manager/di/password_manager_data_di.dart` | bind data implementations to new domain ports |
| `lib/features/password_manager/di/password_manager_domain_di.dart` | register create/validation/unlock use cases |
| `lib/features/password_manager/di/password_manager_presentation_di.dart` | inject coordinator using domain contracts only |
| `pubspec.yaml` | add direct dev dependency on `analyzer` for import-AST architecture test; never edit `version:` |
| `test/features/password_manager/presentation/coordinators/database_session_coordinator_test.dart` | metadata/create/locate/duplicate transactions |
| `test/features/password_manager/presentation/bloc/database_selection_bloc_test.dart` | metadata/create steps/failures |
| `test/features/password_manager/presentation/bloc/database_unlock_bloc_test.dart` | phases/progress/failures |

### Deleted after caller migration

- `lib/features/password_manager/presentation/widgets/create_database_dialog.dart`
- `lib/features/password_manager/presentation/widgets/internal_key_file_manager_dialog.dart`

## Implementation order

1. Snapshot copy across all eight source files.
2. Add domain file/session ports and create use case; rewire DI and remove every
   data/platform/KDBX import from coordinator with existing tests green.
3. Add typed failures/metadata/account models and map data/use-case boundaries.
4. Extend coordinator aggregation and transactional locate/duplicate/create policy.
5. Extend selection BLoC state/events, then rebuild welcome/recent/create/Drive
   screens and migrate sheets.
6. Extend unlock BLoC phase/failure state, then rebuild unlock and key-file sheet.
7. Add omitted-axis widget tests, exact 22 goldens, scoped dialog/copy sweeps.

Every step compiles. Selection and unlock screen edits are serial because both
depend on coordinator contracts and shared sheet/button extraction.

## Transaction rules

- Validation happens before any registry/mapping mutation.
- Locate hash mismatch mutates nothing.
- Replace duplicate creates dated backup, updates in one coordinator operation,
  restores backup/metadata on failure, then deletes backup only after success.
- Keep both chooses collision-free path and new database ID.
- Use existing/cancel always discard staged import.
- Create failure removes partial output/key material created by that attempt and
  leaves prior active database/credentials unchanged.

## Risks

| Risk | Mitigation |
| --- | --- |
| Typed failure mapping mislabels bad credentials as corruption | Map concrete `kdbx` exceptions in use-case tests |
| Password leaks through wizard state/equality/logs | Keep controller-local; event props use `RedactedValue`; BLoC state stores no secret |
| Metadata aggregation becomes UI repository access | Coordinator joins registry/security/sync/file existence once |
| Locate points metadata at another vault | Require stored hash match when available; reject mismatch |
| Fake Argon2 progress implies certainty | `progress == null` only; indeterminate semantics and no ETA |
| Desktop account identity unavailable | Typed fallback; no silent OAuth scope expansion |
| Copy changes during widget rewrite | Freeze fixture before edits; approve only explicit spec list |
| Coordinator keeps architecture violation while gaining workflow | Gate feature work on analyzer-based import URI test and domain-port DI tests |

## Verification

```bash
flutter analyze
flutter test test/features/password_manager/domain/usecases/unlock_database_usecase_test.dart
flutter test test/features/password_manager/domain/usecases/create_database_usecase_test.dart
flutter test test/features/password_manager/data/repositories/database_session_repository_impl_test.dart
flutter test test/features/password_manager/presentation/coordinators/database_session_coordinator_imports_test.dart
flutter test test/features/password_manager/presentation/coordinators/database_session_coordinator_test.dart
flutter test test/features/password_manager/presentation/bloc/database_selection_bloc_test.dart
flutter test test/features/password_manager/presentation/bloc/database_unlock_bloc_test.dart
flutter test test/features/password_manager/presentation/screens/database_selection_screen_test.dart
flutter test test/features/password_manager/presentation/screens/database_unlock_screen_test.dart
flutter test test/goldens/database_and_unlock_test.dart
rg -n 'showDialog(?:<[^>]+>)?\s*\(' lib/features/password_manager/presentation/screens/database_selection_screen.dart lib/features/password_manager/presentation/screens/database_unlock_screen.dart lib/features/password_manager/presentation/screens/create_database_screen.dart lib/features/password_manager/presentation/widgets/internal_key_file_manager_sheet.dart
```

Manual: first run; create success/cancel/failure; Drive loading/empty/switch;
invalid and corrupt files; every duplicate choice; missing recent locate
match/mismatch; password/key/biometric unlock; missing key; resize desktop card.
Full `flutter test` runs once before commit.
