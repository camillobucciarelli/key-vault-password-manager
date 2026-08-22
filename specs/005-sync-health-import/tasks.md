# 005 — Tasks

## Health

- [x] **T1** `vault_health_report.dart`: `VaultHealthReport { int score,
      List<HealthCategory> categories }`, `HealthCategory { kind, count,
      List<String> entryIds }`. Kinds: `weak`, `reused`, `old`, `duplicates`,
      `unmatchable`.
- [x] **T2** `vault_health_service.dart`: compute the five categories from the
      in-memory entry list. Weak = entropy < 40 bits (reuse the existing
      evaluator). Reused = same **sha256 of the password** across ≥ 2 entries —
      never map plaintext. Old = `lastPasswordChangedAt` older than the threshold,
      with an injected `now`. Duplicates = `VaultDuplicateService` groups.
      Unmatchable = empty url **and** empty username. Score per plan §Health score.
- [ ] **T3** `VaultState.healthReport`, computed on unlock and after every write;
      `Equatable` props limited to score + counts.
- [ ] **T4** `vault_health.part.dart`: score circle 64 (Caprasimo 22), five
      `KvListRow` categories each with a Caprasimo 18 count before the chevron.
      Tapping a category opens the filtered list (duplicates → T6).

## Sync

- [ ] **T5** `sync_status_hero.dart`: radius 26, padding 20, 52 circle, title
      Caprasimo 20, meta 12.5, key/value list 12.5 `space-between`. One rendered
      state per `DatabaseSyncStatus` value.
      - `disconnected`: security-model explanation **before** any auth call —
        encrypted `.kdbx` only, Google sees nothing decryptable, scope requested.
      - connected-not-linked: create new (literal "A new file will be created in
        My Drive root.") or pick existing, plus an auto-sync `KvSwitch`.
      - `syncing`: `KvSpinner` 34 + copy.
      - `success`: last sync, local checksum mono 11 truncated, unlink.
      - `error`: message + persistent "Reconnect Google Drive" action.
      - `conflict`: opens the sheet (T7).
- [x] **T6** Recent-activity list under `success` (adopted proposal): compact rows
      padding 11/14 from existing sync metadata.
- [x] **T7** Offline state (adopted proposal): shown only for connection-level
      failures (`SocketException`), never for an HTTP error status.
- [ ] **T8** `remote_file_row.dart`: name, `modifiedTime`, size, plus an
      already-linked warning `KvTag` when the file id appears in another
      `DatabaseSyncMapping`.
- [x] **T9** Conflict sheet: two version cards radius 20 padding 14/16 with a 40
      square, checksum mono 11, `remoteModifiedTime`; Keep local / Use remote /
      Cancel with which-side labels. `SyncConflictResolution` semantics unchanged.

## Duplicates & recycle bin

- [x] **T10** `vault_duplicates.part.dart`: group card radius 24 padding 14,
      inner rows radius 16 padding 11/13, Keep = `MergePreview.primary`,
      Merge = `secondary`, "Some data will be copied" strip (radius 14, padding
      9/12, 12 px) shown when `hasAnythingToCopy`. Merge action full-width,
      padding 11, radius 999.
- [x] **T11** Merge-preview sheet listing **exactly** `willCopyNotes`,
      `willCopyOtp`, `customFieldKeysToCopy`, `willCopyAttachments`.
- [x] **T12** No-duplicates empty state.
- [x] **T13** `vault_recycle_bin.part.dart`: Restore inline, Delete permanently in
      the row overflow, `Empty bin (n)` screen action — strings unchanged. Empty
      state + confirm sheet with the existing literals.

## Import / export

- [x] **T14** CSV import preview: Detected format / Rows found / Valid records /
      Skipped rows + the Avoid duplicates toggle.
- [x] **T15** `vault_csv_import_service.dart`: expose the per-row skip reason it
      already computes (`SkippedRow { index, reason }`).
- [x] **T16** CSV outcome screen listing a reason per skipped row (adopted
      proposal).
- [x] **T17** `vault_backups.part.dart`: the three existing export actions,
      behaviour unchanged.

## Verify

- [x] **T18** `vault_health_service_test.dart`: fixed fixture → fixed score;
      reuse detection works on hashes; injected `now` drives the "old" category.
- [x] **T19** `sync_status_test.dart`: iterate `DatabaseSyncStatus.values`, assert
      a non-empty hero for each; assert no auth call on first `disconnected` render.
- [x] **T20** Merge-preview test: exactly four flags rendered.
- [x] **T21** String diff: recycle-bin literals unchanged.
- [x] **T22** 17 goldens per the spec table.
- [x] **T23** `flutter analyze` clean, `flutter test` green.
