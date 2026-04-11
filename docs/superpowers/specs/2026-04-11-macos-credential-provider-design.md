# macOS Credential Provider Extension — Design Spec

**Date:** 2026-04-11
**Status:** Approved

---

## Overview

Add a macOS `ASCredentialProviderExtension` embedded in the macOS app target. The extension integrates with Safari and the system autofill picker (macOS 14 Sonoma+), providing the same credential fill experience available on iOS — without requiring the browser extension or native messaging host setup.

---

## Requirements

- macOS deployment target raised to **14.0** (from 10.15)
- Works in Safari and any app that uses `ASAuthorizationController` autofill
- Primary data source: existing `DesktopAutofillBridgeService` HTTP bridge (app must be running and unlocked)
- Fallback data source: UserDefaults App Group snapshot (same format as iOS, written by Flutter app)
- Auto-fills the best match silently; shows a credential list only when the match is ambiguous
- No new network access — bridge is loopback only (`127.0.0.1`)

---

## Architecture

```
macOS Credential Provider Extension
         │
         ▼
  BridgeClient.swift
  ┌─────────────────────────────────────────┐
  │ 1. Read ~/.keyvault_autofill/bridge.json │
  │ 2. POST 127.0.0.1:PORT/v1/find          │
  │    (timeout 1.5s, Bearer token)          │
  │ 3. On failure → nil                      │
  └─────────────────────────────────────────┘
         │ nil
         ▼
  SharedAutofillStore.swift
  ┌─────────────────────────────────────────┐
  │ UserDefaults(suiteName: appGroupId)      │
  │ Key: "autofill_entries_json"             │
  │ Same JSON format as iOS snapshot         │
  └─────────────────────────────────────────┘
         │
         ▼
  MacCredentialProviderViewController.swift
  ┌─────────────────────────────────────────┐
  │ Score + sort credentials                 │
  │ Best match logic:                        │
  │  • 1 match with score > 0  → silent fill │
  │  • Top score ≥ 140         → silent fill │
  │  • Otherwise               → show list   │
  └─────────────────────────────────────────┘
```

---

## Deployment Target Change

- `macos/Runner.xcodeproj`: `MACOSX_DEPLOYMENT_TARGET` → `14.0` (Debug, Release, Profile)
- Reason: `ASCredentialProviderExtension` requires macOS 14

---

## New Xcode Target

**Target name:** `CredentialProviderExtension`
**Bundle ID:** `dev.camillobucciarelli.kdbxKeyVault.CredentialProviderMac`
**Extension point:** `com.apple.authentication-services-credential-provider-ui`
**Embedded in:** macOS Runner app

### Files (`macos/CredentialProviderExtension/`)

| File | Description |
|---|---|
| `MacCredentialProviderViewController.swift` | Main VC — orchestrates bridge + snapshot + fill/list logic |
| `BridgeClient.swift` | Reads `bridge.json`, makes HTTP POST, returns credentials or nil |
| `SharedAutofillStore.swift` | UserDefaults App Group read (identical logic to iOS) |
| `CredentialListView.swift` | SwiftUI credential picker (identical to iOS, NSHostingController embedding) |
| `Info.plist` | Extension manifest |
| `CredentialProviderExtension.entitlements` | App Group entitlement |

---

## BridgeClient

```swift
struct BridgeClient {
  private let bridgeConfigPath: URL  // ~/.keyvault_autofill/bridge.json
  private let timeout: TimeInterval = 1.5

  func findCredentials(for url: String, limit: Int = 10) async -> [SharedAutofillCredential]?
  // Returns nil on any failure (timeout, bad token, app not running, file absent)
}
```

**bridge.json format** (already defined, read-only):
```json
{
  "host": "127.0.0.1",
  "port": 54321,
  "token": "base64url_token",
  "expiresAtEpochMs": 1712345678000,
  "version": 1
}
```

Token expiry check: if `expiresAtEpochMs` is in the past, skip bridge and go straight to snapshot (token will be invalid).

---

## MacCredentialProviderViewController

### `prepareCredentialList(for serviceIdentifiers:)`

