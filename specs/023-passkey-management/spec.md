# 023 — Passkey management

**Status**: Draft · **Kind**: Feature / Credentials
**Created**: 2026-08-29
**Depends on**: 004 (entry editor), 006 (security & autofill extension), 008 (per-field conflict resolution — merge of the new fields)
**Coordinates with**: 016 (Android autofill; passkeys were declared out of scope there), 005 (CSV import must not be able to inject passkey fields; attachment and backup export must not leak them), 017 (password history must not record passkey material), 019 (vault navigation model 1a — the entry detail surface the passkey section lands on), 020–022 (pixel passes; a new entry-detail section must be added in the restyled tokens, not ahead of them)

**Input**: User description: "Gestione delle passkey (WebAuthn/FIDO2) nel vault KDBX: storage interoperabile con KeePassXC nei campi custom protetti, visualizzazione e gestione delle passkey nell'entry editor, registrazione e autenticazione tramite l'estensione Apple AutoFill (iOS/macOS), con Android Credential Manager e browser desktop come fasi successive."

## Summary

A passkey is a per-site key pair that replaces the password: the site keeps the
public key, the credential holder keeps the private key and proves possession by
signing a challenge. Sites increasingly offer, and some now require, passkeys —
a password manager that cannot hold one forces the user to keep a second
credential store.

KeyVault stores credentials in a `.kdbx` file, and that format already carries
passkeys in practice: KeePassXC writes them as a small set of named fields on an
ordinary entry. This spec makes KeyVault a first-class holder of those
credentials, in three independently shippable slices:

1. **Hold them** — read, display, protect, sync and delete passkeys that already
   exist in the vault (typically created by KeePassXC on the desktop), without
   ever exposing the private key to the UI, the logs, an export or the
   plaintext caches.
2. **Use them** — sign in with a stored passkey on iOS and macOS through the
   existing AutoFill credential provider extension.
3. **Create them** — register a brand-new passkey from the same extension, so a
   site's "create a passkey" flow can choose KeyVault.

Slice 1 alone delivers value (a KeePassXC user's vault stops being partially
unreadable and unsafely handled in KeyVault); slices 2 and 3 turn KeyVault into
a usable authenticator on Apple platforms.

Android (Credential Manager) and desktop browsers (WebAuthn interception in the
browser extension) are deliberately **not** in this spec — see *Deferred scope*.

### Why the private key needs new plumbing

Custom fields today are written unprotected — every custom field value goes into
the KDBX as a plain value, and the entry editor shows and copies it like any
other text. A passkey private key cannot travel that path: it must be a
protected value in the file, must never be rendered, copied or exported, and
must never appear in a diagnostic string. Principle I of the constitution
(*Secrets never leak into the shell*) is therefore the governing constraint of
this feature, not a checklist item at the end.

## Clarifications

### Session 2026-08-29

- Q: Is user presence required on every assertion, or may a recent unlock satisfy it? → A: Every assertion — biometrics or device passcode each time, no reuse of the password path's recent-unlock window.
- Q: Where does passkey private key material live when the app is not running? → A: In the same sealed cache the app already uses for passwords (AES-GCM-256 in the App Group container, key in the shared keychain, this-device-only, never in a backup), wiped when the database is locked or removed.
- Q: Does Android's Credential Manager belong in this spec or its own? → A: Its own spec — 023 stops at Apple.
- Q: Where is the key pair generated at registration? → A: In the credential provider extension, in CryptoKit; no Dart cryptography dependency is added by this spec.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hold passkeys safely in the vault (Priority: P1)

A user who already created passkeys in KeePassXC opens the same `.kdbx` in
KeyVault. Entries carrying a passkey are recognisable as such, the user can see
which site and account the passkey belongs to and when it was added, and can
delete it. The private key is never displayed, never copied to the clipboard,
never written to an export or an autofill cache, and survives sync and merge
untouched.

**Why this priority**: It is the correctness and safety floor. Without it,
KeyVault silently mishandles credentials that are already in the user's file —
showing a private key as ordinary copyable text is worse than not supporting
passkeys at all. It is also a precondition for every later slice.

**Independent Test**: Open a `.kdbx` containing a KeePassXC-created passkey,
confirm the entry is marked as holding a passkey with the correct site and
account shown, confirm no view or export path yields the private key, delete the
passkey and confirm the entry keeps its other fields and the file reopens
cleanly in KeePassXC.

