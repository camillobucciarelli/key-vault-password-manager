# 014 — Tasks

Ordered tasks. Each names the requirement it satisfies, the files it touches and
how it is verified. There is no migration phase by design (FR-9): nothing here
reads or repairs a previous on-disk layout.

## Phase 1 — one managed root

- [ ] T001 FR-2: introduce a single managed-root resolver returning the app data
      directory on macOS/Windows/Linux and the app documents directory on
      Android/iOS, and route `MobileFileStorage._ensureSubdirectory`,
      `SyncMetadataDataSourceImpl`, `DatabaseRegistryLocalDataSource`,
      `DatabaseSecurityLocalDataSource` and `LocalDataSource` through it.
      Verified by a unit test asserting the resolved root per platform.
- [ ] T002 FR-2: update the app-private perimeter checks and their guard tests
      (`mobile_file_storage_guard_qa_test.dart`,
      `mobile_file_storage_guard_bypass_qa_test.dart`,
      `portable_path_symlink_qa_test.dart`) so the perimeter follows the new
      root. No guard is weakened or skipped.
- [ ] T003 FR-2: confirm `PortablePath` still stores the new root portably and
      re-run `integration_test/ios_portable_paths_qa_test.dart` on a simulator;
      record the outcome.

## Phase 2 — opaque names

- [ ] T004 FR-3: generate an opaque random on-disk identifier for databases and
      key files, not derived from the database identifier or display name, and
      write it with no meaningful extension.
- [ ] T005 FR-3: move the human-readable name into the registry record only, and
      update every UI/export path that currently reads the file basename.
- [ ] T006 FR-3: test that a managed directory listing contains no readable
      name, no `.kdbx`/`.key` extension, and no value shared with the registry
      that would rebind a key to its database.

## Phase 3 — encrypted metadata

- [ ] T007 FR-4: add a metadata key in the platform secure store with no
      biometric gate, created once and never regenerated over existing
      ciphertext.
- [ ] T008 FR-4: encrypt and decrypt `database_registry_records.json`,
      `database_security_profiles.json` and `sync_mappings.json` at their data
      sources; test that no plaintext name or path survives in the file bytes.
- [ ] T009 FR-5: define the unavailable-secure-store state — empty database
      list, no plaintext fallback, manual re-selection recovery — and test it
      with the store stubbed unavailable.

## Phase 4 — mapping identity

- [ ] T010 FR-6: change `getMapping`, `upsertMapping` and `removeMapping` in
      `SyncMetadataDataSourceImpl` to key by database identifier, and update the
      orchestrator call sites.
- [ ] T011 FR-6: test that a mapping resolves after the managed root path
      changes within one run.

## Phase 5 — permissions and backup exclusion

- [ ] T012 FR-7: extend the `SafeVaultFileWriter` `0600` behaviour
      (`defaultVaultMode`) to key-file writes and to backup files, with tests on
      macOS/Linux and the recorded ACL outcome on Windows.
- [ ] T013 FR-7: exclude the managed directory from automatic backup where the
      platform allows it (iOS/macOS do-not-back-up attribute, Android backup
      rules).

## Phase 6 — single key source

- [ ] T014 FR-8: remove `cachedKeyFilePath` from `LocalDataSource` and the
      fallback in `DatabaseSessionCoordinator`, leaving the per-database
      security profile as the only key-file source; test that a database with no
      profile key does not silently borrow another database's key.

## Phase 7 — closing checks

- [ ] T015 FR-9: assert no migration or reconciler path was added, and that a
      non-conforming on-disk state raises an explicit error.
- [ ] T016 Regression gate: `flutter analyze` clean and `flutter test` green,
      including `test/tool/safe_vault_writer_harness_test.dart` and the spec 008
      `database_writer_inventory_test.dart`.
