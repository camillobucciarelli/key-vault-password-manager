# 003 — Tasks

Ordered tasks only. No parallel flags: architecture contracts and shared flow
files overlap.

## Phase 1 · Freeze copy and fix architecture boundary

- [x] **T1** Extract/review user-facing literals from all eight files named in
      spec Copy contract into `test/fixtures/strings_003_before.txt` before any
      source edit. Record approved additions separately in fixture header;
      secrets/test-only strings are excluded. Lock disposition: reuse/modify
      `RecentDatabasesSection`, `DatabaseItemTile`, `DatabaseActionMenu`; remove
      none. Add comparison helper/test.
- [x] **T2** Add domain `DatabaseFileRepository`, `DatabaseSessionRepository`,
      import-transaction/removal-mode models and `CreateDatabaseUseCase`.
      `DatabaseImportService` implements file port; new data repository composes
      existing local/secure data sources. Rewire all three concrete password-
      manager DI files. Make `DatabaseSessionCoordinator` final/concrete, remove
      its single-implementation contract, inject it directly into BLoCs, and move
      FilePicker/file/hash/KDBX/key/session operations behind domain ports/use
      cases. Tests fake those ports/use cases, not coordinator. Add direct dev
      `analyzer` dependency and
      `database_session_coordinator_imports_test.dart`: parse every import
      directive, normalize relative/package-qualified URIs, reject `data` path
      segments, `dart:io`, Flutter, picker, crypto, KDBX/platform packages and
      non-allowlisted internal/external imports. Named test must pass before T3.
      Run existing coordinator/BLoC tests and analyze.
- [x] **T3** Add `DatabaseAccessFailure` and tests mapping absent database,
      invalid/unsupported selection, `KdbxCorruptedFileException`/
      `KdbxInvalidFileStructure`, absent key file and `KdbxInvalidKeyException`.
      Mapping lives in use cases/data implementations; coordinator/UI never sees
      raw `e.toString()`. Run use-case tests and analyze.
- [x] **T4** Add `DatabaseSelectionItem`, `DriveAccountSummary` and
      `DrivePickerData`. Extend `DatabaseSyncRepository`/implementation and
      `DriveAuthService` for mobile account plus exact desktop fallback without
      changing OAuth scopes. Add repository/auth tests and run analyze.

## Phase 2 · Coordinator and BLoC behaviour

- [x] **T5** Change coordinator results from path lists to C-1 metadata aggregated
      through domain ports from registry/security/sync/file existence. Do not
      read, decrypt or persist item counts. Update coordinator and selection-BLoC
      tests; rerun named coordinator-import test and analyze.
- [x] **T6** Add coordinator-owned locate sequencing and BLoC event: accept only a
      missing item, validate through file port, require stored hash match when
      present, update registry path + sync mapping atomically, preserve ID/
      security, then continue to unlock. Test match, mismatch, invalid file and
      rollback; run coordinator/BLoC tests.
- [x] **T7** Harden duplicate sequencing: Keep both unique/new ID; Replace dated
      backup + metadata preservation + rollback; Use existing and cancel discard
      stage. All I/O remains in ports/use cases. Test four results and injected
      failure rollback.
- [x] **T8** Add non-secret `CreateDatabaseStep` to selection state/events.
      Coordinator requests `CreateDatabaseUseCase` and owns transition policy;
      password stays only in screen controllers and redacted final event. Test
      next/back/cancel/submit failure and assert BLoC state/`toString` contains no
      password. Run tests, named coordinator-import test and analyze.
- [x] **T9** Replace unlock `isLoading` contract with C-4 phase/failure/progress.
      Emit decrypting before use-case await, keep progress null, disable duplicate
      events, map typed failures and preserve success/biometric paths. Test phase
      ordering, no percentage, blocked back/submit and all failures.

## Phase 3 · Database selection UI

- [x] **T10** Extract `welcome_screen.dart`; rebuild selection root/header and
      tablet layout from FR-1 using C-1 items. Modify/reuse
      `RecentDatabasesSection`; keep snapshotted strings except approved welcome/
      metadata additions. Add mobile/tablet semantics tests.
- [x] **T11** Modify/reuse `DatabaseItemTile` for source/biometric/sync metadata,
      active and missing states. Modify/reuse `DatabaseActionMenu` for ≥44
      Open/Export/Remove plus conditional Locate. Do not add `DatabaseRow`. Wire
      Locate to T6 and test unchanged existing events/copy and mismatch safety.
- [x] **T12** Rebuild Drive loading/empty picker with row geometry,
      `DrivePickerData` account/fallback, create+upload and switch account. Add
      tests for mobile email, desktop fallback, empty and skeleton/no-spinner.
- [x] **T13** Extract generic `KvBottomSheet.show<T>` from 002 confirmation
      styling on this second use. Add invalid/corrupt basename sheets and typed
      duplicate sheet. Assert no CSV action, consequence copy, one typed decision
      dispatch, and null/back staged cleanup.
- [x] **T14** Add `create_database_screen.dart` with three coordinator-driven
      steps and existing `CreateDatabaseCredentials` route result. Extract
      `KvPillButton` only on second 003 use; keep step bars/strength meter private.
      Delete old dialog only after callers compile. Test back/cancel/result and no
      secret in state.

## Phase 4 · Unlock UI

- [x] **T15** Rebuild unlock base for `ready`: 66/r24 feature square, title 32,
      input 56, primary action, inline links, reduced-motion 280 ms entry, desktop
      card ≤600 with existing explanatory strings hidden but unchanged. Add
      geometry/copy tests.
- [x] **T16** Render typed failures under relevant field/surface: existing
      credential message, explicit missing-key action, separate corrupt/missing
      database treatment. Never display raw path/exception. Add placement tests
      proving credential errors are field descendants, not snackbars.
- [x] **T17** Render key-selected, biometric-gate and C-4 decrypting states.
      Decrypting is indeterminate/static under reduced motion, no percent/ETA,
      no cancel claim, no back or second submit. Add semantics tests.
- [x] **T18** Replace biometric setup dialog with typed Face ID sheet and rename
      key manager to `internal_key_file_manager_sheet.dart`, preserving
      `InternalKeyFileManagerResult`, actions and snapshotted strings. Delete old
      dialog after callers compile; test null/success/deleted-selection results.

## Phase 5 · Exact verification

- [x] **T19** Add omitted-axis widget matrix from spec: all named state families
      under dark theme with semantic-role/contrast assertions; selection at
      599/600/1024 and centred unlock ≤600; credential/database error placement;
      invalid/corrupt/duplicate/key-manager/Face-ID sheet geometry on root
      navigator in light and dark. Run screen tests.
- [x] **T20** Add `database_and_unlock_test.dart` with exact 22 filenames/states.
      Use bundled fonts, DPR 1, text scale 1, `en_US`, fixed clocks/account data
      and disabled external I/O. Generate/review only those images; assert count
      22.
- [x] **T21** Compare post-change copy snapshot; only approved list may differ.
      Run scoped `showDialog` command; it must be empty. Run named coordinator-
      import architecture test; it must pass and report every parsed URI. Do not
      widen dialog sweep into vault files governed by 002.
- [x] **T22** Run analyze and all targeted plan commands, then manual matrix. Run
      full `flutter test` once before commit.
