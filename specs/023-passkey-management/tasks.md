# 023 — Tasks

Ordered work for [spec.md](spec.md), against [plan.md](plan.md). Beta scope:
User Stories 1, 1b and 2. User Story 3 (registration) has no tasks here and
is not counted by the board until it is planned.

Owners name the agent best suited to the task; a human may take any of them.
Each task states the files it touches, what "done" means, and how that is
checked. Tick a box only when its own acceptance holds and its tests pass.
`[P]` marks tasks that can run alongside their neighbours (different files, no
pending dependency).

---

## Phase 1 — Setup

- [ ] **T001** [P] Build the KeePassXC fixture vault — owner: `senior-tester`
  Files: `test/fixtures/passkeys/keepassxc_passkeys.kdbx` (new),
  `test/fixtures/passkeys/README.md` (new).
  Acceptance: created in KeePassXC ≥ 2.7.7 with the entries E1–E4 of
  `quickstart.md` (E1 ES256 passkey-only, E2 password for the same site and
  username, E3 passkey + password, E4 truncated PEM), plus one entry with a
  protected custom attribute `Recovery` and one EdDSA passkey. Keys are
  generated for the fixture only; the README says so and states the master
  password. Every `KPEX_PASSKEY_*` attribute's protect state is listed in the
  README as observed in KeePassXC.
  Verify: KeePassXC opens it and signs in on webauthn.io with E1 before it is
  committed.

- [x] **T002** [P] Test vectors for parsing and signing — owner: `senior-flutter-dev`
  Files: `test/fixtures/passkeys/vectors.dart` (new).
  Acceptance: one ES256, one EdDSA and one RS256 PKCS#8 PEM generated for the
  tests, with matching public keys; one truncated PEM; a known
  `(rpId, clientDataHash)` pair with the expected `authenticatorData` bytes per
  `data-model.md` (flags UP|UV|BE|BS, sign count 0).
  Verify: the file compiles and the vectors are referenced by T012 and T014.

- [ ] **T003** [P] Device evidence ledger — owner: `senior-tester`
  Files: `specs/023-passkey-management/device-evidence.md` (new).
  Acceptance: same shape as `specs/016-android-autofill-completion/device-evidence.md`
  with a devices table (iPhone, Mac, Android API 34+, Android API 29–33,
  Windows, Linux) and one empty row per quickstart section D–F item.
  Verify: file exists and lists every D–F step by id.

## Phase 2 — Foundational (blocks every story)

- [x] **T010** Stop downgrading protected custom fields on save — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/domain/models/vault_custom_field.dart`,
  `lib/features/password_manager/data/services/vault_kdbx_service.dart`,
  `test/features/password_manager/data/services/vault_kdbx_service_test.dart`.
  Acceptance: `VaultCustomField.isProtected` (default `false`, in `props`,
  value still redacted). `_mapCustomFields` sets it from `stringEntry.value is
  ProtectedValue`; `_setCustomFields` writes `ProtectedValue.fromString` when
  true. No other behaviour changes. Committed on its own, before any passkey
  code (plan D2).
  Verify: service test opens a temp vault with one protected and one plain
  custom field, saves a title-only edit, reopens and asserts both protection
  states unchanged (SC-008). A `VaultCustomField(isProtected: true)` round-trips.

- [x] **T011** [P] Passkey domain model — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/domain/models/vault_passkey.dart` (new),
  `test/features/password_manager/domain/models/vault_passkey_test.dart` (new).
  Acceptance: `VaultPasskey`, `VaultPasskeyAlgorithm`, `VaultPasskeyUnusableReason`
  per `data-model.md`. `privateKeyPem` is absent from `props` and `toString`;
  `toString` names rpId and username only.
  Verify: unit test builds a passkey with a PEM containing `SENTINEL` and
  asserts `props.toString()` and `toString()` never contain it.

