part of '../vault_screen.dart';

// spec-019 FR-013 / C-03-12: `_SyncStatusStrip` — the database status card —
// was deleted here, and on 2026-08-31 its last remnant followed: the `⋮`
// overflow (`_SyncStripMenuButton` + `_VaultSettingsSheet`) that had carried
// the card's actions. Everything it offered lives in a first-class
// destination now — sync in Sync, lock/change/hygiene in Settings, exports in
// Backups & import, the generator in the editor.
