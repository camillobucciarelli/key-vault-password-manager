# 014 — Tasks

Ordered tasks. Each names the requirement it satisfies, the files it touches and
how it is verified. There is no migration phase by design (FR-9): nothing here
reads or repairs a previous on-disk layout.

## Phase 1 — one managed root

- [x] T001 FR-2: introduce a single managed-root resolver returning the app data
      directory on macOS/Windows/Linux and the app documents directory on
      Android/iOS, and route `MobileFileStorage._ensureSubdirectory`,
      `SyncMetadataDataSourceImpl`, `DatabaseRegistryLocalDataSource`,
      `DatabaseSecurityLocalDataSource` and `LocalDataSource` through it.
      Verified by a unit test asserting the resolved root per platform.
- [x] T002 FR-2: update the app-private perimeter checks and their guard tests
      (`mobile_file_storage_guard_qa_test.dart`,
      `mobile_file_storage_guard_bypass_qa_test.dart`,
      `portable_path_symlink_qa_test.dart`) so the perimeter follows the new
      root. No guard is weakened or skipped.
- [ ] T003 FR-2: confirm `PortablePath` still stores the new root portably and
      re-run `integration_test/ios_portable_paths_qa_test.dart` on a simulator;
      record the outcome.

## Phase 2 — opaque names

- [x] T004 FR-3: generate an opaque random on-disk identifier for databases and
      key files, not derived from the database identifier or display name, and
      write it with no meaningful extension.
- [x] T005 FR-3: move the human-readable name into the registry record only, and
      update every UI/export path that currently reads the file basename.
- [x] T006 FR-3: test that a managed directory listing contains no readable
      name, no `.kdbx`/`.key` extension, and no value shared with the registry
      that would rebind a key to its database.
- [x] T006b FR-1: assert managed ownership still holds after the renaming work.
      Importing a database or selecting a key file copies it into managed storage,
      and the user's original file is neither modified nor deleted. This is a
      preserved invariant rather than new behaviour, but T004 and T005 rewrite the
      copy path in `database_import_service.dart` and `create_database_usecase.dart`
      that enforces it, so it needs its own assertion rather than being assumed.

## Phase 3 — encrypted metadata

- [x] T007 FR-4: add a metadata key in the platform secure store with no
      biometric gate, created once and never regenerated over existing
      ciphertext.
- [x] T008 FR-4: encrypt and decrypt `database_registry_records.json`,
      `database_security_profiles.json` and `sync_mappings.json` at their data
      sources; test that no plaintext name or path survives in the file bytes.
- [x] T009 FR-5: define the unavailable-secure-store state — empty database
      list, no plaintext fallback, manual re-selection recovery — and test it
      with the store stubbed unavailable.

## Phase 4 — mapping identity

- [x] T010 FR-6: change `getMapping`, `upsertMapping` and `removeMapping` in
      `SyncMetadataDataSourceImpl` to key by database identifier, and update the
      orchestrator call sites.
- [x] T011 FR-6: test that a mapping resolves after the managed root path
      changes within one run.

## Phase 5 — permissions and backup exclusion

- [x] T012 FR-7: extend the `SafeVaultFileWriter` `0600` behaviour
      (`defaultVaultMode`) to key-file writes and to backup files, with tests on
      macOS/Linux and the recorded ACL outcome on Windows.
- [x] T013 FR-7: exclude the managed directory from automatic backup where the
      platform allows it (iOS/macOS do-not-back-up attribute, Android backup
      rules).

## Phase 6 — single key source

- [x] T014a FR-8: remove the cached-key-path API from the data layer and the
      domain port — `LocalDataSource.getCachedKeyFilePath`/`cacheKeyFilePath` and
      the `keyFilePathKey = 'cachedKeyFilePath'` constant, their forwarding pair
      in `DatabaseSessionRepositoryImpl`, and both declarations on the
      `DatabaseSessionRepository` port. Removing them from the port is a breaking
      interface change: every implementation and every test fake that satisfies it
      must be updated in the same commit.
- [x] T014b FR-8: remove all 11 coordinator call sites, not only the unlock
      fallback. `DatabaseSessionCoordinator` holds 8 (a read at the rollback
      capture, the unlock-time fallback read and its normalisation, writes on
      import/create/unlock/relink, and clears on removal and on
      `_clearSessionCredentials`); `VaultSessionCoordinator` holds 3 (a clear on
      lock and two writes on unlock/change-database) and is named in no earlier
      draft of this task. A write site is deleted outright; a clear site becomes
      dead and is deleted with it; the rollback capture stops restoring a value
      that no longer exists.
- [x] T014c FR-8: `SyncMergeRepositoryImpl` reads the cached path as a key-file
      fallback during a merge. That is spec 008 code, so removing it is a
      cross-spec change: it must resolve the key file from the per-database
      security profile instead, and the spec 008 merge and convergence suites must
      be re-run. Coordinate with the spec 008 owner before editing; do not leave
      the merge path silently without a key-file source.
- [x] T014d FR-8: update the seven test files that stub or assert the removed API
      — including `fake_database_ports.dart`, the two coordinator test fakes, the
      repository impl test and `portable_path_regression_qa_test.dart:154` — and
      test that a database with no profile key does not silently borrow another
      database's key.

      **Inventory note.** A search at the time of writing finds 32 references in
      `lib/` across 7 files and 7 test files. Regenerate the inventory at
      implementation time with `rg -n 'cacheKeyFilePath|getCachedKeyFilePath|cachedKeyFilePath' lib test`
      and treat AC-8 as satisfied only when that search returns nothing in `lib/`.

## Phase 7 — closing checks

- [x] T015 FR-9: assert no migration or reconciler path was added, and that a
      non-conforming on-disk state raises an explicit error.
- [x] T016 Regression gate: `flutter analyze` clean and `flutter test` green,
      including `test/tool/safe_vault_writer_harness_test.dart` and the spec 008
      `database_writer_inventory_test.dart`.

## Phase 8 — FR-5 recovery (field defect, 2026-09-04)

- [x] T017 FR-5: make the recovery FR-5 promises reachable. A device was found
      with metadata ciphertext on disk and no key entry in the secure store
      (Pixel 11 Pro, `ENCRYPTED_PREFERENCES_MIGRATED=true`): reads were empty as
      specified, but every write was refused, so the "manual re-selection"
      recovery could not run and the app could never record a database again.
      `EncryptedMetadataStore.writeString` now throws the typed
      `MetadataStorageUnreadableFailure` instead of a bare `StateError`; the
      refusal itself is unchanged, and nothing is discarded implicitly.
- [x] T018 FR-5: `MetadataRecoveryService` (port
      `MetadataRecoveryRepository`) reports unreadable metadata and, on the
      user's explicit confirmation only, renames it aside so writes resume under
      a fresh key. A store that is merely unreachable is never treated as
      unreadable, and files are renamed, never deleted.
- [x] T019 FR-5: the database selection screen turns
      `MetadataStorageUnreadableFailure` into a confirm sheet ("Saved database
      details unreadable" → Reset) that dispatches `DiscardUnreadableMetadata`;
      declining leaves the refusal in place.
