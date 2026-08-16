# 011 — Master password session scope

**Status**: Draft · **not started**
**Kind**: Security fix
**Depends on**: 003 (database selection & unlock), 006 (security, autofill, extension)
**Constitution**: governed by principle I (secrets never leak into the shell) and
principle II (clean architecture layering)

## Problem

The master password in plaintext is written to the platform keystore on every
unlock, for every database, whether or not biometric unlock is enabled, and it
is not removed when the process dies.

`SecureDataSourceImpl` (`lib/features/password_manager/data/datasources/secure_data_source.dart:10`)
stores it under the single global key `'MASTER_PASSWORD'`.

Write sites, none gated on `biometricProtectionEnabled`:

| Site | Context |
| --- | --- |
| `database_session_coordinator.dart:820` | `unlockWithManualCredentials` — the ordinary unlock path of every user |
| `database_session_coordinator.dart:615` | database creation, written even when the biometric flag is `false` |
| `database_session_coordinator.dart:566` | rollback restore of the previous value |
| `vault_session_coordinator.dart:263` | master password change |
| `vault_session_coordinator.dart:346` | re-save after a vault operation |

### Why this is not a missing `if`

Secure storage is currently the **transport** for the session password across
the BLoC boundary, not an opt-in biometric cache. `VaultBloc` reads it once at
`InitializeVault` (`vault_bloc.dart:148`) into the field `_password`
(`vault_bloc.dart:119`) and passes that value to roughly twenty vault and sync
operations. `unlockWithStoredCredentials` (`database_session_coordinator.dart:828`)
and `hasStoredMasterPassword` (`:841`) read the same entry for the biometric
path. Gating the writes without replacing the transport breaks every save and
every sync.

Two distinct concerns are conflated in one keystore entry and must be separated:

1. **Session secret** — must exist only while a vault is unlocked, and must live
   in memory, never on disk.
2. **Biometric credential** — is deliberately persistent, and must exist only
   when the user enabled biometric protection for that specific database.

### Aggravating conditions

- `vault_shell.part.dart:322` — `case AppLifecycleState.detached: break;`. With
  no cleanup on termination, a process killed without an explicit lock leaves
  the plaintext master password in the keystore across reboots, including when
  biometric protection is off.
- `updateBiometricProtection` (`database_session_coordinator.dart:783-805`)
  persists only the profile. Turning biometric protection **off does not remove
  an already stored password**.
- `database_security_repository_impl.dart:45` defaults
  `biometricProtectionEnabled` to `true` when the field is absent. Every profile
  written before this spec is therefore read back as biometric-enabled, so a
  naive gate keeps persisting for the entire existing install base.
- The key `'MASTER_PASSWORD'` is global, not per database. With several vaults
  the stored value belongs to whichever was unlocked last, so a biometric unlock
  of vault A can be attempted with the password of vault B.

### Impact

- Contradicts constitution principle I: plaintext lifetime is currently
  unbounded, extending past process death.
- `PRIVACY.md` had to be weakened to describe this behaviour. The strong,
  accurate claim can only be restored by this fix.
- The threat this defeats is real for a password manager: keystore extraction on
  a rooted, jailbroken, or forensically imaged device recovers the master
  password, and therefore every entry, without the user ever having opted into
  persistent storage.

## Approved product behavior

- Unlocking, saving, syncing, changing the master password and using biometric
  unlock all keep working exactly as they do today. No user-visible flow changes.
- With biometric protection **off** for a database, the master password is never
  written to the keystore. It exists in memory for the duration of the unlocked
  session only.
- With biometric protection **on** for a database, the master password is stored
  in the keystore under a key scoped to that database, and is used only to serve
  a biometric unlock of that same database.
- Turning biometric protection off removes the stored credential for that
  database immediately.
- Locking the vault, switching database, and terminating the application all
  drop the in-memory session secret.
- Existing installs are migrated once: the legacy global `'MASTER_PASSWORD'`
  entry is deleted at startup and re-established per database only where the
  user has genuinely enabled biometric protection.

## Functional requirements

**FR-1 — Session secret holder.** A session-scoped holder owns the master
password in memory for the unlocked session. It lives behind the coordinator
layer per constitution principle II. `VaultBloc` obtains the session secret from
it instead of reading `SecureDataSource` at `vault_bloc.dart:148`.

**FR-2 — Session secret lifetime.** The holder is populated on successful unlock
and cleared on lock, on database switch, on unlock failure, and on
`AppLifecycleState.detached`. After clearing, a vault operation that needs the
password fails with the existing locked-state error rather than proceeding with
an empty string. The current silent `?? ''` fallback is removed: an absent
session secret is an error, not an empty password.

**FR-3 — Keystore writes are gated.** Every one of the five write sites listed
above persists only when `biometricProtectionEnabled` is `true` for the target
database. The flag is read from `DatabaseSecurityProfile`, resolved by database
id, never assumed.

**FR-4 — Per-database key.** The keystore key is derived from the database id,
not the global constant `'MASTER_PASSWORD'`. A biometric unlock of a database
reads only its own entry.

