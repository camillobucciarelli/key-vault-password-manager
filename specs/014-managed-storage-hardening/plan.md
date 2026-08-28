# 014 — Implementation plan

## Delivery strategy

Seven slices in the order the tasks already impose, because they are genuinely
sequential: the root must move before the perimeter can follow it, names must be
opaque before the registry becomes the only place a name lives, and the mapping
must be keyed by identity before a root change can be survived. Each slice
compiles and tests before the next.

FR-9 is the simplifying constraint that makes this affordable: there is no
migration, no reconciler and no compatibility shim. A non-conforming on-disk
state is an explicit error. That removes the largest source of complexity a
storage-layout change usually carries, and it is only acceptable because the app
has no users beyond the developer. Nothing in this plan reads a previous layout.

This plan changes where files live, what they are called and how their metadata
is protected. It changes no vault byte, no KDBX parsing, no safe-writer
algorithm, no `DatabasePathMutex` and no sync decision.

**Owner agent**: `senior-flutter-dev`
**Platform agents**: `senior-apple-dev` (T013 do-not-back-up attribute on
iOS/macOS, T003 simulator run), `senior-android-dev` (T013 `allowBackup` /
`backup_rules`), `senior-windows-dev` (T012 ACL outcome — Dart has no `chmod` on
Windows, so the owner-only assertion there is an ACL check, not a mode check).
`senior-tester` owns the T016 regression gate. Linux needs no native change.

## Constitution Check

Checked against `.specify/memory/constitution.md` v1.1.2. No gate is violated and
no complexity waiver is needed.

| Principle | Verdict | Evidence |
| --- | --- | --- |
| I — Secrets never leak into the shell | PASS | This spec strictly narrows the surface: the three metadata files stop being plaintext (T008), on-disk names stop disclosing which vaults exist and which key belongs to which vault (T004–T006), the desktop root leaves a third-party-synced directory (T001), and the global `cachedKeyFilePath` second source of truth is deleted (T014). The metadata key never enters logs, `props` or `toString`; T008 asserts no plaintext name or path survives in the file bytes. |
| II — Clean architecture layering holds | PASS | The root resolver is a `core/utils` helper; encryption lives at the four data sources that own those files; `DatabaseSessionCoordinator` only loses a fallback branch. No new BLoC, no new coordinator, no presentation change beyond reading the display name from the registry instead of the basename. |
| III — Design tokens | N/A | No restyle; no colour, type or metric is touched. |
| IV — Pixel fidelity | PASS | No new screen and no layout change. T005 changes the *source* of the displayed name, not its rendering; the existing goldens must stay byte-identical, which is the assertion. |
| V — Accessibility floor | N/A | No layout, contrast, target or animation change. |
| VI — Copy preserved unless a spec marks a change | PASS | No user-facing string changes. The one new surface is the FR-5 empty-list state; its copy is added, and every existing literal — including the create-database wizard and the Italian browser-setup labels — stays byte-identical. The wizard's `new_database.kdbx` default stops being an on-disk name but remains the displayed default. |
| VII — Destructive operations ask first and back up | PASS | FR-9 makes a previous layout unopenable by design, and that is stated in the spec as an accepted outcome, not smuggled in. No code path in this plan deletes a user file: import still copies and never modifies or removes the original (FR-1). T012 extends `0600` to backups rather than weakening them. |
| VIII — Ship the smallest thing | PASS | One root helper replacing six independent resolutions, not a storage abstraction layer. AES-GCM from `pointycastle`, already transitive via `kdbx`, rather than a new crypto dependency. The metadata key goes in the existing `SecureDataSource` rather than a parallel keystore service. No developer-only plaintext sidecar for debugging. |
| IX — Verification is local | PASS | T016 runs `flutter analyze` and the full `flutter test` before commit, including `safe_vault_writer_harness_test.dart` and the spec 008 `database_writer_inventory_test.dart`. `pubspec.yaml: version:` is untouched. |

### Phase 0 / Phase 1 artifacts

`research.md` is not generated: `spec.md` carries no `[NEEDS CLARIFICATION]`
marker and its two open questions are explicitly delegated to this plan, which
answers them below (AES-GCM via the already-transitive `pointycastle`; the
existing `databases`/`keys` split is kept).

