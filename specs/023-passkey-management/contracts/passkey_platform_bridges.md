# Contract — passkey material across the platform bridges

The one rule behind every section: **the PEM is written only to a sealed
cache or handed to an in-process signer; it never appears in a plaintext
cache, a method-channel error, a native-messaging frame or a log line.**

## Publish payload (Dart → Apple / Android channel `publishCredentials`)

Existing entry object gains a key, always present, empty for an ordinary
login. A list, not a single object: one entry can hold several passkeys
(KeePassDX writes `_1`, `_2`, … groups) and a single block would silently
drop all but one.

```
"passkeys": [{
  "rpId": "example.com",
  "credentialId": "<base64url, unpadded>",
  "userHandle": "<base64url, unpadded>" | null,
  "username": "alice",
  "privateKeyPem": "-----BEGIN PRIVATE KEY-----…",
  "algorithm": "ES256" | "EdDSA" | "RS256",
  "be": true, "bs": true
}]
```

`credentialId` and `userHandle` are re-encoded from the stored bytes rather
than passed through: KeePassXC omits base64url padding, and the extension
compares `credentialId` against `allowedCredentials`, so both sides must
spell it the same way.

Only `usable` passkeys are sent. An entry with a passkey and an empty password
is **published** (today's `entry_without_password_skipped` warning must not
drop it). The channel result adds `passkeyPublishedCount`.

Sealed record: same objects. Plaintext metadata: `hasPasskey` and, per
passkey, `passkeyRpId` and `passkeyCredentialId` only — never the PEM.

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
descriptor lists it. Payload cap: existing 64 KiB.

`challenge` and `allowCredentials` are **not** added to
`_sensitiveRequestKeys`: that set is a rejection list — a request carrying any
of its keys is refused outright — and this request type has to carry both, so
listing them would refuse every sign-in. They are never echoed anyway, because
`nativeHostErrorResponse` writes a code and a fixed message and never the
request payload.

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
the browser.

`mediation: "conditional"` and `mediation: "silent"` are passed straight to the
original `get`. Conditional mediation is passkey autofill: login pages fire it
on load with no user gesture, and it is specified to resolve only without
interrupting the user. Answering it with the in-app confirmation would pop a
dialog on every page load, and holding it for the 90s app budget would keep the
browser's own autofill UI waiting that long.

### Page ↔ extension, registration (US3, added after this contract was written)

`navigator.credentials.create` **is** wrapped, by
`passkeyCreate`/`/passkey-create`, mirroring the sign-in path:

```
{ "type": "passkeyCreate", "origin": "…", "rpId": "example.com",
  "challenge": "<base64url>", "username": "…",
  "userHandle": "<base64url, unpadded>" | "" }
```
```
{ "type": "passkeyCreate", "ok": true, "credentialId": "<base64url>",
  "attestationObject": "<base64url>", "clientDataJSON": "<base64url>",
  "publicKeyCose": "<base64url>" }
```

`userHandle` is the relying party's own `user.id`, forwarded unchanged through
every hop to `PasskeyGenerator`. An authenticator that substitutes one of its
own breaks two things: a discoverable sign-in hands the site a handle it never
issued, so it cannot resolve the credential to an account; and
`VaultKdbxService.createPasskey` detects a clash by `(rpId, userHandle)`, so a
confirmed replacement would add a second credential instead. It is **dropped,
never truncated**, when it exceeds 88 characters (the base64url form of
WebAuthn's 64-byte ceiling): half a handle is a different handle. Absent is
legitimate — a registration may carry no `user.id` — and the app then falls
back to the credential id.

`keyFilePath` is not on the wire: the app reads the active database's own
security profile at write time (spec 014 FR-8), the same source `VaultBloc`
reads, so a key-file-protected vault opens for a browser-initiated write
exactly as for an in-app one.

The in-app confirmation for either endpoint expires after 80 seconds, under the
host's 90s budget. A prompt that outlived the request could be approved after
the page had already fallen back to the browser, which would sign a challenge
nobody is waiting for or — what FR-020 forbids — write a credential the site
was never told about. A successful write is announced to the app window, which
reloads: the vault on disk is then ahead of both the open record and the
bridge's own credential map and advertised capabilities, so a sign-in straight
after registering would otherwise find nothing.
