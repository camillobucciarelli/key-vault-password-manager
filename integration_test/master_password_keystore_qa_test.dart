// spec 011 AC-1 / AC-2 / AC-6 — keystore lifecycle probe, on a real device.
//
// Test infrastructure only: no CI job runs this and `flutter test` never
// collects `integration_test/` (AGENTS.md > Testing Guidelines). Run phase
// pairs through `tool/run_ios_keystore_qa.sh`: its `--no-uninstall` preserves
// the fixture while Flutter still stops the first process.
//
// ---------------------------------------------------------------------------
// WHY THIS EXISTS: iOS has no keychain dump.
// ---------------------------------------------------------------------------
// `docs/manual-qa.md` could give a real inspection command for Android
// (`run-as` + the SharedPreferences XML), macOS (`security find-generic-
// password`) and Linux (`secret-tool`), and none at all for iOS, because there
// is no supported way to read a third-party app's keychain on a device that is
// not jailbroken. The app asking itself is the only honest route, and it makes
// the SAME check runnable on all five platforms instead of four.
//
// ---------------------------------------------------------------------------
// SECURITY: why this cannot leak a master password, structurally.
// ---------------------------------------------------------------------------
// The constraint from spec 011 constitution principle I is that a probe must
// not be able to reveal the secret and must not exist in a release build.
// Both are satisfied by construction rather than by care:
//
//  1. IT IS NOT IN THE APP. This is a file under `integration_test/`, which
//     `flutter build` never compiles into any artifact, debug or release.
//     There is no debug screen, no build flavor, no `kDebugMode` branch and
//     no new production code — so there is nothing that could be shipped by
//     accident, and nothing to remember to remove. A build-flavor-gated
//     screen would have been a real release-surface risk; this has none.
//
//  2. THE PRESENCE PRIMITIVE IS ALREADY PRODUCTION CODE AND ALREADY A BOOL.
//     `DatabaseSessionCoordinator.hasStoredMasterPassword()` returns `bool`.
//     The probe adds no new way to read the keystore that the app did not
//     already have.
//
//  3. NO REPORTER IN THIS FILE ACCEPTS A STRING. Only [sayBool] and [sayInt]
//     exist. `sayBool('X', secret)` does not compile, and neither does
//     `sayInt`. Reporting a secret is a type error, not a review finding.
//     The raw key inventory is reduced to counts before anything is printed,
//     and VALUES are never read at all — `readAll()` is used for its key set,
//     which is the same thing the Android `grep` in `docs/manual-qa.md` looks
//     at.
//
//  4. EVERY ASSERTION IS ON A BOOL OR AN INT. Assertion output is printed
//     output: `expect(keys, isEmpty)` would dump key names on failure, and
//     failures are exactly the runs whose transcript gets pasted into a bug
//     report. Same discipline as `expectPortable` in the iOS harness.
//
// ---------------------------------------------------------------------------
// PHASES
// ---------------------------------------------------------------------------
//   AC-2 (nothing survives a process kill):
//     --dart-define=QA_PHASE=ac2_unlock     unlock, biometrics off, do NOT lock
//     <the test run ending IS the process kill>
//     --dart-define=QA_PHASE=ac2_relaunch   assert absent + password required
//
//   AC-6 (upgrade from a pre-011 build):
//     --dart-define=QA_PHASE=ac6_seed       plant the legacy global entry
//     --dart-define=QA_PHASE=ac6_upgrade    first launch deletes it, vault opens
//
// The `ac6_seed` phase stands in for "install the pre-`027641d` build and
// unlock once". It writes the legacy global `MASTER_PASSWORD` key that the old
// build wrote, which is the precondition AC-6 needs; what it deliberately does
// NOT do is prove the old build wrote that key. Keep the archived-APK run in
// `docs/manual-qa.md` if you want that half — see S1-5's note there.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';
import 'package:password_manager/injection_container.dart' as di;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _phase = String.fromEnvironment('QA_PHASE', defaultValue: 'ac2_unlock');
const _dbName = 'qa_keystore_probe.kdbx';
const _password = 'QaKeystoreProbe!2026';
const _ac2Scenario = 2;
const _ac6Scenario = 6;

typedef _PhaseMarker = ({int scenario, int processId, String databaseId});