`data-model.md`, `contracts/` and `quickstart.md` are not generated. The
constitution requires `data-model.md` only for specs 008 and 009. This spec adds
no entity — it re-keys one map, renames files on disk and wraps three existing
JSON documents in a cipher. The requirements and acceptance criteria in `spec.md`
are already the contract, and the validation commands live in T016 and below.

## Answers to the spec's open questions

**Which primitive encrypts the metadata files.** AES-256-GCM from `pointycastle`,
which is already in `pubspec.lock` as a transitive dependency of `kdbx`. It is
promoted to a direct dependency — the same pattern and the same justification
already used for `xml` in spec 008: code in `lib/` must not import a package it
does not declare. No new package enters the dependency tree. `crypto ^3.0.7`
cannot serve here: it is hashing and HMAC only, with no symmetric cipher.

GCM rather than CBC because these files are decrypted on every start and a
tampered ciphertext must fail loudly rather than yield garbage that the JSON
decoder then half-parses. File shape: a version byte, a random 12-byte nonce, the
ciphertext and the tag. A fresh nonce per write, never reused.

**One directory or two.** The existing `databases` / `keys` split is kept. It
leaks nothing once names are opaque — the directory a file sits in says only that
it is a database or a key, which the app must know anyway — and merging them
would touch `MobileFileStorage` for no security gain.

## Dependency and safety gates

1. **Spec 008 invariants are untouched.** `SafeVaultFileWriter`'s algorithm,
   `DatabasePathMutex` and the writer inventory are not modified by this plan.
   T012 extends an existing permission behaviour to two more file kinds; it adds
   no writer. If `database_writer_inventory_test.dart` changes, that is a
   deliberate decision taken with the spec 008 owner, not a silent update.
2. **Do not weaken a guard to make it pass.** T002 moves the perimeter with the
   root. `mobile_file_storage_guard_qa_test.dart`,
   `mobile_file_storage_guard_bypass_qa_test.dart` and
   `portable_path_symlink_qa_test.dart` are updated in the same change, never
   skipped or relaxed. These three need Developer Mode or an elevated shell on
   Windows because they build a `/var`→`/private/var` divergence with
   `Link.create`; that is an existing environmental constraint, not a new one.
3. **`PortablePath` must keep working across the move.** The new root is stored
   portably exactly as today. `documentsRoot()` is one of the resolution sites
   (see below) and must move with the others, or an encoded path and its decode
   base will disagree.
4. **Never regenerate the metadata key over existing ciphertext.** T007 creates it
   once. An absent key with ciphertext present is the FR-5 state, not a reason to
   mint a new key — doing so would silently destroy the registry.
5. **No plaintext fallback, ever.** FR-5 is a defined state: empty list, manual
   re-selection. There is no code path that writes an unencrypted metadata file.
6. **Order against 010 and 013.** 010 re-keys and re-shapes `sync_mappings.json`
   (`providerId`/`remoteFileId`, schema v2); 014 re-keys the same file by database
   identifier and encrypts it. Both touch `SyncMetadataDataSourceImpl`. Whichever
   lands second rebases onto the other and re-runs the mapping migration matrix.
   013 owns remote identity and the local copy's remote binding; 014 owns local
   placement, naming and permissions. Neither respecifies the other.

## Migration-inventory correction

The spec lists five resolution sites under *Problem and current state*. A search
of the tree finds **six**:

```text
lib/core/utils/mobile_file_storage.dart:283
lib/features/password_manager/data/datasources/sync_metadata_data_source.dart:217
lib/features/password_manager/data/datasources/database_registry_local_data_source.dart:74
lib/features/password_manager/data/datasources/database_security_local_data_source.dart:82
lib/features/password_manager/data/datasources/local_data_source.dart:88
lib/core/utils/portable_path.dart:83            <-- not listed in spec.md
```

`PortablePath.documentsRoot()` resolves the root independently and is the join
base for `decode`. If it keeps pointing at the documents directory while the five
others move, every encoded path decodes against the wrong base. T001 must route
it through the same helper, and the inventory is regenerated at implementation
time rather than trusted from this list.

## Phase 1 — one managed root (T001–T003)

### Add

