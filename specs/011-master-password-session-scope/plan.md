# 011 — Plan

## Approach

Transport first, gate second — the two-step order the spec mandates so the
hottest path in the app never breaks in a single reviewable change.

1. **FR-1/FR-2 (transport swap, behaviour unchanged).** Introduce an in-memory
   session-secret holder behind the coordinator layer. Every unlock path
   populates it; `VaultBloc` and `VaultSessionCoordinator.updateDatabaseSettings`
   read the session secret from it instead of from `SecureDataSource`. The
   keystore is still written on every unlock at this step, so behaviour is
   identical and the change is a pure indirection. Lock / switch / unlock-failure
   / `detached` clear the holder.
2. **FR-3/FR-4/FR-5/FR-6/FR-7 (gate + per-db key + erase + migrate).** Only now
   restrict keystore writes to biometric-enabled databases, key entries per
   database id, erase on disable/delete, delete the legacy global entry at
   startup, and flip the default flag to `false`.

Splitting the two means step 1 can ship and be verified green with zero
functional change before any keystore behaviour moves.

## Discovered site beyond the spec's five writes

`vault_session_coordinator.dart:187` (`updateDatabaseSettings`) **reads**
`getMasterPassword()` as the current credential for a settings/rename/key-file
change. The spec enumerates it only implicitly. Once FR-3 gates the write, this
read returns null for a biometrics-off database and settings-save breaks. It must
read the session holder (FR-1), not the keystore. Called out here so it is not
missed during the gate step.

## Read/write site map (origin/main @ daf8ff5)

### Keystore writes — gated on `biometricProtectionEnabled` (FR-3), per-db key (FR-4)

| Site | Context |
| --- | --- |
| `database_session_coordinator.dart:804` | `updateBiometricProtection` persist / manual-unlock enrol |
| `database_session_coordinator.dart:600` | database creation |
| `database_session_coordinator.dart:551` | rollback restore of previous value |
| `vault_session_coordinator.dart:261` | master-password change |
| `vault_session_coordinator.dart:340` | re-save after a vault operation |

### Session-secret reads — redirect to holder (FR-1)

| Site | Change |
| --- | --- |
| `vault_bloc.dart:148` | read holder, not `secureDataSource`; absent secret is locked-state error, not `?? ''` (FR-2) |
| `vault_session_coordinator.dart:187` | read holder for current credential |

### Keystore reads — legitimately persistent, biometric path only, now per-db key (FR-4)

| Site | Change |
| --- | --- |
| `database_session_coordinator.dart:817` | `unlockWithStoredCredentials`: read by db id; remove silent `?? ''` |
| `database_session_coordinator.dart:826` | `hasStoredMasterPassword`: read by db id |

### Keystore clears — kept, now per-db key (FR-4)

`vault_session_coordinator.dart:100` (changeDatabase), `:106` (lockVault);
`database_session_coordinator.dart:327,549,655,846,931`. Each also clears the
in-memory holder where it represents a lock/switch (FR-2).

## Autofill impact (FR-8) — verified, not assumed

`rg getMasterPassword|MASTER_PASSWORD|secureDataSource` across
`apple_autofill_v2_coordinator.dart`, `desktop/native_host/`,
`tool/native_host*.dart` → **zero matches**. Autofill never reads the keystore
master password; it receives credentials only through the already-unlocked vault.
FR-8 read-side parity holds by construction. Smoke test still recorded per AC-7.
No overlap with the in-flight spec-009 branch (extension JS + native host only).

## Affected files

### New

| Path | Contents |
| --- | --- |
| `lib/features/password_manager/presentation/coordinators/master_password_session.dart` | FR-1 in-memory session-secret holder; `set/clear/value`, no disk, no logging, redacted `toString` |
| `test/features/password_manager/presentation/coordinators/master_password_session_test.dart` | set/clear/absent-value contract |
| `test/features/password_manager/presentation/coordinators/master_password_gate_test.dart` | FR-3 gate for all five write sites, both flag states; FR-5 erase-on-disable |
| `test/features/password_manager/presentation/coordinators/master_password_migration_test.dart` | FR-6 legacy global entry deleted on first run |
| `test/features/password_manager/data/datasources/secure_data_source_test.dart` | per-db key (FR-4) + legacy-clear (FR-6) |

### Modified

