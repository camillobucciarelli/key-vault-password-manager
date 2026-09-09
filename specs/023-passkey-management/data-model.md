# 023 — Data model

## VaultCustomField (modified)

| Field | Type | Notes |
|---|---|---|
| `key` | String | unchanged |
| `value` | String | redacted in `props`/`toString` (unchanged) |
| `isProtected` | bool, default `false` | read from the KDBX `StringValue` type; written back as `ProtectedValue` when true |

Rule: the writer emits exactly the protection it was given. Existing callers
that construct fields without the flag keep today's behaviour (plain). The
flag is user-editable per field in the entry editor ("secret" toggle) and is
the single input for masking, reveal gating and clipboard guarding in views
(FR-002a/b). `props` includes `isProtected`; the value stays redacted.

## VaultPasskey (new)

| Field | Type | Source field | Notes |
|---|---|---|---|
| `relyingPartyId` | String | `KPEX_PASSKEY_RELYING_PARTY` | plain; identity part 1 |
| `credentialId` | Uint8List | `KPEX_PASSKEY_CREDENTIAL_ID` | base64url decoded; protected; identity part 2 |
| `userHandle` | Uint8List? | `KPEX_PASSKEY_USER_HANDLE` | base64url decoded; protected |
| `username` | String | `KPEX_PASSKEY_USERNAME` | plain; display |
| `privateKeyPem` | String | `KPEX_PASSKEY_PRIVATE_KEY_PEM` | **secret**; protected; redacted everywhere; absent from `props` |
| `algorithm` | enum `VaultPasskeyAlgorithm {es256, eddsa, rs256, unknown}` | derived from the PKCS#8 OID | never stored |
| `backupEligible` / `backupState` | bool | `KPEX_PASSKEY_FLAG_BE` / `_BS`, `"1"`/`"0"` | default true when absent (KeePassXC writes `1`) |
| `createdAt` | DateTime? | entry creation time | display only |
| `usable` | bool | derived | false when any of the three required fields is missing, PEM does not parse, or `algorithm == unknown` |
| `unusableReason` | enum? | derived | `missingField`, `badKey`, `unsupportedAlgorithm`, `unsupportedOnPlatform` |

Identity: `(relyingPartyId, credentialId)` within a vault. Cardinality:
entry 1 → 0..n passkeys (KeePassDX `_1` suffix groups).

`props` = `[relyingPartyId, credentialId, userHandle, username, algorithm,
backupEligible, backupState, usable]`. `toString` names rpId and username only.

## VaultEntry (modified)

| Field | Type | Notes |
|---|---|---|
| `customFields` | List<VaultCustomField> | now **excludes** every key starting `KPEX_PASSKEY_` (case-sensitive, as KeePassXC writes them) |
| `passkeys` | List<VaultPasskey> | parsed; empty when none |
| `passkeyRawFields` | List<VaultCustomField> | every `KPEX_PASSKEY_*` field as read, protection flags intact; re-emitted verbatim by the writer unless `deletePasskey` removed a group |
| `hasPasskey` | bool getter | `passkeys.isNotEmpty` — the badge input |

## VaultEntryRevision (modified)

Same split as `VaultEntry`: `customFields` excludes the namespace, and the
revision carries **no** raw passkey fields and no `VaultPasskey` (FR-007). The
"changed fields" diff reports `passkey` as a single name when the raw set
differs between revisions.

## DuplicateGroup (modified)

| Field | Type | Notes |
|---|---|---|
| `kind` | enum `{credentials, site, passkeyPassword}` | new; existing groups get `credentials`/`site` |

`passkeyPassword`: exactly two entries, one with `hasPasskey && password.isEmpty`,
one with `password.isNotEmpty && !hasPasskey`, same normalized site and username.

## MergePreview (modified)

| Field | Type | Notes |
|---|---|---|
| `passkeysToCopy` | List<VaultPasskey> | shown by rpId + username only |
| `passkeyConflict` | bool | primary already holds the same `(rpId, userHandle)` → merge refused with an explanation |

## Platform caches

**Apple `AutofillCredentialSecret` / Android secret record** — optional block:

```
passkey: {
  rpId: String, credentialId: base64url, userHandle: base64url?,
  username: String, privateKeyPem: String, algorithm: "ES256"|"EdDSA"|"RS256",
  be: Bool, bs: Bool
}
```

**Metadata caches (plaintext)** — `hasPasskey: Bool`, `passkeyRpId: String?`,
`passkeyCredentialId: base64url?` (routing only; the credential id is public
data by WebAuthn design, the RP already holds it). Never the PEM, never the user
handle.

Only `usable` passkeys are published. Lifetime identical to password secrets.

## Assertion (transient, never persisted)

| Field | Bytes |
|---|---|
| `rpIdHash` | SHA-256(rpId) — 32 |
| `flags` | UP(0x01) \| UV(0x04) \| BE(0x08 if be) \| BS(0x10 if bs) — 1 |
| `signCount` | `0x00000000` — 4 |
| `authenticatorData` | rpIdHash ‖ flags ‖ signCount |
| `signature` | Sign(privateKey, authenticatorData ‖ clientDataHash), DER for ES256/RS256, raw 64 bytes for EdDSA |

Response: `{credentialId, authenticatorData, signature, userHandle, clientDataJSON (desktop only)}`
all base64url.

## State transitions

```
passkey in .kdbx ──open──▶ VaultEntry.passkeys (usable?) ──publish──▶ sealed cache
        ▲                          │                                    │
        │                     delete (confirm + backup)             lock/remove
        └── writer re-emits raw ◀──┘                                    ▼
                                                                     wiped
```