- [x] **T012** [P] Passkey parser — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/data/services/passkey_parser.dart` (new),
  `test/features/password_manager/data/services/passkey_parser_test.dart` (new).
  Acceptance: `parse(List<VaultCustomField>)` groups by suffix (`""`, `_1`, …),
  requires `RELYING_PARTY`, `CREDENTIAL_ID`, `PRIVATE_KEY_PEM`, decodes
  base64url padded or unpadded, derives the algorithm from the PKCS#8 OID,
  reads `FLAG_BE`/`FLAG_BS` defaulting to true, never throws. Per
  `contracts/vault_kdbx_service_passkeys.md`.
  Verify: T002 vectors → three usable passkeys with the right algorithm;
  truncated PEM → `badKey`; missing credential id → `missingField`; a
  `_1` suffixed second group parses as a second passkey; an unknown OID →
  `unsupportedAlgorithm`.

- [x] **T013** Split passkey fields out of the entry — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/domain/models/vault_entry.dart`,
  `lib/features/password_manager/domain/models/vault_entry_revision.dart`,
  `lib/features/password_manager/data/services/vault_kdbx_service.dart`,
  `test/features/password_manager/data/services/vault_kdbx_service_test.dart`.
  Acceptance: `VaultEntry.customFields` excludes keys starting
  `KPEX_PASSKEY_`; `VaultEntry.passkeys` and `passkeyDigest` populated per
  the contract; `hasPasskey` getter. The raw strings are not carried on the
  model: `_setCustomFields` never removes or writes the `KPEX_PASSKEY_*`
  namespace, so it stays in place in the `KdbxEntry` untouched.
  `VaultEntryRevision.customFields` applies the same exclusion and carries only
  `passkeyDigest`; its diff reports `passkey` by name when the digest differs.
  `restoreEntryRevision` likewise leaves the namespace in place.
  Verify: open the T001 fixture → E1, E3, E4 have `hasPasskey`, E2 not,
  E4 `usable == false`; no `KPEX_` key in any `customFields`; title-only
  save then byte-compare every `KPEX_*` string and its `Protected` attribute
  (SC-007); a revision of E1 contains no PEM; restoring E1's revision leaves
  the passkey intact.

- [x] **T014** [P] Desktop signer — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/data/services/desktop_passkey_signer.dart` (new),
  `test/features/password_manager/data/services/desktop_passkey_signer_test.dart` (new).
  Acceptance: builds `authenticatorData` per `data-model.md` and signs
  `authenticatorData ‖ clientDataHash` with `pointycastle` for ES256 (DER
  signature, secp256r1) and RS256 (SHA-256 PKCS#1 v1.5); EdDSA returns
  `unsupportedOnPlatform`. Builds `clientDataJSON` `{type:"webauthn.get",
  challenge, origin, crossOrigin:false}`. No new dependency.
  Verify: signatures verify against the T002 public keys; the
  `authenticatorData` bytes equal the vector; EdDSA input → typed failure.

## Phase 3 — US1b: Secret custom fields (P1)

Goal: a user can mark any custom field secret; it is stored protected and
treated like the password in every view.
Independent test: quickstart A2.

- [ ] **T101** [US1b] Secret toggle in the editor — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/presentation/screens/vault/vault_entry_editor.part.dart`,
  `test/features/password_manager/presentation/screens/vault/vault_entry_editor_test.dart`.
  Acceptance: `_CustomFieldFormRow.isProtected`, initialised from the field;
  a per-row "Secret" switch with a semantic label; the value field is
  obscured with a show/hide affordance when on; `_buildCustomFields` passes
  the flag through. Turning the switch off on a row that started protected
  asks for confirmation naming the field (FR-002a). All strings new
  (Constitution VI).
  Verify: widget tests — new row defaults off; toggling on obscures the
  value; saving emits `isProtected: true`; toggling off a protected row shows
  the confirmation and cancel keeps it protected.

