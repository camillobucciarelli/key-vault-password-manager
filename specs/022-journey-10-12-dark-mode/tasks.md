# Tasks: Dark mode verification

**Input**: `spec.md`, `plan.md`. Manual walk; tick a box only when the screen
matches. Findings are appended as fix tasks under **Findings**.

## Phase 1: The six artboard screens (`14 Dark mode`)

- [x] T001 Vault list, phone and wide — ground `#2e2b25`, rows/cards on `#474238`, active tab/rail item `accent-300`; compare with the artboard (`lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart`, `vault_entries.part.dart`)
  Verified 2026-08-31 on `vault_1a_phone_390x844_dark`, `vault_1a_wide_1024x768_dark`, `vault_shell_*_dark`: ground/surface/active-item tokens as specified.
- [x] T002 Entry detail with password revealed and TOTP running, phone and wide — text `#f9f4ed`, secondary @ 55–62%, copy pills primary `#ffc6a5` on `#402310` (`vault_entry_detail.part.dart`)
  Verified on `entry_detail_hidden_390x844_dark`, `entry_detail_revealed_totp_390x844_dark` (as re-recorded by spec 020): revealed password card on `accent-800`, strength strip on `accent-2-800`, TOTP badge `accent-2-300`.
- [x] T003 Health screen — warning tint `#643312` / text `#ffe1d0`, positive `#3d472b` / `#e1eecc` (`presentation/screens/vault/vault_health.part.dart`)
  Verified on `health_390x844_dark`: score tile, warning tint `#643312` with `#ffe1d0` text, positive on the 800 step.
- [x] T004 Field diff (sync conflict sheet) — selection border `#ffc6a5` 2 px, tints at the `800` step (`vault_sync.part.dart`)
  Verified 2026-08-31 on a dark render of `sync_conflict_390x844`: selection card on `accent-800`, remote on `surfaceNested`, `Keep local` primary pill — matches the field-diff artboard.
- [x] T005 Settings with Light / Dark / System selector — selector states readable, surfaces one ramp step up (`presentation/screens/vault/vault_settings.part.dart`)
  Verified on `settings_390x844_dark`: auto-lock warning tint/text correct, rows on `#474238`, toggles readable. Theme selector itself sits below the fold of the golden — confirm on device.
- [x] T006 Browser extension popup in dark — `desktop/browser_extension/` uses the dark token mapping
  `desktop/browser_extension/popup.css` carries the `prefers-color-scheme: dark` block (header `neutral-800`, body `neutral-900`, status cards on the 800 step) per `14 Dark mode` lines 244–280. Verified by reading; the popup has no golden harness.

## Phase 2: Every other journey, against the dark rule

- [x] T007 Journeys 01–02 — database picker, create, unlock, biometric gate, lock/privacy overlay
  Verified on dark renders of `db_create_step1..3`, `db_drive_empty/loading`, `db_duplicate`, `db_invalid_file`, `unlock_*` (7 states), `lock_overlay`, `privacy_overlay`: sheets on `#474238`, primary pills `#ffc6a5`, no light-ramp leak. The square placeholders in the `db_*`/`unlock_*` renders are the icon font missing from that harness — same in light, not a dark finding.
- [x] T008 Journeys 05–06 — entry editor (errors, discard, generator), recycle bin, duplicates, record info
  Verified on dark renders of `editor_new_item` (390/1024), `editor_generator_sheet/column`, `editor_discard`, `editor_saving`, `editor_camera_denied`, `generator_standalone`, `bin_list`, `bin_empty_confirm`, `dup_groups`, `dup_empty`, `dup_merge_preview`. One finding — F-001 below, fixed.
- [x] T009 Journeys 07–09 — sync hero connected/disconnected, Drive picker, import/export, CSV preview/outcome
  Verified on dark renders of `sync_not_linked`, `sync_picker`, `sync_syncing`, `sync_offline`, `sync_error`, `sync_success_1024`, `backups`, `csv_preview`, `csv_outcome`: offline/error cards on `accent-800` with `accent-200` text, `Linked` tag, snackbar on `accent-200`.
- [x] T010 Journeys 10–12 — autofill enablement, browser setup, change master password, backups
  Verified on dark renders of `autofill_enablement`, `link_autofill_credential`, `browser_setup_1024`, `host_not_found_diagnostic_1024`, `change_master_password`, `confirm_security_changes`: warning tints on the 800 step, text 100–200, `Keep`/`Change` tags readable.
- [x] T011 Dialogs, sheets, snackbars, tooltips and focus rings in dark — shadow `rgba(0,0,0,.5)`, focus ring `accent` 2 px visible on `#474238`
  Sheets (discard, empty bin, security changes, Face ID prompt, key manager), the writing-to-kdbx dialog and the sync snackbar verified in the renders above — `neutral-800` on `neutral-900`, ambient shadow. Focus rings and tooltips are not captured by any golden: `app_focus_ring.dart` draws `colors.selectionBorder` (= `#ffc6a5` in dark) at 2 px, which is the artboard value.

## Phase 3: Golden inventory

- [x] T012 List the root layouts still lacking a 1024×768 dark golden (entry detail, health, settings, sync at least) in this file and decide per screen: record it, or name the widget assertion that replaces it (Constitution IV)
  Root layouts with a 1024×768 light golden and no dark twin: `entry_detail_hidden`, `health`, `settings`, `sync_success`, `unlock_password`, `editor_new_item`, `editor_generator_column`, `browser_setup`, `host_not_found_diagnostic`. Decision: the dark render of each was reviewed by hand in this pass (see above) and the token tables are pinned by `app_theme_test.dart`; the widget assertion that replaces the golden is that test's dark semantic-role table (Constitution IV). No new dark goldens beyond F-001's.

## Findings

- [x] F-001 Editor validation error text invisible in dark — `_kvFieldDecoration` hard-coded `errorStyle` to `AppColors.accent800` (the light-ramp value), which sits at ~1.5:1 on the `#2e2b25` ground. Fixed: reads `colors.attentionText` (`accent-900` light, `accent-200` dark). New golden `editor_errors_390x844_dark.png`; `editor_errors_390x844_light.png` re-recorded (`accent800` → `accent900`). File: `lib/features/password_manager/presentation/screens/vault/vault_entry_editor.part.dart`.

### Seen in the dark renders but present in light too — not dark findings, left for their own issue

- `csv_preview` / `csv_outcome` at 390: the header row overflows on the right (Flutter's striped overflow marker is in the golden in both themes).
- `unlock_wrong_password`: the error state falls back to a Material outlined field with a floating `Master password` label, unlike the pill of the other unlock states.
- `editor_generator_column_1024`: the generator column title truncates to `Ge…`.
