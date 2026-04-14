# Background Drive Sync — Design Spec

**Date:** 2026-04-14  
**Status:** Approved

## Problem

After the first Google Drive connection, every subsequent vault open blocks the user:

1. `_onInitializeVault` runs `_refreshSyncState` (Drive network check) in sequence with vault loading — vault entries don't appear until Drive check completes.
2. After init, `SyncCurrentDatabaseNow` fires and shows a visible `syncStatus: syncing` indicator.

Goal: vault appears immediately from local file; all Drive activity happens fully in the background.

## Approach

Vault-first init: remove Drive check from the init path entirely. A new `BackgroundDriveSync` event handles all Drive activity after the vault is already visible.

## Architecture

### Init flow change (`_onInitializeVault`)

**Before:**
```
isLoading: true
→ _refreshSyncState (Drive check, network)
→ _reload (read kdbx)
→ _loadRecycleBinEntries
→ if connected+linked+autoSync → add(SyncCurrentDatabaseNow)
```

**After:**
```
isLoading: true
→ _preloadDriveStateFromLocalMapping()   // zero network, reads local DB
→ _reload (read kdbx)
→ _loadRecycleBinEntries
→ add(BackgroundDriveSync())             // queued after vault is visible
```

`_preloadDriveStateFromLocalMapping` reads `syncMetadataDataSource.getMapping()` synchronously. If a mapping exists, emits `isDriveLinked: true`, `syncStatus: idle`, `isSyncing: false`. No `isDriveConnected` decision is made yet (unknown until Drive check). This avoids a "disconnected → connected" flash in the header.

### New event: `BackgroundDriveSync`

Handler `_onBackgroundDriveSync`:

1. `_refreshSyncState` — Drive check via `attemptLightweightAuthentication` (already non-blocking on mobile; desktop reads stored token).
2. If `isDriveConnected && isDriveLinked && autoSyncEnabled`:
   - Emit `isSyncing: true` (subtle icon only, `syncStatus` stays `idle`)
   - Call `_performSync(emit, silentIfConflict: true)` **without** emitting `syncStatus: syncing`
   - On `SyncNowSuccess`:
     - If `!state.isSaving` → `_reload` silently
     - Else → emit `isSyncReloadPending: true`
   - On `SyncNowConflict` → emit `syncStatus: conflict` (existing banner flow)
3. Emit `isSyncing: false`
4. On any auth/network error:
   - If token expired or Drive unreachable → emit `isDriveConnected: false`, `isSyncing: false`
   - No popup, no dialog — Drive icon shows "disconnected"

### `isSyncReloadPending` flush

When `isSyncReloadPending: true` and any other event already calls `_reload` (e.g. entry save → `_onUpdateVaultEntry` → `_reload`), pass `clearSyncReloadPending: true` in `copyWith` to clear the flag. No extra logic needed.

### `_performSync` change

Add `bool emitSyncingStatus = true` parameter. Background path passes `false` — suppresses the `syncStatus: syncing` emit. Manual "sync now" still passes `true` (existing behaviour unchanged).

## VaultState additions

| Field | Type | Default | Purpose |
|---|---|---|---|
| `isSyncing` | `bool` | `false` | Background sync in progress — drives subtle header icon |
| `isSyncReloadPending` | `bool` | `false` | Sync updated local file but reload was deferred (user was saving) |

`copyWith` gains `bool clearSyncReloadPending = false`.

## UI

- `isSyncing: true` → small spinning Drive icon in vault header (replace existing `syncStatus: syncing` visual)
- `isSyncing: false` + `isDriveConnected: false` (when mapping existed) → Drive icon with offline badge
- All existing conflict/error banners unchanged

## Error handling

| Scenario | Behaviour |
|---|---|
| Network absent during background sync | Silent: `isSyncing: false`, `syncStatus: idle` |
| Token expired (mobile) | `isDriveConnected: false`, Drive icon shows "disconnected" |
| Token expired (desktop PKCE) | Same — no interactive OAuth from background |
| `isSyncReloadPending` + user saves entry | Save's `_reload` clears the flag |
| Conflict detected in background | `syncStatus: conflict` + existing non-blocking banner |
| Manual `ConnectGoogleDrive` (first time / reconnect) | Unchanged — interactive OAuth flow |

## Out of scope

- Periodic background sync (timer-based) — existing `_scheduleAutoSync` debounce unchanged
- Token refresh retry logic
- Conflict resolution UI changes