- [ ] **T102** [US1b] Secret field in the entry detail — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/presentation/screens/vault/vault_entry_detail.part.dart`,
  `test/features/password_manager/presentation/screens/vault/vault_entry_detail_test.dart`.
  Acceptance: a custom field with `isProtected` renders masked, uses the
  existing `RevealController`, `_showBiometricRevealGate` and
  `ClipboardGuard.copy` exactly as the password row (plan D2a). Plain fields
  are unchanged.
  Verify: widget tests — masked by default; reveal goes through the gate on a
  biometric-protected database; copy calls the guard; the raw value never
  appears in the tree while masked.

- [ ] **T103** [P] [US1b] Secret fields in history and merge preview — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/domain/models/vault_entry_revision.dart`,
  `lib/features/password_manager/domain/models/merge_field_display.dart`,
  `lib/features/password_manager/data/services/kdbx_merge_adapter.dart`,
  `lib/features/password_manager/presentation/screens/vault/vault_entry_history.part.dart`,
  matching tests under `test/`.
  Acceptance: a secret custom field shows by name with redacted sides in the
  merge preview and masked in a history revision, with the same reveal
  behaviour as the revision's password (FR-002b).
  Verify: unit tests on the display models; history widget test asserts the
  value is not rendered while masked.

- [ ] **T104** [US1b] Goldens for the secret field — owner: `senior-tester`
  Files: `test/goldens/editor_custom_field_secret_test.dart` (new),
  `test/goldens/vault_entry_detail_secret_field_test.dart` (new), PNGs.
  Acceptance: `editor_custom_field_secret` 390×844 light+dark,
  `vault_entry_detail_secret_field` 390×844 light; contrast ≥ 4.5:1 asserted
  on the toggle label; `warmUpGoldenAssets()` in `setUpAll`; no `di.sl` in
  `dispose`.
  Verify: `fvm flutter test test/goldens --test-randomize-ordering-seed=$RANDOM`
  and the plain run both green.

## Phase 4 — US1: Hold passkeys safely in the vault (P1)

Goal: passkeys from KeePassXC are recognised, shown, protected, deletable and
survive every write path.
Independent test: quickstart A, B, C.

- [ ] **T201** [P] [US1] Passkey badge in the list — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/presentation/screens/vault/vault_entries.part.dart`,
  `test/features/password_manager/presentation/screens/vault/vault_entries_test.dart`.
  Acceptance: an entry with `hasPasskey` shows a badge from `AppIcons` with
  semantic label "Passkey", tokens only, never colour alone (FR-011).
  Verify: widget test finds the semantic label on E1 and not on E2.

- [ ] **T202** [US1] Passkey section in the entry detail — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/presentation/screens/vault/vault_entry_passkeys.part.dart` (new),
  `lib/features/password_manager/presentation/screens/vault_screen.dart` (one `part`),
  `lib/features/password_manager/presentation/screens/vault/vault_entry_detail.part.dart`,
  `test/features/password_manager/presentation/screens/vault/vault_entry_passkeys_test.dart` (new).
  Acceptance: per passkey — rpId, username, algorithm, created date, backup
  flags as text; an unusable passkey states it cannot be used for sign-in and
  why (FR-012); the fixed security note (FR-009); a delete action ≥ 44 dp
  with a focus ring. No copy or reveal on any passkey value. Rows ≥ 44 dp.
  Verify: widget tests — section renders for E1/E3/E4 with the right text;
  no character of the PEM in the tree; no copy/reveal buttons; unusable copy
  present for E4.