- `lib/core/utils/managed_storage_root.dart` — the single resolver.
  `getApplicationSupportDirectory()` on macOS, Windows and Linux;
  `getApplicationDocumentsDirectory()` on Android and iOS, where the documents
  directory is already the app-private container. `path_provider` maps that to
  Application Support, `AppData\Roaming` and `~/.local/share` respectively, so no
  per-platform branching beyond the one native/desktop split is needed.
- `test/core/utils/managed_storage_root_test.dart` — asserts the resolved root
  per platform (AC-6).

### Change

All six sites above call the helper. None resolves a root of its own afterwards;
a guard test asserts `getApplicationDocumentsDirectory` appears in exactly one
production file.

### Perimeter widening — a deliberate consequence

`SafeVaultFileWriter.isAppPrivateDocumentsRoot` (`safe_vault_file_writer.dart:156`)
returns `true` only for iOS, Android and sandboxed macOS today, and `false` for
unsandboxed macOS, Windows and Linux — because on those platforms the root *is*
the user's real `~/Documents`, where a `vault.kdbx -> ~/Dropbox/vault.kdbx`
symlink is an ordinary setup that must keep being written through (HIGH-2).

Moving the desktop root into the application data directory removes that reason.
Application Support / AppData / `~/.local/share` are app-owned: a symlink there
can only have been planted, exactly as on iOS and Android. So T002 does not merely
follow the root — it **extends** the perimeter to macOS, Windows and Linux, and
the HIGH-2 carve-out is retired with its justification recorded in the same
change. This is the security win of Phase 1 and must be stated in the diff, not
discovered later.

### T003

`PortablePath` must still encode the new root portably; the iOS
container-relocation harness (`integration_test/ios_portable_paths_qa_test.dart`)
is manual and on-demand — see the `manual-qa-harnesses` skill for its procedure —
and is re-run on a simulator after the move, with the outcome recorded.

## Phase 2 — opaque names (T004–T006)

### Change

- `lib/features/password_manager/data/services/database_import_service.dart:517`
  (`saveKeyFile`) — stops preserving the picked file's basename.
- `lib/features/password_manager/domain/usecases/create_database_usecase.dart:115`
  — stops writing `database.key`.
- `lib/features/password_manager/presentation/screens/create_database_screen.dart:32`
  — `new_database.kdbx` stays the *displayed* default and stops being the on-disk
  name.
- `lib/core/utils/mobile_file_storage.dart` — allocates the opaque name.
- every UI and export path that reads a basename to display a name now reads the
  registry record (T005).

The on-disk identifier is a fresh 128-bit random value, base32 or hex, with no
extension. It is **not** derived from the database identifier, the display name,
or any value stored in the metadata files — otherwise the key-to-database
association is reconstructable from a directory listing plus one leaked registry
field, which is exactly what AC-1 forbids. The database's opaque name and its key
file's opaque name are independent draws; the binding between them lives only in
the encrypted security profile.

Export and download output keep the human-readable name: that is the point at
which the user needs it, and it is outside managed storage.

Gate: AC-1 test lists the managed directory and asserts no readable name, no
`.kdbx`, no `.key`, and no value shared with any registry field.

## Phase 3 — encrypted metadata (T007–T009)

### Add

- `lib/features/password_manager/data/datasources/metadata_cipher.dart` —
  AES-256-GCM seal/open over bytes. No key material in `toString` or `props`.
- the metadata key accessor on the existing `SecureDataSource`
  (`secure_data_source.dart`), alongside the spec 011 per-database master-password
  entries. No biometric gate (FR-4): the key lists databases, it never unlocks
  one, and gating it would put a prompt in front of the database list while
  protecting nothing the vault credentials do not already protect.
- `pubspec.yaml` — `pointycastle` promoted from transitive to direct.

### Change

- `database_registry_local_data_source.dart`, `database_security_local_data_source.dart`,
  `sync_metadata_data_source.dart` and `local_data_source.dart` read and write
  through the cipher. Their JSON shape is unchanged; only the bytes on disk are.

### FR-5 state

Secure store unavailable → the registry read returns empty, the app starts, the
database list is empty, no plaintext file is written, and the key is not minted
over existing ciphertext. Recovery is manual re-selection of the vault files.
Tested with the store stubbed unavailable (AC-5).

Gate: AC-2 asserts no plaintext database name or path in the bytes of all three
files; AC-5 covers the unavailable-store path.

## Phase 4 — mapping identity (T010–T011)

### Change