**Acceptance Scenarios**:

1. **Given** a vault entry carrying a passkey created by KeePassXC, **When** the
   user opens the entry, **Then** the entry shows a passkey section naming the
   relying party and the passkey username, and shows no private key value.
2. **Given** that entry, **When** the user attempts any copy, reveal, export or
   share action available on the entry, **Then** no action yields the private
   key or the credential seed.
3. **Given** that entry, **When** the user deletes the passkey and saves,
   **Then** the passkey fields are removed, all other fields are unchanged, and
   KeePassXC opens the resulting file without error or warning.
4. **Given** two devices syncing the same vault where one added a passkey,
   **When** the vaults merge, **Then** the passkey arrives intact and the merge
   preview describes it as a passkey rather than listing its raw field values.
5. **Given** a passkey entry, **When** any diagnostic or log line is produced for
   it, **Then** the private key is absent from that output.

---

### User Story 2 - Sign in with a stored passkey on iOS and macOS (Priority: P2)

A user visits a site or app on iPhone or Mac that asks for a passkey. The system
offers KeyVault among the credential providers; the user picks the KeyVault
passkey for that site, confirms with biometrics or device passcode, and is
signed in without typing anything.

**Why this priority**: It is the payoff of holding the credential, and it reuses
the credential provider extension that already exists for passwords, so it is
the cheapest platform to reach.

**Independent Test**: With a passkey for a test relying party in the vault,
trigger a passkey sign-in on iOS and on macOS and confirm the sign-in completes
using KeyVault, and that a passkey for a *different* relying party is never
offered or usable for that site.

**Acceptance Scenarios**:

1. **Given** the vault holds a passkey for a site, **When** the site requests a
   passkey sign-in, **Then** KeyVault appears as an available provider and lists
   only passkeys whose relying party matches that site.
2. **Given** the user selects a KeyVault passkey, **When** the user confirms with
   biometrics or device passcode, **Then** the sign-in succeeds.
3. **Given** the user cancels or fails the confirmation, **When** the flow ends,
   **Then** no assertion is produced and the site receives a cancellation, not an
   error implying the credential is missing.
4. **Given** the vault holds no passkey for the requesting site, **When** the
   request arrives, **Then** KeyVault offers nothing for that request and does
   not present a misleading empty list.
5. **Given** a passkey sign-in has completed, **When** the flow ends, **Then** no
   private key remains outside its protected storage.

---

### User Story 3 - Create a new passkey from KeyVault on iOS and macOS (Priority: P3)

A user on a site's "create a passkey" flow chooses KeyVault as the destination.
KeyVault creates the credential, stores it on a new or existing entry for that
site, and the site completes registration. The new passkey is immediately
visible in the vault (Story 1) and usable for sign-in (Story 2).

**Why this priority**: It removes the dependency on KeePassXC for creating
passkeys, but the user still gets real value from Stories 1 and 2 without it.

**Independent Test**: Run a passkey registration on a test relying party
choosing KeyVault, then confirm the credential appears in the vault with the
correct site and account, and that signing in with it afterwards succeeds.

**Acceptance Scenarios**:

1. **Given** a site requests passkey creation, **When** the user chooses KeyVault
   and confirms, **Then** a passkey is stored in the vault and the site reports
   successful registration.
2. **Given** the vault already has an entry for that site and account, **When**
   the passkey is created, **Then** the user can attach it to that existing entry
   instead of creating a duplicate.
3. **Given** the vault already holds a passkey for the same relying party and
   user handle, **When** a new one is created for that same pair, **Then** the
   user is told what will be replaced before anything is overwritten, and the
   previous credential is not silently lost.
4. **Given** creation is interrupted (cancelled, vault locked, write failure),
   **When** the flow ends, **Then** the vault contains either the complete
   passkey or none of it — never a partial credential.

---

### Edge Cases

- **Vault locked at request time.** A passkey request can arrive when the vault
  has not been unlocked. Per FR-022 the credential is still servable from the
  sealed cache, so this must produce a working sign-in behind the per-assertion
  confirmation — not a prompt to go and open the app. Where the credential is
  genuinely unavailable (cache wiped, database removed), the user must be told
  plainly, never left with a silent failure that looks to the site like "no
  credential".