- [ ] **T203** [US1] `deletePasskey` on the service — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/data/services/vault_kdbx_service.dart`,
  `test/features/password_manager/data/services/vault_kdbx_service_test.dart`.
  Acceptance: per `contracts/vault_kdbx_service_passkeys.md`: removes exactly
  the matching suffix group, leaves everything else, appends one history
  revision, throws `PasskeyNotFound` on no match. Under `DatabasePathMutex`.
  Verify: delete E3's passkey → E3 keeps password, URL, custom fields,
  attachments and tags; one new revision; a second delete throws; deleting
  from E1 with two groups removes one.

- [ ] **T204** [US1] `PasskeyCoordinator.delete` — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/presentation/coordinators/passkey_coordinator.dart` (new),
  `lib/features/password_manager/di/password_manager_presentation_di.dart`,
  `test/features/password_manager/presentation/coordinators/passkey_coordinator_test.dart` (new).
  Acceptance: refuses on a locked session; writes `datedBackupPath` copy
  before the service call (Constitution VII, FR-010); reports a failed write
  with the backup path kept. Mirrors `EntryHistoryCoordinator.clearHistory`.
  Verify: fakes — locked refuses with no backup; backup precedes delete;
  failed delete keeps the backup and surfaces the error.

- [ ] **T205** [US1] Delete flow in BLoC and UI — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/presentation/bloc/vault/{vault_event,vault_bloc}.dart`,
  `lib/features/password_manager/presentation/screens/vault/vault_entry_passkeys.part.dart`,
  `lib/features/password_manager/presentation/screens/vault/vault_confirmations.part.dart`,
  matching tests.
  Acceptance: `DeletePasskey` event → coordinator → reload → success message.
  Confirmation names site and username, says it cannot be recovered and that
  a backup is written before anything happens.
  Verify: bloc test emits reload then message; widget test shows the
  confirmation and cancel changes nothing.

- [ ] **T206** [P] [US1] Duplicate pairing passkey + password — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/domain/models/duplicate_group.dart`,
  `lib/features/password_manager/data/services/vault_duplicate_service.dart`,
  `test/features/password_manager/data/services/vault_duplicate_service_test.dart`.
  Acceptance: `DuplicateGroup.kind` with `passkeyPassword`; third pass pairs a
  passkey-only entry with a password entry on the same normalized site and
  username (plan D10); `previewMerge` carries `passkeysToCopy` with protection
  intact and sets `passkeyConflict` when the primary already holds the same
  `(rpId, userHandle)`. Existing groups unchanged.
  Verify: E1 + E2 form one `passkeyPassword` group; two different passkeys on
  the same site are not duplicates; conflict flagged when both have passkeys
  for the same handle.

- [ ] **T207** [US1] Merge with a passkey in Vault health — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart`,
  `lib/features/password_manager/data/services/vault_kdbx_service.dart` (merge path),
  matching tests.
  Acceptance: the group is labelled as "same account, one holds the passkey";
  the merge confirmation names the passkey that moves and the backup; the
  merge writes the passkey fields on the primary protected; a conflict refuses
  with an explanation (FR-011a). Never automatic.
  Verify: service test merges E1 into E2 → E2 has the passkey, E1 in the bin,
  protection preserved; widget test shows the label and the refusal copy.

- [ ] **T208** [P] [US1] CSV import cannot inject passkey fields — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/data/services/vault_csv_import_service.dart`,
  `test/features/password_manager/data/services/vault_csv_import_service_test.dart`.
  Acceptance: a header starting `KPEX_PASSKEY_` is skipped with a warning
  entry in the import report; nothing is written under that key.
  Verify: import a CSV with `KPEX_PASSKEY_PRIVATE_KEY_PEM` → warning, entry
  has no such custom field.