- `sync_metadata_data_source.dart:38-75` — `getMapping`, `upsertMapping` and
  `removeMapping` key by database identifier instead of `mapping.databasePath`.
- the orchestrator and repository call sites that pass a path today.

Gate: AC-7 — a mapping resolves after the managed root path changes within one
run. Coordinate with 010's mapping schema work per safety gate 6.

## Phase 5 — permissions and backup exclusion (T012–T013)

`SafeVaultFileWriter` already applies the target's permission bits to a backup
*before* any content is written (`safe_vault_file_writer.dart`, T108 backup), so a
`0600` vault never has a world-readable copy on disk. The real gap is narrower
than FR-7 reads: **key files** written through `saveKeyFile` never pass through
mode enforcement, and a backup of a file that is not already `0600` inherits that
looser mode.

T012 therefore applies `defaultVaultMode` (`0600`) at key-file creation and makes
the backup floor explicit rather than inherited. macOS and Linux assert the mode
directly. Windows has no `chmod` in `dart:io`, so its owner-only outcome is
recorded as an ACL check by `senior-windows-dev`, per AC-3.

T013 sets the do-not-back-up attribute on iOS/macOS and the Android
`allowBackup` / `backup_rules` — native work, owned by the Apple and Android
specialists.

## Phase 6 — single key source (T014)

### Change

- `lib/features/password_manager/data/datasources/local_data_source.dart:17,27,40,44`
  — `keyFilePathKey` / `cachedKeyFilePath` removed entirely.
- `lib/features/password_manager/presentation/coordinators/database_session_coordinator.dart:793-806`
  — the fallback branch is deleted; the per-database security profile's
  `keyFilePath` is the only source.
- `test/features/password_manager/data/portable_path_regression_qa_test.dart:146`
  — its `cachedKeyFilePath` case is removed rather than left asserting a field
  that no longer exists.

Gate: a database with no profile key does not silently borrow another database's
key (T014), and AC-8 — `cachedKeyFilePath` appears nowhere in `lib/`.

## Phase 7 — closing checks (T015–T016)

### Targeted commands

```bash
dart format lib test
flutter analyze
flutter test test/core/utils/managed_storage_root_test.dart
flutter test test/core/utils/mobile_file_storage_guard_qa_test.dart
flutter test test/core/utils/mobile_file_storage_guard_bypass_qa_test.dart
flutter test test/features/password_manager/data/portable_path_symlink_qa_test.dart
flutter test test/features/password_manager/data/portable_path_regression_qa_test.dart
flutter test test/features/password_manager/data/datasources
flutter test test/features/password_manager/data/services/safe_vault_file_writer_test.dart
flutter test test/features/password_manager/data/services/database_writer_inventory_test.dart
flutter test test/tool/safe_vault_writer_harness_test.dart
flutter test test/features/password_manager/presentation/coordinators
flutter test test/goldens
flutter test
```

### Guard searches

```bash
rg -n 'getApplicationDocumentsDirectory' lib
rg -n 'cachedKeyFilePath|keyFilePathKey' lib test
rg -n '\.kdbx"|\.key"|new_database\.kdbx|database\.key' lib
```

Expected: the first returns exactly one production file, the new root helper; the
second returns nothing; the third returns only display defaults and export
filenames, never a managed on-disk name.

T015 additionally asserts no migration or reconciler path was added and that a
non-conforming on-disk state raises an explicit error — FR-9 is verified as an
absence, so it needs its own assertion rather than being assumed.

## Rollout sequencing

- Ship as one change. There is no intermediate build: a build with the new root
  and the old perimeter, or with encrypted metadata and a path-keyed mapping, is
  broken by construction.
- No migration means no backout that reconciles state. Backing this out means
  reverting the commit and accepting that vaults created by the new version are
  unopenable by the old one — the symmetric statement of FR-9, and acceptable for
  the same reason.
- Because the previous layout is not read, the developer's existing local vaults
  must be exported before the change lands and re-imported after. This is a
  human step, not code.

## Deferred implementation plan

User-owned storage (security-scoped bookmarks, Android SAF persisted grants) is
rejected on the platform matrix, not deferred — see `spec.md` §Rejected
alternative. Web has no managed storage and is out of scope. A developer-only
plaintext read path for debugging opaque names is added only if it proves
necessary, and never as a sidecar file.