- **Malformed or foreign passkey fields.** An entry carrying an incomplete,
  truncated or unrecognised passkey field set must be shown as an unusable
  passkey and left byte-identical on save; KeyVault must not "repair" or drop
  fields it does not understand.
- **Same relying party, several accounts.** Multiple passkeys for one site must
  be distinguishable by account at selection time.
- **Passkey and password on the same entry.** An entry may hold both; each must
  be offered to the matching kind of request and neither may shadow the other.
- **Deleting an entry that holds a passkey.** The recycle bin path must treat the
  passkey as a credential to be restored intact, not as loose text fields.
- **Field-level merge conflicts on passkey fields.** A conflict-resolution UI
  that displays field values must not display passkey secret values, and must not
  let a merge produce a credential assembled from two different passkeys.
- **Import paths.** CSV import must not be able to inject a passkey field set,
  and the duplicate detector must not treat two different passkeys as duplicates
  because their surrounding fields match.
- **Read-only or failed save.** If the vault cannot be written, a registration
  must fail before the site is told it succeeded.

## Requirements *(mandatory)*

### Functional Requirements

**Storage and interoperability**

- **FR-001**: The system MUST store a passkey on an ordinary vault entry using a
  field layout that KeePassXC reads as a passkey, and MUST read passkeys written
  by KeePassXC without conversion or migration.
- **FR-002**: The system MUST store the passkey's private key material as a
  protected value in the vault file, distinct from ordinary custom fields, which
  are stored unprotected today.
- **FR-003**: The system MUST preserve any passkey-related field it does not
  recognise, byte-for-byte, across open, edit and save of the entry.
- **FR-004**: The system MUST keep an entry's passkey intact across sync, merge,
  recycle-bin deletion and restore.

**Confidentiality**

- **FR-005**: The system MUST NOT display, copy to the clipboard, reveal, or
  otherwise render the passkey private key or credential seed in any user
  interface.
- **FR-006**: The system MUST NOT include passkey secret material in logs,
  diagnostic strings, error messages, crash reports, plaintext caches, attachment
  or backup exports, or any message sent over the desktop browser bridge. (The
  app has no CSV export today — CSV is import-only; see `research.md` R3 for the
  surfaces that actually exist.)
- **FR-007**: The system MUST NOT record passkey secret material in password
  history.
- **FR-008**: Where a conflict-resolution or merge-preview surface lists changed
  fields, the system MUST represent a passkey as a single named credential and
  MUST NOT display its secret values.

**Management in the app**

- **FR-009**: Users MUST be able to see, on an entry that holds a passkey, that a
  passkey exists and which relying party and account it belongs to.
- **FR-010**: Users MUST be able to delete a passkey from an entry without
  affecting the entry's other fields.
- **FR-011**: The system MUST make entries holding passkeys findable — a user
  MUST be able to tell from the vault which of their credentials are passkeys.
- **FR-012**: The system MUST show a passkey it cannot interpret as unusable, and
  MUST explain that it cannot be used for sign-in, rather than failing silently.

**Sign-in (Apple platforms)**

- **FR-013**: The system MUST offer KeyVault as a passkey provider on iOS and
  macOS for sign-in requests.
- **FR-014**: The system MUST offer, for a given request, only passkeys whose
  relying party matches the requesting site, and MUST NOT allow a passkey for one
  relying party to be used for another.
- **FR-015**: The system MUST require user presence — biometrics or device
  passcode — before producing **each** assertion. A recent successful vault
  unlock MUST NOT satisfy this requirement, even though the password autofill
  path reuses such a window today.
- **FR-016**: The system MUST produce an assertion that the requesting site
  accepts as a valid WebAuthn response for the stored credential.
- **FR-017**: On cancellation, failed confirmation, locked vault or missing
  credential, the system MUST end the request with the outcome that matches the
  actual cause, and MUST NOT report success.

**Registration (Apple platforms)**

- **FR-018**: The system MUST support creating a passkey for a requesting site
  and storing it either on a new entry or on an existing entry chosen by the
  user.
- **FR-019**: The system MUST warn before replacing an existing passkey for the
  same relying party and user handle, and MUST NOT overwrite one silently.
- **FR-020**: A registration MUST be all-or-nothing: the vault MUST never be left
  holding a partially written credential, and the site MUST NOT be told
  registration succeeded unless the credential was durably written to the vault.
- **FR-021**: Passkey creation and use MUST respect the existing backup and safe
  write protections that govern every vault write.