- [ ] **T209** [P] [US1] Merge preview collapses the passkey — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/domain/models/merge_field_display.dart`,
  `lib/features/password_manager/data/services/kdbx_merge_adapter.dart`,
  matching tests.
  Acceptance: the `KPEX_PASSKEY_*` namespace appears as one field
  "Passkey (rpId)" with redacted sides; a per-field choice applies to the
  whole group so a merge never mixes two passkeys (FR-008, edge case).
  Verify: adapter test with a passkey changed on one side shows one row and
  resolves the whole group together.

- [ ] **T210** [P] [US1] Desktop metadata cache carries no passkey field — owner: `senior-web-chrome-dev`
  Files: `lib/features/password_manager/data/services/desktop_browser_autofill_cache.dart`,
  `test/features/password_manager/data/services/desktop_browser_autofill_cache_test.dart`.
  Acceptance: the mapper never emits a `KPEX_` key or a protected custom
  field; an entry with a passkey and an empty password is still skipped from
  the *password* cache (it has nothing to fill).
  Verify: mapper test on E1 and E3 asserts the JSON contains no `KPEX_` and no
  protected value.

- [ ] **T211** [US1] Goldens for the passkey surfaces — owner: `senior-tester`
  Files: `test/goldens/vault_entry_passkey_section_test.dart`,
  `test/goldens/vault_list_passkey_badge_test.dart`,
  `test/goldens/vault_passkey_delete_confirm_test.dart` (all new), PNGs.
  Acceptance: inventory in `plan.md` (section 390×844 light+dark, wide
  1024×768 light+dark, unusable 390×844 light, badge 390×844 dark, confirm
  390×844 light); contrast assertions on section text and note.
  Verify: both golden runs green (plain and randomized seed).

- [ ] **T212** [US1] KeePassXC round-trip on the fixture — owner: `senior-tester`
  Files: `specs/023-passkey-management/device-evidence.md`.
  Acceptance: quickstart A.4, B.1, C.2 executed on a desktop build against a
  copy of the T001 fixture, then the file opened in KeePassXC and E1 used to
  sign in on webauthn.io (SC-001).
  Verify: evidence rows filled with KeePassXC version and outcome.

## Phase 5 — US2: Sign in with a stored passkey — iOS and macOS (P2)

Goal: the credential provider extension answers passkey sign-in requests.
Independent test: quickstart D, on each platform.

- [ ] **T301** [US2] Publish passkeys to the sealed cache — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/domain/models/apple_autofill_v2_models.dart`,
  `lib/features/password_manager/data/services/apple_autofill_v2_method_channel_client.dart`,
  `lib/features/password_manager/presentation/coordinators/apple_autofill_v2_coordinator.dart`,
  matching tests.
  Acceptance: the publish entry gains the `passkey` block of
  `contracts/passkey_platform_bridges.md` for each usable passkey; an entry
  with a passkey and no password is published; result carries
  `passkeyPublishedCount`; the model's `toString` redacts the PEM.
  Verify: client test asserts the payload shape and that `toString` of the
  publish model contains no PEM; coordinator test publishes E1.

- [ ] **T302** [US2] Sealed store and metadata on Apple — owner: `senior-apple-dev`
  Files: `ios/CredentialProviderExtension/SharedAutofillStore.swift`,
  `macos/CredentialProviderExtension/SharedAutofillStore.swift`,
  `ios/Runner/*` and `macos/Runner/*` channel handlers that call it.
  Acceptance: `AutofillCredentialSecret.passkey` (optional, Codable);
  metadata gains `hasPasskey`, `passkeyRpId`, `passkeyCredentialId` only;
  entries without a password but with a passkey are stored, not skipped;
  `clearCredentials` wipes them with the rest (FR-023). `Logger` lines carry
  rpId only.
  Verify: Swift unit test (Runner test target) round-trips a secret with a
  passkey through seal/unseal and asserts the metadata JSON has no PEM.

- [ ] **T303** [US2] Assertion builder in Swift — owner: `senior-apple-dev`
  Files: `ios/CredentialProviderExtension/PasskeyAssertionBuilder.swift` (new,
  shared into the macOS extension target via the project file).
  Acceptance: builds `authenticatorData` per `data-model.md`; signs with
  CryptoKit `P256.Signing` (DER), `Curve25519.Signing` (raw), and `SecKey`
  for RSA; PKCS#8 parsing for all three; never logs the key.
  Verify: Swift unit test with the T002 vectors — bytes equal, signatures
  verify with the public keys.

