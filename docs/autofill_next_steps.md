# Autofill Next Steps

This repository now includes:
- Android Autofill Service integration (runtime enabled from app UI).
- iOS shared snapshot bridge via `UserDefaults(suiteName:)` in App Group.
- iOS Credential Provider extension scaffold in `ios/CredentialProviderExtension/`.

## iOS wiring in Xcode (required)

The extension scaffold files are present, but the Xcode target is not yet attached to
`ios/Runner.xcodeproj`. Complete the following in Xcode:

1. Open `ios/Runner.xcworkspace`.
2. Add a new target: `Credential Provider Extension`.
3. Set target bundle id (example):
   - `dev.camillobucciarelli.passwordManager.CredentialProviderExtension`
4. Add these files to the extension target:
   - `ios/CredentialProviderExtension/CredentialProviderViewController.swift`
   - `ios/CredentialProviderExtension/SharedAutofillStore.swift`
   - `ios/CredentialProviderExtension/Info.plist`
   - `ios/CredentialProviderExtension/CredentialProviderExtension.entitlements`
5. Enable App Group capability for both targets with:
   - `group.dev.camillobucciarelli.passwordManager`
6. Build and run on device, then enable AutoFill in iOS Settings.

## Desktop browser implementation plan

For desktop browser fill support, implement in this order:

1. Native Messaging host (local bridge service from app vault to browser extension).
2. Chromium extension (Chrome/Edge) with login form detection and fill command.
3. Firefox manifest adaptation.
4. Safari Web Extension adaptation.

Security baseline:
- Require explicit user unlock before exposing any credential.
- Match credentials by exact domain, with explicit confirmation on mismatch.
- Never persist plaintext vault passwords in browser extension storage.
