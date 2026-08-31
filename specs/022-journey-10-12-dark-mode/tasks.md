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
- [ ] T004 Field diff (sync conflict sheet) — selection border `#ffc6a5` 2 px, tints at the `800` step (`vault_sync.part.dart`)
  No golden covers the conflict sheet in dark — device only.
- [x] T005 Settings with Light / Dark / System selector — selector states readable, surfaces one ramp step up (`presentation/screens/vault/vault_settings.part.dart`)
  Verified on `settings_390x844_dark`: auto-lock warning tint/text correct, rows on `#474238`, toggles readable. Theme selector itself sits below the fold of the golden — confirm on device.
- [ ] T006 Browser extension popup in dark — `desktop/browser_extension/` uses the dark token mapping
  No golden; open the extension popup with the OS in dark.

## Phase 2: Every other journey, against the dark rule

- [ ] T007 Journeys 01–02 — database picker, create, unlock, biometric gate, lock/privacy overlay
  Partly verified on `db_recent_*_dark`, `db_welcome_390x844_dark`, `unlock_password_390x844_dark`, `unlock_biometric_gate_390x844_dark`. Create flow, lock/privacy overlay: device only. (The square placeholders in the `db_*` goldens are the icon font missing from that harness — same in light, not a dark finding.)
- [ ] T008 Journeys 05–06 — entry editor (errors, discard, generator), recycle bin, duplicates, record info
  Editor verified on `vault_wide_editor_in_pane_1024x768_dark`. Generator, discard, bin, duplicates, record info: device only.
- [ ] T009 Journeys 07–09 — sync hero connected/disconnected, Drive picker, import/export, CSV preview/outcome
  Sync hero verified on `sync_disconnected_390x844_dark`, `sync_success_390x844_dark`. Drive picker, import/export, CSV: device only.
- [ ] T010 Journeys 10–12 — autofill enablement, browser setup, change master password, backups
  No dark golden for any of these — device only.
- [ ] T011 Dialogs, sheets, snackbars, tooltips and focus rings in dark — shadow `rgba(0,0,0,.5)`, focus ring `accent` 2 px visible on `#474238`

## Phase 3: Golden inventory

- [ ] T012 List the root layouts still lacking a 1024×768 dark golden (entry detail, health, settings, sync at least) in this file and decide per screen: record it, or name the widget assertion that replaces it (Constitution IV)
  Known today: no 1024×768 dark golden for entry detail, health, settings, sync, unlock, editor generator.

## Findings

(none from the golden review of 2026-08-31 — remaining tasks need the running app)