- [ ] **T304** [US2] Passkey requests in the extension controllers — owner: `senior-apple-dev`
  Files: `ios/CredentialProviderExtension/CredentialProviderViewController.swift`,
  `macos/CredentialProviderExtension/MacCredentialProviderViewController.swift`,
  `ios/CredentialProviderExtension/CredentialListView.swift`,
  `macos/CredentialProviderExtension/CredentialListView.swift`,
  both `Info.plist` (`ProvidesPasskeys`).
  Acceptance: per the Apple table in `contracts/passkey_platform_bridges.md`:
  list filtered by rpId and `allowedCredentials`, empty →
  `credentialIdentityNotFound`; without-interaction →
  `userInteractionRequired`; interactive path runs `LAContext`
  `deviceOwnerAuthentication` every time (FR-015), then
  `completeAssertionRequest`; cancel → `userCanceled`. Password behaviour
  unchanged.
  Verify: builds for both targets; quickstart D.1–D.4 on device recorded in
  `device-evidence.md`; existing password autofill smoke still passes.

## Phase 6 — US2: Sign in with a stored passkey — Android (P2)

Goal: a Credential Manager provider serves passkeys on API 34+, and the app
says so below it.
Independent test: quickstart E.

- [ ] **T401** [US2] Publish passkeys to the Android sealed store — owner: `senior-android-dev`
  Files: `android/app/src/main/kotlin/dev/camillobucciarelli/kdbxKeyVault/autofill/{AndroidAutofillModels.kt,AndroidAutofillJson.kt,AndroidAutofillStore.kt,AndroidAutofillV2Channel.kt}`.
  Acceptance: the secret record gains the `passkey` block; metadata gains
  `hasPasskey`, `passkeyRpId`, `passkeyCredentialId`; an entry with a passkey
  and no password is stored (the `entry_without_password_skipped` warning
  applies only to entries with neither); `clearCredentials` wipes it.
  Verify: Kotlin unit test round-trips a passkey record through the AES-GCM
  seal and asserts the metadata file has no PEM.

- [ ] **T402** [P] [US2] Assertion builder in Kotlin — owner: `senior-android-dev`
  Files: `android/.../autofill/PasskeyAssertionBuilder.kt` (new), test under
  `android/app/src/test/`.
  Acceptance: `authenticatorData` per `data-model.md`; JCA signing for
  `SHA256withECDSA`, `Ed25519` (API 33+; below → unusable), `SHA256withRSA`
  from PKCS#8; `clientDataJSON` with `origin` from `callingAppInfo.origin` or
  `android:apk-key-hash:`; produces the WebAuthn `PublicKeyCredential` JSON.
  Verify: unit test with the T002 vectors.

- [ ] **T403** [US2] Credential provider service — owner: `senior-android-dev`
  Files: `android/app/build.gradle.kts` (`androidx.credentials:credentials`,
  current stable pinned in the task), `android/app/src/main/AndroidManifest.xml`,
  `android/app/src/main/res/xml/keyvault_credential_provider.xml` (new),
  `android/.../autofill/KeyVaultCredentialProviderService.kt` (new).
  Acceptance: service declared with `BIND_CREDENTIAL_PROVIDER_SERVICE`;
  `onBeginGetCredentialRequest` filters metadata by rpId and
  `allowCredentials` and returns one `PublicKeyCredentialEntry` per match with
  a `PendingIntent` to T404; no match → empty response. The autofill service
  of spec 016 is untouched.
  Verify: builds on API 34 SDK; instrumented or manual check that the
  provider appears in system settings on an API 34+ device.