**FR-5 — Disabling biometrics erases.** `updateBiometricProtection(enabled: false)`
deletes the stored credential for that database in the same operation that
persists the profile. Deleting or unregistering a database deletes its entry too.

**FR-6 — Migration.** On first run after this change, the legacy global
`'MASTER_PASSWORD'` entry is deleted unconditionally. It is not copied into a
per-database entry, because the value cannot be reliably attributed to a
database. Users with biometric protection enabled re-establish it at their next
manual unlock. This is a one-time, silent re-enrolment; no data is lost and the
vault file is never touched.

**FR-7 — Default flag corrected.** The `?? true` default at
`database_security_repository_impl.dart:45` becomes `?? false`. Absence of the
flag must not be read as consent to persist a secret. Profiles that legitimately
have biometrics enabled carry the field explicitly.

**FR-8 — Autofill parity.** The Apple credential provider and the desktop native
messaging bridge continue to receive exactly the credentials they receive today
and no more. Their code path is verified against FR-1 through FR-5, not assumed
to be unaffected.

**FR-9 — Privacy policy restored.** `PRIVACY.md` returns to the strict claim:
the master password reaches the keystore only when the user enables biometric
unlock. The line is updated in the same change that makes it true, never before.

## Acceptance criteria

**AC-1.** With biometric protection off: unlock a vault, then inspect the
platform secure store. No entry contains the master password. Verified on
Android and on at least one Apple platform.

**AC-2.** With biometric protection off: unlock, kill the process without
locking, restart. No entry contains the master password, and the app requires
the password again.

**AC-3.** With biometric protection on: unlock, kill the process, restart,
unlock with biometrics. Succeeds, exactly as today.

**AC-4.** Enable biometric protection, then disable it. The stored credential is
gone immediately, before the app is restarted.

**AC-5.** Two databases, biometrics enabled only on A. Unlock B manually, then
biometric-unlock A. A succeeds with its own credential; no entry exists for B.

**AC-6.** Upgrade path: install a build from before this spec, unlock to create
the legacy global entry, upgrade to the new build. The legacy entry is gone
after first launch, and the vault still opens with the master password.

**AC-7.** No regression in vault save, entry edit, master password change,
Drive sync, Apple autofill, or desktop browser autofill.

**AC-8.** No plaintext master password appears in any log, `props`, `toString`,
or error message, per constitution principle I.

## Test plan

Automated, required before merge:

- Coordinator tests asserting the FR-3 gate for each of the five write sites,
  both flag states. This invariant has **no test coverage today**.
- Coordinator test for FR-5: disabling biometrics erases.
- Coordinator test for FR-2: the session secret is cleared on lock, on database
  switch, and on `detached`; a vault operation after clearing raises the locked
  error instead of using an empty password.
- Migration test for FR-6: a pre-existing global entry is deleted on first run.
- Repository test for FR-7: an absent flag deserialises to `false`.
- `VaultBloc` tests updated for the FR-1 source change, covering the case where
  the session secret is absent.

Manual, per platform, recorded in the task list with a pass/fail per platform:

- Keystore inspection for AC-1, AC-2, AC-5 on Android and Apple. Desktop secure
  store inspection on macOS, Linux and Windows, or the platform is recorded as
  `not-run` rather than assumed passing.
- Biometric unlock on Android and Apple for AC-3.
- Apple autofill and desktop browser autofill smoke test for FR-8.

Host evidence never qualifies another platform.

## Out of scope

- Holding the master password as a locked or obfuscated buffer in memory, or
  zeroing it after use. Dart offers no reliable guarantee here; this spec bounds
  the *lifetime and location*, not the in-process memory representation.
- Replacing `flutter_secure_storage`, or adding hardware-backed key attestation.
- Requiring biometric or device-credential authentication on read of the stored
  credential. Worth a separate spec; it changes the unlock UX.
- Any change to KDBX key derivation or vault encryption.

## Risks

| Risk | Mitigation |
| --- | --- |
| Breaking unlock, save or sync for every user: the change sits on the hottest path in the application | FR-1 lands first with the transport swapped and behaviour unchanged; gating in FR-3 follows as a separate reviewable step |
| Users with biometrics enabled are silently re-enrolled by FR-6 | Accepted and documented. The alternative, migrating an unattributable secret, is worse |
| `?? false` in FR-7 disables biometrics for profiles that relied on the implicit default | Intended: implicit consent to persist a secret is not consent. Users re-enable it explicitly |
| Desktop secure stores behave differently across Linux backends | Platforms are recorded per AC, never inferred from macOS |

## Definition of done

- All acceptance criteria met, with the per-platform matrix filled in and any
  uncovered platform explicitly marked `not-run`.
- `flutter analyze` clean; `flutter test` green excluding goldens, per the CI
  convention; goldens green locally.
- `PRIVACY.md` FR-9 line updated in the same change.
- Validated by `senior-tester`, including the keystore inspection steps, which
  are not automatable in this repository.
