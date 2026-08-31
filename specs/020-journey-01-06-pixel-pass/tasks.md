# Tasks: Entry detail — one home for attachments

**Input**: `spec.md`, `plan.md`. One user story (US1: the vault user finds
attachments in one place and can add the first one). Tests required
(Constitution IV, IX). Paths repo-relative.

## Phase 1: Implementation (US1)

- [x] T001 [US1] Replace the conditional `More` block with a permanent `Attachments` section (label, count including `0`, `Manage` pill dispatching `_EntryAction.attachments`) in `lib/features/password_manager/presentation/screens/vault/vault_entry_detail.part.dart`; drop `_MoreChip` if nothing else uses it
- [x] T002 [US1] Remove the `Attachments` item and the spec-019 C-04-04 comment from the detail header `PopupMenuButton` in `lib/features/password_manager/presentation/screens/vault/vault_entry_detail.part.dart` (keep `Move`, `Duplicate`, `Record info`, `Delete`; keep the enum value)
- [x] T003 [P] [US1] Append the FR-006 amendment text to FR-011 in `specs/018-desktop-vault-navigation/spec.md`

## Phase 2: Tests

- [x] T004 [US1] Update the pinned menu inventories to the amended FR-011 in `test/features/password_manager/presentation/screens/vault/vault_navigation_mobile_characterisation_test.dart` (menu offers `Move`, `Delete`; body offers `Attachments` + `Manage`) and `test/features/password_manager/presentation/screens/vault/vault_detail_dismissal_test.dart` (650/1024 parity)
- [x] T005 [US1] Route the `Attachments closes at $width` cases through the section's `Manage` in `test/features/password_manager/presentation/screens/vault/vault_operation_context_test.dart`; add `Manage` to the inventory in `test/features/password_manager/presentation/screens/vault/vault_action_inventory_test.dart`
- [x] T006 [US1] Add widget tests in `test/features/password_manager/presentation/screens/vault/vault_entry_detail_actions_test.dart`: at 390 and 1024 a record with 0 attachments shows `0` and `Manage` opens the `Attachments` dialog; a record with 2 shows `2`; `Attachments` text appears once with the overflow open (SC-001, SC-002)
- [x] T007 [US1] Re-record `test/goldens/entry_detail_hidden_390x844_light.png`, `entry_detail_hidden_390x844_dark.png`, `entry_detail_hidden_1024x768_light.png`, `entry_detail_revealed_totp_390x844_light.png`, `entry_detail_revealed_totp_390x844_dark.png`; confirm by eye the only diff is the new section (SC-003)
  Done: ten goldens changed, not five — every golden that renders the detail body shows the section (`entry_biometric_gate`, `entry_copy_confirmation`, `entry_weak_reused` at 390 light; `vault_wide_record_selected_1024x768_{light,dark}`). Checked by eye at 390 and 1024 light.

## Phase 3: Close

- [x] T008 Mark C-04-04 resolved by spec 020 in `specs/_design/CONFORMANCE_AUDIT.md`; run `flutter analyze`, `flutter test`, `flutter test test/goldens --test-randomize-ordering-seed=$RANDOM`; tick these boxes; `PROJECT_NUMBER=2 tool/sync_spec_project.sh`

## Dependencies

T001 → T002 (never remove the menu item before the section exists — that is the
dead end spec 019 hit). T003 parallel. T004–T006 after T002. T007 after T001.
T008 last.