- [ ] **T404** [US2] Per-assertion authentication activity — owner: `senior-android-dev`
  Files: `android/.../autofill/PasskeyAuthActivity.kt` (new), manifest entry.
  Acceptance: `BiometricPrompt` with `BIOMETRIC_STRONG | DEVICE_CREDENTIAL`
  on every request, never reading `AndroidAutofillAuthSession` (FR-015);
  success → secret → T402 → `PendingIntentHandler.setGetCredentialResponse`;
  cancel → `GetCredentialCancellationException`; missing →
  `NoCredentialException`.
  Verify: quickstart E.1 and E.3 recorded in `device-evidence.md`.

- [ ] **T405** [US2] API floor and settings row — owner: `senior-android-dev`, `senior-flutter-dev`
  Files: `android/.../MainActivity.kt` (component enable on start),
  `android/.../autofill/AndroidAutofillV2Channel.kt` (`getPasskeyProviderAvailability`),
  `lib/features/password_manager/data/services/apple_autofill_v2_method_channel_client.dart`,
  `lib/features/password_manager/presentation/screens/vault/vault_settings.part.dart`,
  matching tests.
  Acceptance: provider component enabled only when `SDK_INT >= 34`,
  re-evaluated on every start (plan D9); the settings row says passkey
  sign-in is not available on this device below 34 (FR-013). `minSdk` stays 29.
  Verify: widget test for both states of the row; quickstart E.2 on an API
  29–33 device recorded in `device-evidence.md`.

## Phase 7 — US2: Sign in with a stored passkey — Windows and Linux (P2)

Goal: the browser extension serves passkey sign-in through the native host and
the app, with the key never leaving the app.
Independent test: quickstart F.

- [ ] **T501** [US2] `passkeyAssert` in the native host protocol — owner: `senior-web-chrome-dev`
  Files: `tool/native_host_protocol.dart`, `tool/native_host.dart`,
  `test/tool/native_host_test.dart`.
  Acceptance: new type per `contracts/passkey_platform_bridges.md`;
  `hello` advertises `passkeyAssertV1` only when the app bridge descriptor
  lists it; `challenge` and `allowCredentials` in `_sensitiveRequestKeys`;
  forwarded to `/passkey-assert`; 64 KiB cap; an old host answers
  `unsupported_type`.
  Verify: protocol tests — round-trip, capability gating, sensitive keys not
  echoed in an error frame, response with a `privateKeyPem` key is rejected
  (never forwarded).

- [ ] **T502** [US2] `/passkey-assert` in the app bridge — owner: `senior-flutter-dev`
  Files: `lib/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart`,
  `lib/features/password_manager/data/services/desktop_browser_autofill_cache.dart` (descriptor capability),
  `lib/features/password_manager/presentation/coordinators/desktop_browser_autofill_coordinator.dart`,
  `lib/features/password_manager/presentation/screens/vault/vault_dialogs.part.dart`,
  matching tests.
  Acceptance: requires an unlocked session; checks rpId against the origin's
  effective domain or a registrable suffix; finds usable passkeys for the
  rpId (and `allowCredentials`); raises the in-app confirmation naming site
  and username on every request (FR-015); signs with T014; answers the
  contract shape; `reason` codes for every failure. No PEM in any response
  or log.
  Verify: service tests with fakes for each reason code; rpId mismatch
  refused; confirmation declined → `declined`; success payload verifies with
  the vector public key.

- [ ] **T503** [US2] Page-world interception in the extension — owner: `senior-web-chrome-dev`
  Files: `desktop/browser_extension/passkey_page_bridge.js` (new),
  `desktop/browser_extension/content_overlay.js`,
  `desktop/browser_extension/overlay_lifecycle.js`,
  `desktop/browser_extension/background.js`,
  `desktop/browser_extension/manifest.json` (version bump only),
  `desktop/browser_extension/test/`.
  Acceptance: MAIN-world script registered alongside the overlay script on
  granted hosts; wraps `navigator.credentials.get` with a per-page nonce;
  relays to the background, which sends `passkeyAssert`; on `ok:true`
  resolves a `PublicKeyCredential`-shaped object (research R12, including
  `toJSON()`); on `ok:false` or `unsupported_type` calls the original
  function so the browser's own UI appears. `create` is not wrapped.
  Verify: extension unit tests for the wrapper (fallthrough, nonce check,
  result shape); `serve_harness.sh` page exercises a fake host; quickstart
  F.1–F.5 recorded in `device-evidence.md` on Windows and Linux.

