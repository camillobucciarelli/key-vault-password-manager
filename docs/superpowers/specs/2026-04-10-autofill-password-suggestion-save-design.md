# Autofill: Password Suggestion & Save on iOS and Android

**Date:** 2026-04-10  
**Status:** Approved

---

## Overview

Implement proper password suggestion (fill) and password saving on iOS and Android, plus KeePass-standard field compliance for precise app/website matching. iOS target raised to 17 to unlock native save and strong-password suggestion APIs.

---

## 1. Password Generator Service (Domain Layer)

**Goal:** Extract the existing private password generation logic from the presentation layer into a reusable domain service.

**New file:** `lib/features/password_manager/domain/services/password_generator_service.dart`

- `PasswordGeneratorOptions` — public value object with fields: `length`, `includeUppercase`, `includeLowercase`, `includeDigits`, `includeSymbols`. Mirrors current `_PasswordGeneratorOptions.defaults()`.
- `PasswordGeneratorService.generate(PasswordGeneratorOptions)` — pure function, no side effects. Moves `_generateSecurePassword` logic verbatim.
- Registered in `get_it` as a singleton.
- `vault_dialog_password.part.dart` removes the private copies and calls the injected service.
- `AndroidAutofillCoordinator` and `IosAutofillSnapshotCoordinator` receive the service via constructor injection.

---

## 2. KeePass Field Standards

**Goal:** Fields used for app/website matching must be interoperable with KeePass2Android, KeePassium, Strongbox, and AuthPass.

### Recognized custom field keys (matching — read)

| Key pattern | Convention |
|---|---|
| `KPH: androidPackage` | KeePass2Android / KeePass Helper |
| `KPH: iosBundle` | KeePassium |
| `androidPackage` (legacy) | previous app version |
| keys containing `package`, `bundle`, `androidapp`, `iosapp` | broad fallback |

### URL schemes (matching — read + write)

| Scheme | Example | Used by |
|---|---|---|
| `androidapp://` | `androidapp://com.example.app` | Strongbox, AuthPass |
| `iosbundleid://` | `iosbundleid://com.example.app` | Strongbox |

### Changes

1. **`VaultAutofillMatcher._extractPackageIdentifiers`**
   - Adds extraction from URLs with `androidapp://` and `iosbundleid://` schemes.
   - Explicitly checks for `KPH: androidPackage` and `KPH: iosBundle` key names.

2. **`AndroidAutofillCoordinator._buildSaveCustomFields`**
   - Saves `KPH: androidPackage` instead of `androidPackage`.
   - Matcher retains fallback to old key for backward compatibility.

3. **`SharedAutofillCredential`** (Swift)
   - Adds `customFields: [String: String]` to carry bundle ID data to the credential provider extension.

4. **`IosAutofillDataSource.saveSnapshot`**
   - Includes `customFields` in the JSON payload (key-value map).

---

## 3. iOS: Fix Matching + ASCredentialIdentityStore + iOS 17 Save

### 3.1 Deployment target

`ios/Podfile` and Xcode project: raise `IPHONEOS_DEPLOYMENT_TARGET` from `13.0` to `17.0`.

### 3.2 ASCredentialIdentityStore registration

**`IosAutofillSnapshotCoordinator.syncSnapshot`** — after saving the snapshot JSON, also registers all entries as `ASPasswordCredentialIdentity` objects:

```swift
// called from Dart via MethodChannel after saveSnapshot
func registerCredentialIdentities(entries: [SharedAutofillCredential])
```

- For each entry with a non-empty URL: create `ASPasswordCredentialIdentity(serviceIdentifier: ASCredentialServiceIdentifier(identifier: url, type: .URL), user: username)`
- For each entry with a bundle ID in `customFields["KPH: iosBundle"]`: create identity with `type: .domain` using the bundle ID as identifier.
- Call `ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities)` atomically.
- This makes credentials appear in the QuickType keyboard bar without the user opening the extension.

**New MethodChannel method:** `registerIdentities` — called by `IosAutofillSnapshotCoordinator` after every `saveSnapshot`.

### 3.3 CredentialProviderViewController rewrite

**`prepareCredentialList(for: serviceIdentifiers)`**
- Load all credentials from `SharedAutofillStore`.
- For each `serviceIdentifier` (URL or bundle ID), score and filter credentials using the same logic as `VaultAutofillMatcher` (domain matching + bundle ID matching via `customFields`).
- Present the filtered, ranked list to the user. If no matches, show all credentials.
- Do not complete immediately — show the picker UI.

**`provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity)`**
- Match by `serviceIdentifier.identifier` (domain/bundle) AND `credentialIdentity.user` (username).
- If found, complete with `ASPasswordCredential`. If not found, cancel with `userInteractionRequired`.

### 3.4 iOS 17 password saving

> **Note:** The `CredentialProviderExtension` runs in a separate OS process — it cannot call MethodChannel on the main Flutter app. Communication uses the shared App Group (`UserDefaults(suiteName:)`).

**New `ASCredentialProviderViewController` override (iOS 17):**

```swift
@available(iOS 17.0, *)
override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) { }
```

