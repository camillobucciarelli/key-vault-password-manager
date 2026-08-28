# 014 — Managed storage hardening

**Status**: Planned · **Kind**: Security  
**Depends on**: 003 · **Coordinates with**: 013 (local copy of the Drive vault), 010 (storage port)

## Summary

Keep app-managed storage on every native platform, but harden it: move the
desktop managed root out of `~/Documents` into the application data directory,
give database and key files opaque on-disk names, encrypt the three metadata
files, key sync mappings by database identifier instead of by path, enforce
restrictive permissions on databases, key files and backups, and delete the
global `cachedKeyFilePath` fallback.

There is **no migration**. The app has no users beyond the developer, so a vault
created by the previous version may become unopenable and a clean reinstall is
an acceptable outcome. A non-conforming on-disk state is an error, not a case to
be reconciled.

Spec 014 is the **normative source for where managed files live, what they are
named, and how their metadata is protected**. It does not change the vault byte
format, the safe-writer invariants owned by spec 008, or the sync algorithm.

## Problem and current state

- Every managed file resolves under `getApplicationDocumentsDirectory()`:
  `MobileFileStorage._ensureSubdirectory` (`lib/core/utils/mobile_file_storage.dart:283`),
  `SyncMetadataDataSourceImpl` (`sync_metadata_data_source.dart:217`),
  `DatabaseRegistryLocalDataSource` (`database_registry_local_data_source.dart:74`),
  `DatabaseSecurityLocalDataSource` (`database_security_local_data_source.dart:82`)
  and `LocalDataSource` (`local_data_source.dart:88`). On macOS, Windows and
  Linux that resolves to the user's real `~/Documents`, which is routinely
  synchronised by iCloud Drive, OneDrive or Dropbox — so databases and key files
  are pushed into a third-party cloud without the user ever asking for it.
  `SafeVaultFileIo.isAppPrivateDocumentsRoot`
  (`safe_vault_file_writer.dart:156`) already documents this divergence for the
  writer; the storage root itself has not been moved.
- On-disk names are human-readable and self-describing. The wizard defaults to
  `new_database.kdbx` (`create_database_screen.dart:32`), generated key files are
  written as `database.key` (`create_database_usecase.dart:115`), and a selected
  key file keeps its original basename when copied into the managed `keys`
  subdirectory (`database_import_service.dart:563`). Anyone who lists the
  directory learns which vaults exist and which key belongs to which vault.
- `database_registry_records.json`, `database_security_profiles.json` and
  `sync_mappings.json` are stored as plaintext JSON. They enumerate every vault,
  its security profile and its remote mapping.
- `SyncMetadataDataSourceImpl` keys mappings by `mapping.databasePath`
  (`sync_metadata_data_source.dart:38-75`). The key is therefore invalidated by
  any relocation of the managed root — precisely what this spec performs.
- `SafeVaultFileWriter` applies `0600` to vault files
  (`safe_vault_file_writer.dart:304`, `defaultVaultMode`), but key files written
  through `saveKeyFile` on the managed path and backup files do not go through
  the same mode enforcement.
- `LocalDataSource.keyFilePathKey = 'cachedKeyFilePath'`
  (`local_data_source.dart:17`) holds one global key-file path in
  `local_state.json`, consulted as a fallback by
  `DatabaseSessionCoordinator` (`database_session_coordinator.dart:793-806`).
  It is a second source of truth next to the per-database security profile, and
  it can attach the wrong key to the wrong database.

## Goals

1. Keep the app the owner of every database and key file copy, on all native
   platforms.
2. Move the desktop managed root off `~/Documents`.
3. Make the managed directory reveal nothing by listing it.
4. Make the three metadata files unreadable without a system-protected key.
5. Make sync mappings survive a change of storage root.
6. Enforce owner-only permissions on databases, key files and backups.
7. Remove the global cached key-file path.

## Non-goals

- No user-owned storage model: no security-scoped bookmarks, no Android SAF
  persisted grants, no "point at a file the user chose". This was evaluated and
  rejected — see *Rejected alternative*.
- No migration, no start-up reconciler, no adjustment prompt, no compatibility
  shim for vaults created by the previous version.
- No change to the hash-based relocation rule.
- No change to the KDBX format, to `VaultKdbxService`, to `DatabasePathMutex`,
  or to the safe-writer algorithm itself.
- No web support. Web has no managed storage and is out of scope here.
- No export or backup UX work; that stays where it is.

## Rejected alternative — user-owned storage

Pointing the app at a path the user picked does not work on this product's
platform matrix:

- On iOS and Android the file picker returns a **temporary copy**, not a durable
  path, so the "user's file" is not addressable after the picker closes.
- Android SAF exposes a document URI, not a filesystem path, and the existing
  `dart:io` write path — including `SafeVaultFileWriter` — is path-based.
- A per-file grant addresses exactly one file, which forbids writing the sibling
  backup that spec 008 FR-9 requires next to the vault.

Managed storage is therefore retained on all native platforms, and hardened
instead.

## Functional requirements

**FR-1 — Managed ownership.** On Android, iOS, macOS, Windows and Linux the app
owns the database and key-file copies. Importing a file copies it into managed
storage; the user's original is never modified and never deleted.

