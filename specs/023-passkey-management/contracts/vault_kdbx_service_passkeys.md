# Contract — `VaultKdbxService` passkey surface

All methods take the existing `(path, credentials)` pair and run under
`DatabasePathMutex` like every other write.

## Read (no new method)

`loadEntries` / entry mapping now produces, per entry:

- `customFields`: every non-standard string **except** keys starting
  `KPEX_PASSKEY_`, each with `isProtected` as read.
- `passkeys`: `PasskeyParser.parse(rawPasskeyFields)` — one `VaultPasskey`
  per suffix group (`""`, `_1`, `_2`, …); never throws; malformed → `usable:
  false`.
- `passkeyDigest`: fingerprint of the raw strings, or `null`.

Invariant: no `KPEX_PASSKEY_*` key ever appears in `customFields`.

## Write (`createEntry`, `updateEntry`, `restoreEntryRevision`, merge)

`_setCustomFields(entry, customFields)`:

1. Remove every non-standard key **outside** the `KPEX_PASSKEY_*` namespace.
2. Re-add `customFields` with `PlainValue` or `ProtectedValue` per
   `isProtected`, skipping any `KPEX_PASSKEY_*` key a caller passes in.

The namespace is therefore left in the `KdbxEntry` exactly as opened.

Invariant (SC-007): for an entry opened and saved without a passkey change,
every `KPEX_PASSKEY_*` string has identical value and identical
`Protected` attribute before and after — including keys the parser does not
understand (`KPEX_PASSKEY_PRF`).

`restoreEntryRevision` restores the revision's editable fields only; the
passkey strings of the current entry stay in place.

## `deletePasskey`

```
Future<void> deletePasskey({
  required String path, required VaultCredentials credentials,
  required String entryId, required String relyingPartyId,
  required Uint8List credentialId,
})
```

- Removes exactly the suffix group whose `(rpId, credentialId)` matches.
- Leaves every other string, binary, tag and history record untouched.
- Appends one history revision (ordinary edit semantics).
- Throws `PasskeyNotFound` when no group matches; throws on a locked or
  read-only session like the other writers.

Caller (`PasskeyCoordinator`) is responsible for confirmation and the dated
backup; the service does neither.

## `PasskeyParser` (pure, `data/services/passkey_parser.dart`)

```
List<VaultPasskey> parse(List<VaultCustomField> rawPasskeyFields)
VaultPasskeyAlgorithm algorithmOf(String pem)   // OID → enum, unknown otherwise
Uint8List decodeBase64Url(String s)             // padded or unpadded
```

Test vectors live beside the test: one ES256, one EdDSA, one RS256 PEM (all
generated for the tests), one truncated PEM, one missing-credential-id set.
