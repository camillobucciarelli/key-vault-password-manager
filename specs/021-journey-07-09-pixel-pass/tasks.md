# Tasks: Pixel pass on journeys 07–09

Closed by a manual review on the running desktop build (2026-08-31), fixed and
shipped in v0.4.0 via PR #180. No screenshot pass is planned.

- [x] T001 Journey 07 — sync status and Drive connection: hero rebuilt on `surface`/`surfaceNested`, provider tile, contextual link action in the file picker, real local checksum (`lib/features/password_manager/presentation/widgets/sync/sync_status_hero.dart`, `remote_file_row.dart`, `screens/vault/vault_sync.part.dart`)
- [x] T002 Journey 08 — sync conflict resolution: conflict sheet pane-aware on desktop, dispatch on captured bloc (`screens/vault/vault_sync.part.dart`)
- [x] T003 Journey 09 — import / export: reviewed by hand, reachable from Settings › Backups & import and from the disconnected sync hero export pill; no change needed