**FR-2 — Desktop managed root.** On macOS, Windows and Linux the managed root is
the application data directory — Application Support, AppData and
`~/.local/share` respectively — not `~/Documents`. On Android and iOS the root
stays the app documents directory, which is already app-private. Every call site
listed under *Problem and current state* resolves through the same single root
helper; no data source resolves its own root independently.

**FR-3 — Opaque names.** Database and key files are stored under a random
identifier with no meaningful extension. The name is **not** derived from the
database identifier, from the display name, or from any value present in the
metadata files — otherwise the database-to-key association is reconstructable
from the directory listing alone. The human-readable name exists only inside the
encrypted registry and in export/download output. This replaces the
`<database-name>.key` convention.

**FR-4 — Encrypted metadata.** `database_registry_records.json`,
`database_security_profiles.json` and `sync_mappings.json` are encrypted at
rest. The metadata key lives in the platform secure store (Keychain, DPAPI,
libsecret) **without a biometric gate**: it only lists databases, it never
unlocks one. Gating it biometrically would block the database list behind a
prompt while protecting nothing that is not already protected by the vault's own
credentials.

**FR-5 — Secure store unavailable.** When the secure store cannot return the
metadata key, the app shows an **empty database list** and offers recovery only
through manual re-selection of the vault files. It never falls back to plaintext
metadata, and it never silently recreates the key over existing ciphertext.

**FR-6 — Mapping key.** `sync_mappings.json` is keyed by **database
identifier**, not by database path. `getMapping`, `upsertMapping` and
`removeMapping` in `SyncMetadataDataSourceImpl` take the identifier.

**FR-7 — Permissions.** On macOS, Windows and Linux, databases, key files and
backup files are created owner-only. The `0600` behaviour already implemented
for vault writes in `SafeVaultFileWriter` (`defaultVaultMode`) is extended to
key files and backups, with tests. Where the platform supports it, the managed
directory is excluded from automatic backup (iOS/macOS "do not back up"
attribute, Android `allowBackup`/`backup_rules`).

**FR-8 — Single key source.** `cachedKeyFilePath` is removed from
`local_state.json` and from the `DatabaseSessionCoordinator` fallback. The
`keyFilePath` of the per-database security profile is the only source of truth.

**FR-9 — No migration.** No migration code, no reconciler, no prompt. A
non-conforming on-disk state produces an explicit error. Losing access to vaults
created by the previous version is an accepted outcome of this spec.

## Acceptance criteria

1. Listing the managed directory on any platform shows no human-readable
   database name, no `.kdbx` extension and no `.key` extension, and no name from
   which the database-to-key association can be derived.
2. `database_registry_records.json`, `database_security_profiles.json` and
   `sync_mappings.json` are unreadable without the secure-store key; a test
   asserts no plaintext database name or path appears in their bytes.
3. On macOS and Linux, a freshly created database, key file and backup are all
   owner-only; the assertion is a test, not a manual step. Windows records the
   equivalent ACL outcome.
4. `SafeVaultFileWriter`, `DatabasePathMutex` and Google Drive sync show no
   behavioural regression: the existing suites stay green, including
   `test/tool/safe_vault_writer_harness_test.dart`.
5. With the secure store made unavailable, the app starts, shows an empty
   database list, does not crash, does not write plaintext metadata, and lets
   the user recover a vault by re-selecting its files manually.
6. The desktop managed root is no longer under `~/Documents`; a test asserts the
   resolved root for each desktop platform.
7. Sync mappings resolve by database identifier and survive a change of the
   managed root path within one run.
8. `cachedKeyFilePath` no longer appears anywhere in `lib/`.

## Risks

| Risk | Mitigation |
| --- | --- |
| Dependence on Keychain / DPAPI / libsecret; libsecret is inconsistent across Linux desktops | FR-5 makes an unavailable store a defined, safe state (empty list + manual recovery), not a crash and never a plaintext fallback |
| Losing the metadata key makes the database list unrecoverable | The vaults themselves stay openable with their own credentials; recovery is manual re-selection. Documented as accepted, not mitigated away |
| Interaction with `PortablePath` (`lib/core/utils/portable_path.dart`), which exists to survive iOS container-UUID rotation | The new root must be stored portably, exactly as today; `integration_test/ios_portable_paths_qa_test.dart` is re-run manually after the root move |
| Existing guard tests assume the app-private perimeter — `test/core/utils/mobile_file_storage_guard_qa_test.dart`, `mobile_file_storage_guard_bypass_qa_test.dart`, `test/features/password_manager/data/portable_path_symlink_qa_test.dart` | These are updated in the same change as the root move, never disabled; the perimeter assertion moves with the root |
| Spec 008 Gate 0 inventory (`database_writer_inventory_test.dart`) pins the set of writers | Opaque naming and permission changes must not add a writer; if the inventory changes, it is updated deliberately with the spec 008 owner |
| Opaque names make manual filesystem debugging harder | The encrypted registry is the map; add a developer-only read path only if it proves necessary, never a plaintext sidecar |
| Coordination with 013: the Drive vault's local copy also lives in managed storage | 013 owns remote identity, 014 owns local placement and naming; neither respecifies the other |

## Open questions

None blocking. Which primitive encrypts the metadata files, and whether the
managed root exposes one directory or two (`databases` and `keys`, as today), are
implementation choices made in the plan, not policy decisions.