- [ ] **T504** [P] [US2] Update note for the extension — owner: `senior-web-chrome-dev`
  Files: `desktop/browser_extension/README.md`, `desktop/browser_extension/store_assets/`.
  Acceptance: explains that the extension now answers passkey sign-in on
  granted sites, that the key stays in the app, and that the app asks before
  each use (Assumptions).
  Verify: text present; no permission added to `permissions`.

## Phase 8 — Polish and verification gate

- [ ] **T601** Redaction sweep — owner: `senior-tester`
  Files: none new; `specs/023-passkey-management/device-evidence.md`.
  Acceptance: quickstart G — the grep hits only the parser's PEM header
  constant; verbose logs from one run of A, D, E and F contain no
  `PRIVATE KEY` (SC-002).
  Verify: evidence row with the grep output summary and log sizes.

- [ ] **T602** [P] Contrast and accessibility assertions — owner: `senior-tester`
  Files: `test/features/password_manager/presentation/accessibility/passkey_contrast_test.dart` (new).
  Acceptance: every new text/background pairing ≥ 4.5:1 in light and dark;
  badge has a semantic label; delete action ≥ 44×44 with a focus ring
  (Constitution V).
  Verify: tests green.

- [ ] **T603** Full quickstart run and board sync — owner: `senior-tester`
  Files: `specs/023-passkey-management/device-evidence.md`, `tasks.md`.
  Acceptance: sections A–G executed, every D–F row filled with device and
  version; `fvm flutter analyze` clean; `fvm flutter test` green with the
  before/after test count recorded here; `PROJECT_NUMBER=2
  tool/sync_spec_project.sh` run and the board state reported.
  Verify: this box is the last one ticked.

## Dependencies

```
T001 T002 T003 (parallel)
   └─▶ T010 ─▶ T011 T012 T014 (parallel) ─▶ T013
                    ├─▶ US1b: T101 T102 (after T010) · T103 [P] · T104
                    ├─▶ US1:  T201 T206 T208 T209 T210 [P] · T202 ─▶ T203 ─▶ T204 ─▶ T205 · T207 (after T206) · T211 · T212
                    ├─▶ Apple:   T301 ─▶ T302 ─▶ T303 ─▶ T304
                    ├─▶ Android: T401 · T402 [P] ─▶ T403 ─▶ T404 ─▶ T405
                    └─▶ Desktop: T501 · T502 (after T014) ─▶ T503 · T504 [P]
                                        └─▶ T601 T602 [P] ─▶ T603
```

US1b depends only on T010. US1 depends on T011–T013. The three US2 platform
phases depend on T013 and are independent of each other and of US1's UI.

### Parallel opportunities

- Phase 1 entirely; T011, T012, T014 together after T010.
- US1b and US1 UI in parallel once T013 lands (different part files).
- Apple, Android and desktop phases in parallel, one owner each.
- T206/T208/T209/T210 alongside T202–T205.

## Implementation strategy

1. **Bug fix first**: T010 alone is a shippable fix (protected custom fields
   stop being downgraded) and goes in before anything else.
2. **MVP**: Phase 2 + US1b + US1 — the vault holds passkeys and secret fields
   correctly on every platform with no native code touched.
3. **Then one platform at a time**, Apple first (least new code), Android,
   desktop. Each is independently releasable; a beta may ship with any subset
   and the spec's per-platform scenarios say what each subset proves.
4. **Gate**: Phase 8 closes the spec for the beta; US3 stays unplanned.