**Availability of the credential to the platform**

- **FR-022**: Passkey private key material MUST be held in the same encrypted,
  sealed cache the app already uses for passwords — device-local, readable only
  while the device is unlocked, and excluded from device backups — so that a
  system passkey request can be served while the app is not running. It MUST
  NOT appear in the plaintext routing/display cache.
- **FR-023**: The system MUST remove a database's passkey material from that
  cache when the database is locked or removed, so a user has a way to stop a
  device from being able to answer passkey requests.

### Key Entities *(include if data involved)*

- **Passkey credential**: The credential stored on a vault entry. Attributes:
  relying party identifier, credential identifier, account/username shown to the
  user, user handle, private key material (secret, never displayed), creation
  time. One entry holds zero or more; each belongs to exactly one relying party.
- **Vault entry**: The existing container. Gains the ability to hold passkeys
  alongside its password, custom fields and attachments, and to declare that it
  holds one.
- **Protected custom field**: An entry field whose value is stored encrypted in
  the vault file and is excluded from display, copy and export. New concept —
  today every custom field is unprotected.
- **Passkey request**: A system-originated ask from a site — either "sign in" or
  "create" — carrying the relying party and, for sign-in, the acceptable
  credential identifiers.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A vault created in KeePassXC with passkeys opens in KeyVault with
  100% of those passkeys recognised, and reopens in KeePassXC afterwards with no
  passkey lost, altered or reported as corrupt.
- **SC-002**: No user-reachable action in the app, and no exported or logged
  artefact, yields passkey secret material — verified by an automated check that
  fails the build if a passkey secret reaches display, clipboard, export or log
  paths.
- **SC-003**: A user can complete a passkey sign-in on iOS or macOS in under 15
  seconds from the moment the site asks, without leaving the requesting app.
- **SC-004**: A passkey created in KeyVault is accepted by the site at
  registration and works for a subsequent sign-in on at least three independent
  relying parties used as conformance targets.
- **SC-005**: A passkey offered for a site is never a passkey belonging to
  another site — zero cross-relying-party offers across the matching test suite.
- **SC-006**: An interrupted registration leaves zero partially written
  credentials across the interruption test matrix (cancel, lock, write failure).
- **SC-007**: Opening and saving an entry that holds a passkey KeyVault does not
  fully understand changes no byte of that passkey's stored fields.

## Assumptions

- The KeePassXC field layout for passkeys is the interoperability target;
  matching it is preferred over inventing a KeyVault-specific layout, so that
  vaults stay usable in both applications.
- The security model of a passkey held here is the vault's security model —
  master password, key file and the sync destination — not hardware-backed key
  isolation. This is a deliberate trade for portability and must be stated to the
  user, not implied.
- Apple platforms are reached through the credential provider extension that
  already serves passwords; no second extension is introduced.
- Existing user-facing copy and the current password autofill behaviour are
  unchanged by this feature (constitution VI).
- The three existing BLoCs are sufficient; passkey work is expected to live in
  use cases, services and the existing coordinators (constitution II, VIII).
- Attestation of the created credential is not required by the target relying
  parties; self-attestation or none is acceptable.
- Key generation and signing both happen inside the credential provider
  extension, using the platform's own cryptography. The app is not running when
  a request arrives, so no second cryptographic implementation is introduced on
  the Dart side and this spec adds no cryptography dependency.
- Verification is local before push — `flutter analyze` clean and `flutter test`
  green — and the platform flows that cannot run in the test suite are covered by
  a named manual QA harness, as spec 008 and spec 011 already do.

## Deferred scope

Out of scope for 023, each to be its own spec if adopted:

- **Android.** Passkeys are served by the Credential Manager provider API, a
  different integration from the autofill service completed in spec 016, which
  explicitly excluded them. It also has a floor of its own: a Credential Manager
  provider needs a newer Android than this app's declared minimum, so a large
  part of the supported range needs a "not available here" story that belongs in
  that spec, not in a user story here.
- **Desktop browsers.** Serving passkeys to a browser requires intercepting the
  site's WebAuthn calls in the browser extension — a large compatibility and
  security surface, and a change to the extension's permissions.
- **Windows and Linux system-level passkey providers.**
- **Attestation statements**, enterprise attestation and device-bound keys.
- **Passkey export/backup as a standalone artefact** outside the `.kdbx`.