| Path | Change |
| --- | --- |
| `lib/features/password_manager/data/datasources/secure_data_source.dart` | key by database id (FR-4); add `clearLegacyGlobalMasterPassword()` (FR-6); drop global `'MASTER_PASSWORD'` const |
| `lib/features/password_manager/domain/repositories/database_session_repository.dart` | thread `databaseId` through save/get/clear master-password |
| `lib/features/password_manager/data/repositories/database_session_repository_impl.dart` | pass `databaseId` to secure data source |
| `lib/features/password_manager/data/repositories/database_security_repository_impl.dart` | default `biometricProtectionEnabled` `?? true` → `?? false` (FR-7) |
| `lib/features/password_manager/presentation/coordinators/database_session_coordinator.dart` | gate writes on profile flag (FR-3); per-db key (FR-4); populate holder on unlock; clear holder on lock/switch/failure; erase entry in `updateBiometricProtection(false)` and on db delete (FR-5) |
| `lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart` | gate writes (FR-3); read holder in `updateDatabaseSettings` (FR-1); clear holder in `lockVault`/`changeDatabase` (FR-2) |
| `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart` | read session holder at init instead of `secureDataSource`; absent secret → locked error, remove `?? ''` (FR-2) |
| `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart` | `AppLifecycleState.detached` clears holder + keystore session state (FR-2) |
| `lib/features/password_manager/di/password_manager_data_di.dart` | thread db-id secure API |
| `lib/features/password_manager/di/password_manager_presentation_di.dart` | register `MasterPasswordSession` singleton; inject into VaultBloc + coordinators |
| `lib/injection_container.dart` | run FR-6 legacy-clear once at startup |
| `PRIVACY.md` | restore strict claim in the same change (FR-9) |
| `test/features/password_manager/presentation/bloc/vault_bloc_test.dart` | FR-1 source change; absent-secret case |
| `test/features/password_manager/data/repositories/database_security_repository_impl_test.dart` | FR-7 absent flag → `false` |

## Implementation order

1. Add `MasterPasswordSession` holder + test. Register in DI.
2. FR-1: redirect the two read sites to the holder; populate on every unlock
   path; keep keystore writes untouched. Green with no behaviour change.
3. FR-2: clear holder on lock/switch/failure/detached; remove `?? ''`; absent
   secret raises locked error. Bloc/coordinator tests.
4. FR-4: per-db key in `SecureDataSource` + repository/port threading.
5. FR-3: gate all five writes on the resolved profile flag.
6. FR-5: erase on `updateBiometricProtection(false)` and on db delete.
7. FR-7: flip default flag to `false` + repository test.
8. FR-6: `clearLegacyGlobalMasterPassword()` at startup + migration test.
9. FR-9: update `PRIVACY.md`. Analyze, targeted tests, full `flutter test`.

Every step compiles. Steps 1–3 are the transport swap; 4–8 are the gate; the two
halves are separately reviewable.

## Risks

| Risk | Mitigation |
| --- | --- |
| Breaking unlock/save/sync on the hottest path | FR-1 transport swap lands first, behaviour identical; gate follows separately |
| Settings-save silently breaks with biometrics off (discovered read at :187) | Redirect that read to the holder in the FR-1 step, not the gate step |
| Existing installs read back as biometric-enabled (`?? true`) | FR-7 flips default to `false`; FR-6 deletes the unattributable legacy entry |
| Global key serves wrong vault's password | FR-4 keys every entry by database id |
| Session secret leaks via logs/props/toString | Holder has redacted `toString`, no logging; AC-8 asserts |
| Per-platform secure-store divergence | Manual matrix per AC; uncovered platform recorded `not-run`, never inferred |

## Verification

```bash
flutter analyze
flutter test test/features/password_manager/presentation/coordinators/master_password_session_test.dart
flutter test test/features/password_manager/presentation/coordinators/master_password_gate_test.dart
flutter test test/features/password_manager/presentation/coordinators/master_password_migration_test.dart
flutter test test/features/password_manager/data/datasources/secure_data_source_test.dart
flutter test test/features/password_manager/data/repositories/database_security_repository_impl_test.dart
flutter test test/features/password_manager/presentation/bloc/vault_bloc_test.dart
rg -n "getMasterPassword|saveMasterPassword|MASTER_PASSWORD" lib
```

Manual, per platform, recorded pass/fail/not-run: keystore inspection AC-1/2/5
(Android, Apple; desktop macOS/Linux/Windows); biometric unlock AC-3 (Android,
Apple); Apple + desktop-browser autofill smoke (FR-8). Host evidence never
qualifies another platform. Full `flutter test` runs once before commit.