Future<bool> _writePhaseMarker(
  File file, {
  required int scenario,
  required String databaseId,
}) async {
  try {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'scenario': scenario,
        'processId': pid,
        'databaseId': databaseId,
      }),
      flush: true,
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<_PhaseMarker?> _readPhaseMarker(File file) async {
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    final scenario = decoded['scenario'];
    final processId = decoded['processId'];
    final databaseId = decoded['databaseId'];
    if (scenario is! int ||
        processId is! int ||
        databaseId is! String ||
        databaseId.isEmpty) {
      return null;
    }
    return (scenario: scenario, processId: processId, databaseId: databaseId);
  } catch (_) {
    return null;
  }
}

Future<bool> _deletePhaseMarker(File file) async {
  try {
    if (await file.exists()) await file.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// The only two reporters in this file. There is deliberately no `String`
/// overload: a secret cannot be printed because no function here accepts one.
void sayBool(String key, bool value) {
  // ignore: avoid_print
  print('QA|$key|$value');
}

void sayInt(String key, int value) {
  // ignore: avoid_print
  print('QA|$key|$value');
}

/// Present, absent, or *could not be determined*.
///
/// The third value is the whole reason this is not a `bool`. On macOS the
/// keychain can answer `errSecInteractionNotAllowed` (-25308) to a
/// non-interactive process; a `catch (_) { return false; }` around that would
/// turn "the keystore refused to answer" into "there is no entry", and this
/// probe's entire job is to prove absence. An indeterminate reading is
/// reported and FAILS the item — it is never quietly upgraded to a pass, the
/// same rule `docs/manual-qa.md` states for `not-run`.
enum Presence { present, absent, indeterminate }

/// Counts of master-password-shaped keys the app owns, and nothing else.
///
/// `readAll()` returns a `Map<String, String>` — key to VALUE. The values are
/// never bound to a variable, never inspected and never returned: only
/// `.keys` is touched, and only to classify and count. This is the same
/// question the Android XML `grep` in `docs/manual-qa.md` asks, expressed so
/// that iOS can answer it too.
class _KeystoreCensus {
  const _KeystoreCensus({
    required this.legacyGlobal,
    required this.ownEntry,
    required this.perDatabaseCount,
    required this.totalKeys,
    required this.readable,
  });

  /// The bare `MASTER_PASSWORD` key spec 011 FR-6 must delete. Must be absent
  /// after any launch of a post-slice-3 build.
  final Presence legacyGlobal;

  /// `MASTER_PASSWORD.<id>` for THE DATABASE UNDER TEST.
  ///
  /// This, not [perDatabaseCount], is what AC-1/AC-2 assert on. AC-5's
  /// correct state is a device that holds an entry for a DIFFERENT vault —
  /// the one with biometrics on — so an unscoped "zero entries anywhere"
  /// assertion would fail on a device that is behaving perfectly, and on any
  /// developer machine that has ever run the app. Scoping it is not a
  /// weakening: `MASTER_PASSWORD.<id of A>` is the exact name spec 011 AC-1
  /// names.
  final Presence ownEntry;

  /// Every `MASTER_PASSWORD.<databaseId>` entry the app owns, including other
  /// vaults'. Reported as context, never asserted on — see [ownEntry].
  /// `-1` when the store could not be enumerated.
  final int perDatabaseCount;

  final int totalKeys;

  /// False when the platform keystore refused to answer at all.
  final bool readable;

  static Future<_KeystoreCensus> take(
    FlutterSecureStorage storage, {
    required String? databaseId,
  }) async {
    const legacy = SecureDataSourceImpl.legacyMasterPasswordKey;
    Set<String> keys;
    try {
      keys = (await storage.readAll()).keys.toSet();
    } catch (_) {
      // Deliberately NOT "absent". See [Presence].
      return const _KeystoreCensus(
        legacyGlobal: Presence.indeterminate,
        ownEntry: Presence.indeterminate,
        perDatabaseCount: -1,
        totalKeys: -1,
        readable: false,
      );
    }
    return _KeystoreCensus(
      legacyGlobal: keys.contains(legacy) ? Presence.present : Presence.absent,
      ownEntry: databaseId == null
          ? Presence.indeterminate
          : keys.contains(SecureDataSourceImpl.masterPasswordKey(databaseId))
          ? Presence.present
          : Presence.absent,
      perDatabaseCount: keys.where((k) => k.startsWith('$legacy.')).length,
      totalKeys: keys.length,
      readable: true,
    );
  }

  void report(String prefix) {
    sayBool('${prefix}_KEYSTORE_READABLE', readable);
    sayInt('${prefix}_LEGACY_GLOBAL', legacyGlobal.index);
    sayInt('${prefix}_OWN_ENTRY', ownEntry.index);
    sayInt('${prefix}_PER_DATABASE_ENTRIES_ALL_VAULTS', perDatabaseCount);
    sayInt('${prefix}_TOTAL_KEYS', totalKeys);
  }
}

/// Asserts [actual] is exactly [expected], and treats
/// [Presence.indeterminate] as a distinct, louder failure.
///
/// The message matters: "the keystore could not be read" and "the keystore
/// says the entry is there" are opposite findings, and collapsing them into
/// one red is how an unreadable keystore gets written down as a pass.
void expectPresence(String what, Presence actual, Presence expected) {
  if (actual == Presence.indeterminate) {
    fail(
      '$what could not be determined: the platform keystore refused to '
      'answer. This is NOT evidence of absence. On macOS this is usually '
      'errSecInteractionNotAllowed (-25308) — the login keychain will not '
      'serve a non-interactive process. Record the item not-run with this '
      'reason, or use the `security` command in docs/manual-qa.md instead.',
    );
  }
  expect(
    actual == expected,
    isTrue,
    reason: '$what is ${actual.name}, expected ${expected.name}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseSessionCoordinator coordinator;
  late DatabaseRegistryRepository registry;
  late FlutterSecureStorage storage;
  late File phaseMarkerFile;

  setUpAll(() async {
    // `di.init()` is the FR-6 migration point: it calls
    // `deleteLegacyMasterPassword()` unconditionally on every startup. The
    // `ac6_upgrade` phase depends on that happening HERE, exactly as it does
    // on a real first launch after the upgrade.
    await di.init();
    coordinator = di.sl<DatabaseSessionCoordinator>();
    registry = di.sl<DatabaseRegistryRepository>();
    storage = di.sl<FlutterSecureStorage>();
    final documents = await getApplicationDocumentsDirectory();
    phaseMarkerFile = File(
      p.join(documents.path, 'metadata', 'qa_keystore_phase.json'),
    );
  });

  /// The vault this probe owns, created on demand. Never a user's vault.
  Future<String> ensureVault() async {
    final existing = (await registry.list())
        .where((r) => r.canonicalPath.contains('qa_keystore_probe'))
        .toList();
    if (existing.isNotEmpty) {
      sayBool('VAULT_REUSED_FROM_PREVIOUS_PHASE', true);
      return existing.single.canonicalPath;
    }
    final result = await coordinator.createNewDatabase(
      databaseFileName: _dbName,
      password: _password,
      biometricProtectionEnabled: false,
      generateKeyFile: false,
    );
    sayBool('VAULT_CREATED', result.path != null);
    expect(result.path, isNotNull, reason: 'could not create the probe vault');
    return result.path!;
  }

  Future<DatabaseRecord> requirePriorPhase(int expectedScenario) async {
    final marker = await _readPhaseMarker(phaseMarkerFile);
    final markerFound = marker != null;
    sayBool('CROSS_PROCESS_MARKER_FOUND', markerFound);
    expect(
      markerFound,
      isTrue,
      reason:
          'the phase-1 marker is absent: the app container was reset or phase '
          '1 did not complete. Use tool/run_ios_keystore_qa.sh.',
    );
    final phaseMatches = marker!.scenario == expectedScenario;
    sayBool('CROSS_PROCESS_PHASE_MATCHES', phaseMatches);
    expect(phaseMatches, isTrue, reason: 'wrong phase-1 marker');
    final newProcess = marker.processId != pid;
    sayBool('CROSS_PROCESS_PID_CHANGED', newProcess);
    expect(
      newProcess,
      isTrue,
      reason: 'phase 2 is still running in the phase-1 process',
    );

    final records = (await registry.list())
        .where((r) => r.canonicalPath.contains('qa_keystore_probe'))
        .toList();
    expect(
      records.length,
      1,
      reason:
          'no retained probe vault from phase 1. Use the runner on the same '
          'device without uninstalling.',
    );
    final record = records.single;
    final sameDatabaseIdentity = marker.databaseId == record.databaseId;
    sayBool('SAME_DATABASE_IDENTITY', sameDatabaseIdentity);
    expect(
      sameDatabaseIdentity,
      isTrue,
      reason:
          'phase 2 resolved a different database identity; an equivalent new '
          'vault does not qualify',
    );
    return record;
  }

  test('spec 011 keystore lifecycle — phase $_phase', () async {
    sayInt('PHASE_IS_AC2_UNLOCK', _phase == 'ac2_unlock' ? 1 : 0);
    sayInt('PHASE_IS_AC2_RELAUNCH', _phase == 'ac2_relaunch' ? 1 : 0);
    sayInt('PHASE_IS_AC6_SEED', _phase == 'ac6_seed' ? 1 : 0);
    sayInt('PHASE_IS_AC6_UPGRADE', _phase == 'ac6_upgrade' ? 1 : 0);

    switch (_phase) {
      // ---------------------------------------------------------------
      // AC-1 + AC-2, first half: unlock for real, biometrics off, and do
      // not lock. The process dying at the end of this run IS the kill.
      // ---------------------------------------------------------------
      case 'ac2_unlock':
        final path = await ensureVault();

        await coordinator.unlockWithManualCredentials(
          databasePath: path,
          password: _password,
          keyFilePath: null,
        );
        sayBool('UNLOCKED', true);

        final record = (await registry.list()).firstWhere(
          (r) => r.canonicalPath == path,
        );

        // AC-1: an unlock with biometrics off must write nothing FOR THIS
        // DATABASE. Other vaults' entries are none of this item's business.
        final census = await _KeystoreCensus.take(
          storage,
          databaseId: record.databaseId,
        );
        census.report('AFTER_UNLOCK');
        expectPresence(
          'the legacy global entry (FR-6)',
          census.legacyGlobal,
          Presence.absent,
        );
        expectPresence(
          'this database\'s master password with biometrics off (AC-1)',
          census.ownEntry,
          Presence.absent,
        );
        expect(
          await coordinator.hasStoredMasterPassword(databasePath: path),
          isFalse,
          reason: 'the app itself reports a stored credential it must not have',
        );

        // POSITIVE CONTROL. Without this the whole probe is worthless: a
        // presence check hard-wired to `false` would pass every assertion
        // above. Prove it can say `true`, then put the keystore back.
        await di.sl<SecureDataSource>().saveMasterPassword(
          record.databaseId,
          _password,
        );
        final seeded = await _KeystoreCensus.take(
          storage,
          databaseId: record.databaseId,
        );
        seeded.report('POSITIVE_CONTROL');
        expectPresence(
          'the deliberately-seeded control entry — if this is not observed, '
          'the probe cannot see entries at all and its absence findings '
          'prove nothing',
          seeded.ownEntry,
          Presence.present,
        );
        expect(
          await coordinator.hasStoredMasterPassword(databasePath: path),
          isTrue,
          reason: 'hasStoredMasterPassword is stuck on false',
        );
        await di.sl<SecureDataSource>().clearMasterPassword(record.databaseId);
        final cleaned = await _KeystoreCensus.take(
          storage,
          databaseId: record.databaseId,
        );
        cleaned.report('AFTER_CONTROL_CLEANUP');
        expectPresence(
          'the control entry after cleanup',
          cleaned.ownEntry,
          Presence.absent,
        );

        final markerWritten = await _writePhaseMarker(
          phaseMarkerFile,
          scenario: _ac2Scenario,
          databaseId: record.databaseId,
        );
        sayBool('CROSS_PROCESS_MARKER_WRITTEN', markerWritten);
        expect(
          markerWritten,
          isTrue,
          reason: 'could not persist the non-secret cross-process marker',
        );

        sayBool('AC2_UNLOCK_PHASE_COMPLETE', true);

      // ---------------------------------------------------------------
      // AC-2, second half: after the kill, nothing persisted and the app
      // demands the master password again.
      // ---------------------------------------------------------------
      case 'ac2_relaunch':
        final record = await requirePriorPhase(_ac2Scenario);
        final path = record.canonicalPath;

        final census = await _KeystoreCensus.take(
          storage,
          databaseId: record.databaseId,
        );
        census.report('AFTER_KILL');
        expectPresence(
          'the legacy global entry after the kill',
          census.legacyGlobal,
          Presence.absent,
        );
        expectPresence(
          'this database\'s master password after a process kill (AC-2)',
          census.ownEntry,
          Presence.absent,
        );
        expect(
          await coordinator.hasStoredMasterPassword(databasePath: path),
          isFalse,
        );

        // The behavioural half: with nothing stored and no key file, the
        // stored-credential unlock path must refuse, which is what makes the
        // UI ask for the password again.
        var refused = false;
        try {
          await coordinator.unlockWithStoredCredentials(
            databasePath: path,
            keyFilePath: null,
          );
        } catch (_) {
          refused = true;
        }
        sayBool('STORED_CREDENTIAL_UNLOCK_REFUSED', refused);
        expect(
          refused,
          isTrue,
          reason:
              'the vault opened without a password after a kill — AC-2 is '
              'violated and this is a security failure, not a bug',
        );

        // And the password still works, so the refusal above is "no stored
        // secret", not "the vault is broken".
        await coordinator.unlockWithManualCredentials(
          databasePath: path,
          password: _password,
          keyFilePath: null,
        );
        sayBool('MANUAL_UNLOCK_STILL_WORKS', true);
        expect(
          await _deletePhaseMarker(phaseMarkerFile),
          isTrue,
          reason: 'could not consume the cross-process marker',
        );

      // ---------------------------------------------------------------
      // AC-6, first half: plant the legacy global entry a pre-011 build
      // left behind. Written AFTER `di.init()`, which would delete it.
      // ---------------------------------------------------------------
      case 'ac6_seed':
        final path = await ensureVault();
        final record = (await registry.list()).firstWhere(
          (r) => r.canonicalPath == path,
        );
        await storage.write(
          key: SecureDataSourceImpl.legacyMasterPasswordKey,
          value: _password,
        );
        final census = await _KeystoreCensus.take(storage, databaseId: null);
        census.report('AFTER_SEED');
        expectPresence(
          'the planted legacy entry — without it the ac6_upgrade phase '
          'proves nothing, exactly the "old build is not old enough" trap '
          'S1-5 warns about',
          census.legacyGlobal,
          Presence.present,
        );
        final markerWritten = await _writePhaseMarker(
          phaseMarkerFile,
          scenario: _ac6Scenario,
          databaseId: record.databaseId,
        );
        sayBool('CROSS_PROCESS_MARKER_WRITTEN', markerWritten);
        expect(
          markerWritten,
          isTrue,
          reason: 'could not persist the non-secret cross-process marker',
        );
        sayBool('AC6_SEED_PHASE_COMPLETE', true);

      // ---------------------------------------------------------------
      // AC-6, second half: `di.init()` in `setUpAll` already ran the FR-6
      // deletion. Assert it happened and the vault still opens.
      // ---------------------------------------------------------------
      case 'ac6_upgrade':
        final record = await requirePriorPhase(_ac6Scenario);

        final census = await _KeystoreCensus.take(
          storage,
          databaseId: record.databaseId,
        );
        census.report('AFTER_UPGRADE_LAUNCH');
        expectPresence(
          'the legacy global entry after the first launch of the upgraded '
          'build (FR-6 / AC-6)',
          census.legacyGlobal,
          Presence.absent,
        );

        await coordinator.unlockWithManualCredentials(
          databasePath: record.canonicalPath,
          password: _password,
          keyFilePath: null,
        );
        sayBool('VAULT_STILL_OPENS_AFTER_UPGRADE', true);
        expect(
          await _deletePhaseMarker(phaseMarkerFile),
          isTrue,
          reason: 'could not consume the cross-process marker',
        );

      default:
        fail(
          'unknown QA_PHASE. Use ac2_unlock, ac2_relaunch, ac6_seed or '
          'ac6_upgrade.',
        );
    }
  });
}
