# Contract — passkey material across the platform bridges

The one rule behind every section: **the PEM is written only to a sealed
cache or handed to an in-process signer; it never appears in a plaintext
cache, a method-channel error, a native-messaging frame or a log line.**

## Publish payload (Dart → Apple / Android channel `publishCredentials`)

Existing entry object gains an optional key:

```
"passkey": {
  "rpId": "example.com",
  "credentialId": "<base64url>",
  "userHandle": "<base64url>" | null,
  "username": "alice",
  "privateKeyPem": "-----BEGIN PRIVATE KEY-----…",
  "algorithm": "ES256" | "EdDSA" | "RS256",
  "be": true, "bs": true
}
```

Only `usable` passkeys are sent. An entry with a passkey and an empty password
is **published** (today's `entry_without_password_skipped` warning must not
drop it). The channel result adds `passkeyPublishedCount`.

Sealed record: same object. Plaintext metadata: `hasPasskey`, `passkeyRpId`,
`passkeyCredentialId` only.

## Apple extension

| Callback | Behaviour |
|---|---|
| `prepareCredentialList(for:requestParameters:)` | list = metadata where `passkeyRpId == requestParameters.relyingPartyIdentifier` and (`allowedCredentials` empty or contains `passkeyCredentialId`). Empty list → `cancelRequest(.credentialIdentityNotFound)` (FR-017, scenario 4). |
| `provideCredentialWithoutUserInteraction(for: ASPasskeyCredentialRequest)` | `cancelRequest(.userInteractionRequired)` — always (FR-015). |
| `prepareInterfaceToProvideCredential(for: ASPasskeyCredentialRequest)` | `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` → on success read sealed secret → `PasskeyAssertionBuilder.assert(secret, clientDataHash, rpId)` → `completeAssertionRequest(using: ASPasskeyAssertionCredential(userHandle:relyingParty:signature:clientDataHash:authenticatorData:credentialID:))`. Cancel → `cancelRequest(.userCanceled)`. Missing secret → `cancelRequest(.credentialIdentityNotFound)`. |
| `Info.plist` | `ASCredentialProviderExtensionCapabilities` adds `ProvidesPasskeys = true`. |

`PasskeyAssertionBuilder` is one Swift file compiled into both extension
targets. It never logs the key; the `Logger` calls it makes carry rpId only.

## Android provider

| Element | Behaviour |
|---|---|
| Manifest | `<service android:name=".autofill.KeyVaultCredentialProviderService" android:permission="android.permission.BIND_CREDENTIAL_PROVIDER_SERVICE" android:exported="true">` with `android.service.credentials.CredentialProviderService` intent filter and `android.credentials.provider` meta-data. Enabled state toggled at runtime for API ≥ 34 (plan D9). |
| `onBeginGetCredentialRequest` | For each `BeginGetPublicKeyCredentialOption`: parse `requestJson.rpId` and `allowCredentials`; filter metadata; one `PublicKeyCredentialEntry(context, username, pendingIntent, option, displayName=title)` per match. No matches → empty response (the platform shows nothing). |
| `PasskeyAuthActivity` | `BiometricPrompt` with `BIOMETRIC_STRONG | DEVICE_CREDENTIAL`, every time. Success → secret → assertion → `PublicKeyCredential(json)` → `PendingIntentHandler.setGetCredentialResponse(intent, GetCredentialResponse(...))`. Cancel → `setGetCredentialException(GetCredentialCancellationException())`. Missing → `NoCredentialException`. |
| `clientDataJSON` | `{type:"webauthn.get", challenge, origin, androidPackageName?}` where origin is `callingAppInfo.origin` when set (browser) else `android:apk-key-hash:<base64url sha256 of signing cert>`. |
| Method channel | `getPasskeyProviderAvailability` → `{available: bool, apiLevel: int}` for the settings row. |

## Desktop

### Native messaging (extension ↔ host), protocol v2, new type

Request:
```
{ "type": "passkeyAssert", "requestId": "…", "origin": "https://example.com",
  "rpId": "example.com", "challenge": "<base64url>",
  "allowCredentials": ["<base64url>", …], "userVerification": "required"|"preferred"|"discouraged" }
```
Response (success):
```
{ "type": "passkeyAssert", "requestId": "…", "ok": true,
  "credentialId": "<base64url>", "authenticatorData": "<base64url>",
  "signature": "<base64url>", "userHandle": "<base64url>"|null,
  "clientDataJSON": "<base64url>" }
```
Response (no match / declined / unavailable):
```
{ "type": "passkeyAssert", "requestId": "…", "ok": false,
  "reason": "no_credential" | "declined" | "vault_locked" | "rp_mismatch" | "unsupported_algorithm" }
```
An old host answers `{"type":"error","code":"unsupported_type"}`; the
extension then calls the original `navigator.credentials.get`. `hello`
advertises `passkeyAssertV1` in `capabilities` only when the app bridge
descriptor lists it. Payload cap: existing 64 KiB. `challenge`,
`allowCredentials` are added to `_sensitiveRequestKeys` so they are never
echoed in error frames.

### Host ↔ app (`/passkey-assert` on the reveal bridge)

Same body as the native request plus the bridge token header the other
endpoints use. The app: checks session unlocked; checks `rpId` against
`origin` (effective domain or registrable suffix); finds usable passkeys;
shows the in-app confirmation naming site and username (FR-015); signs;
answers the same shape as above. Never returns a PEM under any path.

### Page ↔ extension (MAIN world ↔ isolated world)

`window.postMessage({ kv: nonce, kind: "passkey-get", options })` from the
wrapper; `{ kv: nonce, kind: "passkey-get-result", ok, credential | null }`
back. The wrapper resolves the original promise with a
`PublicKeyCredential`-shaped object (see research R12) or falls through to
the browser. `navigator.credentials.create` is **not** wrapped in this spec.
