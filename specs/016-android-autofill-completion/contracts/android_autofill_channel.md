# 016 — Method channel contract (additive)

Channel: `dev.camillobucciarelli.keyvault/apple_autofill_v2` (name historical; it
carries Android too). Everything below is **additive**. Existing methods,
arguments, results and the Apple side are unchanged; the Apple implementation
ignores the new field and does not implement the new methods.

## Changed: `publishCredentials`

Arguments gain one optional field:

| Field | Type | Meaning |
| --- | --- | --- |
| `authSessionTtlMs` | `int`, optional, default `0` | How long a successful device authentication may be reused before the next release of a secret prompts again. `0` = prompt every time. Published from the spec 011 master-password session scope. Negative values are rejected as an argument error. |

Result is unchanged in shape. `getStatus` gains two read-only fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `authSessionTtlMs` | `int` | The value currently stored. |
| `lastAuthenticatedAtEpochMs` | `int?` | When a release was last authenticated, or `null`. Never includes anything about *which* entry was released. |

Both live in the existing plaintext metadata file. Neither is a secret.

## New: `readPendingCapture`

Called by Dart when the app is launched by a save request.

**Arguments**: `{ "token": String }` — the opaque token carried in the launching
intent.

**Result**:

```
{
  "token": String,
  "username": String,        // may be empty (change-password screens)
  "password": String,        // present only in this response, never persisted
  "packageName": String?,    // the app the capture came from
  "webDomain": String?,      // set instead of packageName for browser captures
  "capturedAtEpochMs": int
}
```

**Errors**: `android_autofill_capture_missing` when the token is unknown or the
capture already expired (process death, timeout, or a prior resolve call). This
is an expected outcome, not a crash: Dart reports "the credential was not saved"
and stops.

**Invariants**:

- The password is returned exactly once per token. A second `readPendingCapture`
  with the same token fails with `android_autofill_capture_missing`.
- The value is never logged, never written to disk, and never included in any
  `toString()` on either side of the channel.

## New: `resolvePendingCapture`

Called by Dart after the user accepts or declines, and on every failure path.

**Arguments**:

```
{
  "token": String,
  "outcome": "saved" | "updated" | "declined" | "cancelled" | "failed"
}
```

**Result**: `{ "clearedCount": int, "warnings": [String] }` — matching the shape
the existing `clearPendingAssociations` returns.

**Invariants**:

- Calling it clears the holder entry unconditionally, whatever the outcome.
- `declined` additionally records the association so the same submission is not
  prompted again (FR-011). The record holds the association and username only —
  never the password.
- It is safe to call for an unknown token; the result is `clearedCount: 0`.

## Native structures (not exposed over the channel)

`AndroidAutofillCapture` — `token`, `username`, `password`, `packageName`,
`webDomain`, `capturedAtEpochMs`. Its `toString()` redacts `password` and
`username`, matching `AndroidAutofillCredentialSecret`.

`AndroidAutofillCaptureHolder` — a process-local map from token to capture, with
an expiry and explicit clearing on resolve, on activity destruction and on
process death (nothing is persisted, so process death clears it implicitly).

## Compatibility

A build of the app that predates these methods keeps working: the field is
optional and defaults to prompting every time, and the new methods are only
called after a save intent that an older service never sends.