Save flow:
1. iOS calls the extension with the new credential (username + password + service URL).
2. Extension shows a minimal confirmation UI (entry title + username + masked password). No Flutter involvement.
3. On user confirmation, extension writes the credential to a `pending_autofill_saves` key in shared `UserDefaults` (App Group) as a JSON array.
4. Extension calls `extensionContext.completeRequest(withSelectedCredential:)`.
5. When the main app next resumes, `IosAutofillSnapshotCoordinator.syncSnapshot()` reads and clears `pending_autofill_saves`, then calls `VaultKdbxService.createEntry()` for each pending credential.
6. After persisting, `syncSnapshot` re-runs to update the snapshot and identity store.

**`SharedAutofillStore`** gains a `readPendingSaves() -> [SharedAutofillCredential]` and `clearPendingSaves()` method.

**`IosAutofillSnapshotCoordinator`** gains `_processPendingSaves()` called at the start of each `syncSnapshot`.

### 3.5 Strong password suggestion (iOS 17)

The extension runs in its own process and cannot call into Flutter. Password generation is implemented natively in Swift within the extension.

**New `CredentialProviderPasswordGenerator.swift`** (inside the extension target):
- Mirrors `PasswordGeneratorService` defaults: 20 chars, uppercase + lowercase + digits + symbols.
- Uses `SecRandomCopyBytes` for cryptographic randomness.
- No external dependencies.

When iOS requests a new password via `ASPasswordCredentialRequest`:
- Generate a password using `CredentialProviderPasswordGenerator`.
- Return `ASPasswordCredential(user: "", password: generatedPassword)`.
- iOS presents it as a suggested strong password in the QuickType bar / credential UI.

---

## 4. Android: Strong Password Suggestion

**Goal:** When Android detects a "new password" field (autofill hint `AUTOFILL_HINT_NEW_PASSWORD`), offer a generated strong password as the first dataset.

### 4.1 Detection

In `AndroidAutofillCoordinator._handleFillRequest`:
- Inspect `metadata` for fill hints indicating a new-password context.
- `flutter_autofill_service` exposes `AutofillMetadata` — check if any hinted field matches `newPassword` semantics.

### 4.2 Generated password dataset

If a new-password context is detected:
- Call `PasswordGeneratorService.generate(PasswordGeneratorOptions.defaults())`.
- Prepend a `PwDataset(label: 'Genera password sicura', username: '', password: generatedPassword)` to the datasets list.
- The save flow (`_handleSaveRequest`) already handles saving the chosen credential back to the vault — no changes needed there.

### 4.3 No changes to enableIMERequests

Keep `enableIMERequests: false` — this workaround for the `NoSuchElementException` crash in the plugin remains in place.

---

## 5. Data Flow Summary

```
[Vault unlocked]
    │
    ├─ iOS: syncSnapshot()
    │       ├─ saveSnapshot JSON → UserDefaults (App Group)
    │       └─ registerIdentities → ASCredentialIdentityStore
    │
    └─ Android: handlePendingRequest() on resume
            ├─ fill → PwDataset[] (+ generated password if new-password field)
            └─ save → VaultKdbxService.createEntry / updateEntry

[iOS Credential Provider Extension]
    ├─ prepareCredentialList → filter by serviceIdentifier → show picker
    ├─ provideCredentialWithoutUserInteraction → match domain+user → fill
    └─ prepareInterface(forUserInteractionIfNeeded) [iOS 17]
            ├─ save credential → MethodChannel → VaultKdbxService.createEntry
            └─ new password request → generatePassword → ASPasswordCredential
```

---

## 6. Files Changed

| File | Change |
|---|---|
| `lib/.../domain/services/password_generator_service.dart` | **New** — extracted generator |
| `lib/.../domain/services/vault_autofill_matcher.dart` | Add `androidapp://`, `iosbundleid://`, `KPH:` key support |
| `lib/.../data/services/android_autofill_coordinator.dart` | `KPH: androidPackage` on save; strong password dataset |
| `lib/.../data/services/ios_autofill_snapshot_coordinator.dart` | Call `registerIdentities` after snapshot; add `saveCredential` |
| `lib/.../data/datasources/ios_autofill_data_source.dart` | Include `customFields` in JSON; add `registerIdentities`, `saveCredential`, `generatePassword` methods |
| `lib/.../presentation/screens/vault/vault_dialog_password.part.dart` | Use injected `PasswordGeneratorService` |
| `lib/injection_container.dart` (+ DI files) | Register `PasswordGeneratorService` |
| `ios/Runner/AppDelegate.swift` | Handle `registerIdentities`, `saveCredential`, `generatePassword` methods |
| `ios/CredentialProviderExtension/SharedAutofillStore.swift` | Add `customFields` to `SharedAutofillCredential` |
| `ios/CredentialProviderExtension/CredentialProviderViewController.swift` | Full rewrite: proper matching, iOS 17 save, strong password |
| `ios/CredentialProviderExtension/CredentialProviderPasswordGenerator.swift` | **New** — Swift-native password generator for the extension process |
| `ios/Podfile` | `platform :ios, '17.0'` |

---

## 7. Out of Scope

- Passkey (WebAuthn) support
- iOS 13–16 save flow (dropped per design decision)
- Android inline IME suggestions (blocked by plugin crash)
- UI settings for password generator options in autofill context
