# 002 — Tasks

Ordered tasks only. No `[P]`: destination migrations share files and assembler
directives.

## Phase 1 · Typed contract

- [ ] **T1** Snapshot title/body/action literals for the exact 19 FR-7 calls into
      `test/fixtures/vault_dialogs_002_before.txt`; assert fixture row count 19.
      Add final concrete `VaultShellRouter`, sealed DTOs, never-reused
      `VaultOperationId` and session-local completers. Do not add a router
      interface/mock implementation; test the real class through collaborators
      and widget harness. Secret-bearing DTOs use redacted `props`/`toString`.
      Run fixture/router tests and analyze.
- [ ] **T2** Implement terminal handling for success, back, cancel, accepted
      destination change, route/sheet removal, build failure, parent close and
      router dispose. Require exact live operation ID, ignore stale completion,
      cancel child operations, remove session before completing, and clear all
      surface/result/builder/secret refs in `finally`. Test every terminal path,
      stale old-ID completion during a later operation, nested confirmation,
      duplicate completion and no result logging. Run router tests and analyze.
- [ ] **T3** Implement exhaustive sealed `presentationFor(surface, width)` switch
      returning route/sheet/pane exactly per FR-6. Route uses
      `MaterialPageRoute`; sheet uses root `showModalBottomSheet`; pane never
      pushes. Parameterize every surface at 390 and 1024 and assert existing
      platform transition builders. Run router tests and analyze.

## Phase 2 · Shell and responsive behaviour

- [ ] **T4** Rework `vault_shell.part.dart` with private tab-bar/rail/layout
      widgets, four destinations and stable Health/Sync/Settings placeholders.
      Implement FR-2 geometry, semantics and reset-on-new-shell behaviour. Run
      analyze and shell tests.
- [ ] **T5** Implement width arithmetic exactly at 599/600/707/708/1023/1024:
      single pane where required, folder only from 1024, no shadow, 1 px dividers,
      min detail 300. Add overflow-free geometry tests and run them.
- [ ] **T6** Add mobile back, compact-pane back, dirty-form destination guard and
      latched resize behaviour. Test mobile→desktop and desktop→mobile with an
      in-progress draft and unresolved future; neither may lose state or complete
      during resize. Run analyze and router/shell tests.

## Phase 3 · Serial surface migration

- [ ] **T7** Migrate Vault entry detail/editor, generator, metadata, attachments
      and recycle-bin calls in `vault_dialogs.part.dart`, `vault_entries*.part.dart`,
      `vault_dialog_password.part.dart` and `vault_recycle_bin.part.dart`. Replace
      private/raw results with typed DTOs without changing copy or BLoC events.
      Run affected widget flows and analyze.
- [ ] **T8** Migrate Health duplicate and merge-preview calls in
      `vault_duplicates.part.dart`; preserve merge result semantics and backup
      confirmation. Run affected tests and analyze.
- [ ] **T9** Migrate Drive link, remote picker and sync conflict in
      `vault_dialogs.part.dart`; then move only those cohesive declarations to
      `vault_sync.part.dart` and add its part directive. Run sync/result tests and
      analyze before continuing.
- [ ] **T10** Migrate database settings, master-password, key-file and CSV/import
      surfaces in `vault_navigation.part.dart`/`vault_shared.part.dart`; then move
      Settings-owned declarations to `vault_settings.part.dart` and add its part
      directive. Preserve all current return values and copy. Run affected tests
      and analyze.
- [ ] **T11** Move confirmation sheet content from `vault_dialogs.part.dart` to
      `vault_confirmations.part.dart`; keep shared helpers in
      `vault_navigation_support.part.dart` only when at least two destination
      parts call them. Add part directive and run analyze/router tests. Do not
      split files to satisfy a byte count.

## Phase 4 · Verify

- [ ] **T12** Add and run `vault_surface_migration_matrix_test.dart`: exactly 19
      named FR-7 cases, each asserting 390/1024 presentation kind, typed
      success/null result, frozen title/body/action copy and listed BLoC event or
      coordinator callback. Matrix must pass before any zero-dialog sweep.
- [ ] **T13** Add exact four shell goldens using spec-001 harness and review diffs.
- [ ] **T14** Run vault-only `showDialog` sweep from spec AC-8; result must be
      empty. Do not modify database selection/unlock or unrelated presentation
      files to widen this gate.
- [ ] **T15** Run `flutter analyze`, router tests, 19-row matrix, shell tests and
      shell goldens.
      Manually execute route/pane/back/resize/confirmation matrix from plan.
      Run full `flutter test` once before commit.