1. Fetch credentials: try bridge → fallback snapshot
2. If empty → `cancelWithError(.credentialIdentityNotFound)`
3. Score all credentials against `serviceIdentifiers`
4. Apply best-match logic:
   - Single match with score > 0 **or** top score ≥ 140 → `completeRequest(withSelectedCredential:)` immediately
   - Otherwise → `showCredentialList(sorted, bestMatchId:)` via `NSHostingController`

### `provideCredentialWithoutUserInteraction(for:)`

1. Fetch credentials: try bridge → fallback snapshot
2. Find credential matching both `credentialIdentity.user` and service identifier
3. Match found → `completeRequest`
4. No match → `cancelWithError(.userInteractionRequired)`

### `provideCredentialWithoutUserInteraction(for credentialRequest:)` (iOS 17 / macOS 14 API)

Delegates to the `ASPasswordCredentialIdentity`-based method for password requests; cancels with `.failed` for unsupported types.

### `prepareInterfaceToProvideCredential(for:)`

Called after `userInteractionRequired`. Fetches credentials and shows the full credential list (no auto-fill shortcut here — user interaction was explicitly required).

### `prepareInterfaceForExtensionConfiguration()`

Calls `completeExtensionConfigurationRequest()` immediately (no config UI needed).

---

## Matching Logic

Reuses the same scoring rules already in the iOS extension:
- Exact domain match: 140 pts
- Subdomain/parent: 110 pts
- Registrable domain: 80 pts
- Bundle ID via `androidapp://` / `iosbundleid://`: 140 pts
- KPH custom fields (`kph: iosbundle`, `kph: androidpackage`): 140 pts

Credentials sorted: score desc → title asc.

---

## Flutter Side Changes

### Platform check in `IosAutofillSnapshotCoordinator`

The coordinator currently restricts to iOS. Change the platform check to include macOS:

```dart
bool get _isSupportedPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
         defaultTargetPlatform == TargetPlatform.macOS;
}
```

This makes the Flutter macOS app write and maintain the same JSON snapshot in the App Group UserDefaults, which the extension reads as fallback.

### macOS Runner Entitlements

Add to `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.application-groups</key>
<array>
  <string>group.dev.camillobucciarelli.kdbxKeyVault</string>
</array>
```

### App Group Registration

The App Group `group.dev.camillobucciarelli.kdbxKeyVault` must be registered in the Apple Developer portal for the macOS app ID and the extension bundle ID.

---

## Credential List UI

`CredentialListView.swift` is SwiftUI and identical to the iOS version. On macOS, it is embedded via `NSHostingController` instead of `UIHostingController`. The view itself requires no changes.

---

## Error Handling

| Condition | Behavior |
|---|---|
| Bridge not available (app closed) | Falls back to snapshot silently |
| Bridge timeout (>1.5s) | Falls back to snapshot |
| Bridge returns 401 | Falls back to snapshot (token rotated) |
| Snapshot empty or missing | `cancelWithError(.credentialIdentityNotFound)` |
| Best match found | Silent `completeRequest` |
| Ambiguous matches | Show `CredentialListView` |
| User cancels list | `cancelWithError(.userCanceled)` |

---

## Out of Scope

- Passkey support (passwords only)
- Saving new credentials from the extension
- Firefox/Chrome support (handled by browser extension)
- macOS versions < 14

---

## File Checklist

**New files:**
- `macos/CredentialProviderExtension/MacCredentialProviderViewController.swift`
- `macos/CredentialProviderExtension/BridgeClient.swift`
- `macos/CredentialProviderExtension/SharedAutofillStore.swift`
- `macos/CredentialProviderExtension/CredentialListView.swift`
- `macos/CredentialProviderExtension/Info.plist`
- `macos/CredentialProviderExtension/CredentialProviderExtension.entitlements`

**Modified files:**
- `macos/Runner.xcodeproj/project.pbxproj` — new target, deployment target 14.0, embed extension
- `macos/Runner/DebugProfile.entitlements` — add App Group
- `macos/Runner/Release.entitlements` — add App Group
- `lib/features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart` — enable macOS
