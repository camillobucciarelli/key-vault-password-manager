# 011 — Tasks

Ordered. No parallel flags: the coordinators and the secure data source are
shared across every task. Transport (T1–T3) lands and is verified green before
any keystore behaviour moves (T4–T8).

## Phase 1 · Transport swap (behaviour unchanged)

- [ ] **T1** Add `master_password_session.dart`: in-memory holder with
      `set(String)`, `clear()`, `String? get value`, redacted `toString`, no disk
      write, no logging. Register a singleton in
      `password_manager_presentation_di.dart` and inject into `VaultBloc`,
      `DatabaseSessionCoordinator`, `VaultSessionCoordinator`. Add
      `master_password_session_test.dart` (set/clear/absent). Analyze + test.
- [ ] **T2** FR-1: populate the holder on every successful unlock path
      (manual, stored/biometric, create) in `DatabaseSessionCoordinator`. Redirect
      the two reads — `vault_bloc.dart:148` and
      `vault_session_coordinator.dart:187` (`updateDatabaseSettings`) — to the
      holder. Leave all keystore writes untouched. Behaviour must be identical.
      Run vault-bloc + coordinator tests and analyze.
- [ ] **T3** FR-2: clear the holder on `lockVault`, `changeDatabase`, unlock
      failure, and `AppLifecycleState.detached` (`vault_shell.part.dart:322`).
      Remove the silent `?? ''` fallbacks; an absent session secret raises the
      existing locked-state error, never proceeds with an empty password. Test
      clear-on-lock/switch/detached and the absent-secret error path. Analyze.

## Phase 2 · Keystore gate, per-db key, erase

- [ ] **T4** FR-4: key every entry by database id in `SecureDataSource`
      (`save/get/clearMasterPassword(String databaseId, ...)`); thread `databaseId`
      through `DatabaseSessionRepository` + impl and both DI files. Update
      `unlockWithStoredCredentials`/`hasStoredMasterPassword` to read by id.
      Add `secure_data_source_test.dart`. Analyze + test.
- [ ] **T5** FR-3: gate all five write sites
      (`database_session_coordinator.dart:551,600,804`;
      `vault_session_coordinator.dart:261,340`) on
      `DatabaseSecurityProfile.biometricProtectionEnabled` resolved by database id,
      never assumed. Add `master_password_gate_test.dart` asserting each site in
      both flag states. Analyze + test.
- [ ] **T6** FR-5: `updateBiometricProtection(enabled: false)` deletes the stored
      credential in the same operation that persists the profile; database
      delete/unregister deletes its entry. Extend the gate test with erase cases.
      Analyze + test.

## Phase 3 · Default flag and migration

- [ ] **T7** FR-7: `database_security_repository_impl.dart:51` default
      `?? true` → `?? false`. Update
      `database_security_repository_impl_test.dart` to assert an absent flag
      deserialises to `false`. Analyze + test.
- [ ] **T8** FR-6: add `clearLegacyGlobalMasterPassword()` to `SecureDataSource`
      deleting the legacy `'MASTER_PASSWORD'` key unconditionally; call it once at
      startup in `injection_container.dart`. Add
      `master_password_migration_test.dart`. Analyze + test.

## Phase 4 · Privacy, verification, manual matrix

- [ ] **T9** FR-9: restore the strict `PRIVACY.md` claim (master password reaches
      the keystore only when biometric unlock is enabled) in this same change.
      Run `rg -n "getMasterPassword|saveMasterPassword|MASTER_PASSWORD" lib` and
      confirm no global-key or ungated write remains. AC-8: grep logs/props for
      plaintext.
- [ ] **T10** Run `flutter analyze`, all Phase 1–3 tests, then full `flutter test`
      once. Hand to `senior-tester` for the per-platform manual matrix:
      AC-1/AC-2/AC-5 keystore inspection (Android, Apple; desktop macOS/Linux/
      Windows or `not-run`); AC-3 biometric unlock (Android, Apple); AC-4
      disable-erases; AC-6 upgrade path; AC-7 autofill smoke (Apple + desktop
      browser). Record pass/fail/not-run per platform; host evidence never
      qualifies another platform.
