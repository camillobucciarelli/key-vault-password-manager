// QA-authored iOS runtime probe for the portable-database-path fix (#41).
// Test infrastructure only: no CI job runs this, and `flutter test` never
// collects `integration_test/`. See AGENTS.md > Testing Guidelines.
//
// Run in two phases around a simulator container relocation:
//   --dart-define=QA_PHASE=create   (before the relocation)
//   --dart-define=QA_PHASE=verify   (after  the relocation)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:password_manager/core/utils/mobile_file_storage.dart';
import 'package:password_manager/core/utils/portable_path.dart';
import 'package:password_manager/features/password_manager/data/repositories/database_registry_repository_impl.dart';
import 'package:password_manager/features/password_manager/domain/models/database_selection_item.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_security_repository.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';
import 'package:password_manager/injection_container.dart' as di;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _phase = String.fromEnvironment('QA_PHASE', defaultValue: 'create');
const _dbName = 'qa_vault.kdbx';
const _password = 'QaRuntimeProbe!2026';

/// Host-side stash. Simulator apps run as the host user, so the test can carry
/// `Documents/` across the uninstall/reinstall that rotates the container UUID
/// -- exactly what an iOS data-preserving reinstall does.
const _stash = '/tmp/qa_docs_backup';

Future<void> copyTree(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final e in from.list(recursive: true, followLinks: false)) {
    final rel = p.relative(e.path, from: from.path);
    if (e is Directory) {
      await Directory(p.join(to.path, rel)).create(recursive: true);
    } else if (e is File) {
      final dest = File(p.join(to.path, rel));
      await dest.parent.create(recursive: true);
      await e.copy(dest.path);
    }
  }
}

/// Everything printed goes through here so the transcript is greppable and
/// nothing sensitive leaks: only the *shape* of a path is reported.
///
/// Assertion output counts as printed output. A bare
/// `expect(somePath, startsWith('appdocs:'))` dumps the verbatim path -- the
/// container UUID included -- into the transcript on failure, and failures are
/// exactly the runs whose transcript gets pasted into a bug report. So every
/// assertion about a path goes through [expectPortable] or compares a derived
/// boolean, never the path itself.
void say(String key, Object? value) => debugPrintQa('QA|$key|$value');

void debugPrintQa(String line) {
  // ignore: avoid_print
  print(line);
}

String shape(String path, String docsRoot) {
  if (path.startsWith('appdocs:')) return 'PORTABLE(${path.substring(8)})';
  if (p.isWithin(docsRoot, path)) {
    return 'ABSOLUTE_INSIDE_DOCS(${p.relative(path, from: docsRoot)})';
  }
  return 'ABSOLUTE_OUTSIDE_DOCS';
}

/// Asserts [value] is a portable `appdocs:` value without ever printing it.
///
/// The assertion runs on a boolean, so the failure output is `false`; the
/// diagnosis rides in `reason` as a [shape], which drops the container UUID.
void expectPortable(
  String key,
  String? value,
  String docsRoot, {
  String? extra,
}) {
  final portable = value != null && value.startsWith('appdocs:');
  final shown = value == null ? 'NULL' : shape(value, docsRoot);
  expect(
    portable,
    isTrue,
    reason: extra == null
        ? '$key is not portable, it is $shown'
        : '$key is not portable, it is $shown -- $extra',
  );
}

Future<Map<String, dynamic>> readJsonFile(String path) async {
  final f = File(path);
  if (!await f.exists()) return {};
  final raw = await f.readAsString();
  if (raw.trim().isEmpty) return {};
  final decoded = jsonDecode(raw);
  return decoded is Map ? decoded.cast<String, dynamic>() : {'_list': decoded};
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String docsRoot;
  late String metadataDir;

  setUpAll(() async {
    // Restore BEFORE the DI graph reads anything: this stands in for iOS
    // carrying the container contents across a reinstall.
    if (_phase == 'verify') {
      final stash = Directory(_stash);
      if (await stash.exists()) {
        final target = await getApplicationDocumentsDirectory();
        await copyTree(stash, Directory(target.path));
      }
    }
    await di.init();
    docsRoot = (await getApplicationDocumentsDirectory()).path;
    metadataDir = p.join(docsRoot, 'metadata');
  });

  test(
    'runtime facts: does this runtime exhibit the /var symlink split?',
    () async {
      final resolved = PortablePath.resolveForComparison(docsRoot);
      final diverges = resolved != docsRoot;
      say('PLATFORM', Platform.operatingSystem);
      say('DOCS_ROOT_STARTS_WITH_VAR', docsRoot.startsWith('/var/'));
      say('DOCS_ROOT_RESOLVED_DIFFERS', diverges);
      say('DOCS_ROOT_DEPTH', p.split(docsRoot).length);
      // Never print the container UUID or user paths verbatim: only report
      // whether the container marker segment could be located at all.
      say('CONTAINER_MARKER_PRESENT', docsRoot.contains('/Application/'));
      expect(Platform.operatingSystem, 'ios');
    },
  );

  test('phase body', () async {
    final coordinator = di.sl<DatabaseSessionCoordinator>();
    final registry = di.sl<DatabaseRegistryRepository>();
    final security = di.sl<DatabaseSecurityRepository>();
    expect(registry, isA<DatabaseRegistryRepositoryImpl>());

    if (_phase == 'create') {
      // ---------- REAL CREATE FLOW ----------
      final result = await coordinator.createNewDatabase(
        databaseFileName: _dbName,
        password: _password,
        biometricProtectionEnabled: false,
        generateKeyFile: true,
      );
      say('CREATE_STATUS', result.status);
      expect(result.path, isNotNull);

      final records = await registry.list();
      // Length, not the list: a failed `hasLength` would print every record,
      // and a record's `toString` carries the absolute path.
      expect(records.length, 1);
      say('CREATED_PATH_SHAPE', shape(records.single.canonicalPath, docsRoot));
      expect(await File(records.single.canonicalPath).exists(), isTrue);

      // ---------- ON-DISK SHAPE ----------
      final reg = await readJsonFile(
        p.join(metadataDir, 'database_registry_records.json'),
      );
      final regRow = (reg['_list'] as List).single as Map;
      say(
        'DISK_registry.canonicalPath',
        shape(regRow['canonicalPath'] as String, docsRoot),
      );

      final prof = await readJsonFile(
        p.join(metadataDir, 'database_security_profiles.json'),
      );
      final profRow = prof.values.first as Map;
      final diskKey = profRow['keyFilePath'] as String?;
      say(
        'DISK_security.keyFilePath',
        diskKey == null ? 'NULL' : shape(diskKey, docsRoot),
      );

      final state = await readJsonFile(p.join(metadataDir, 'local_state.json'));
      final diskCachedKey = state['cachedKeyFilePath'] as String?;
      say(
        'DISK_local_state.cachedKeyFilePath',
        diskCachedKey == null ? 'NULL' : shape(diskCachedKey, docsRoot),
      );
      // #42 removed the cached-database-path accessor, so this key must no
      // longer be written at all. The probe asserts its *absence*: it is a
      // regression guard, not a value check, and it is read straight out of
      // the JSON precisely because no Dart symbol reads it any more. If a
      // future change reintroduces the writer, this fails here rather than
      // silently re-freezing an absolute path into local_state.json.
      final diskCachedDb = state['cachedDatabasePath'] as String?;
      say(
        'DISK_local_state.cachedDatabasePath',
        diskCachedDb == null ? 'NULL' : shape(diskCachedDb, docsRoot),
      );
      expect(
        diskCachedDb,
        isNull,
        reason:
            'cachedDatabasePath is back in local_state.json; #42 removed it',
      );

      // Leave a breadcrumb so the verify phase can prove the root moved.
      await File(
        p.join(metadataDir, 'qa_state.json'),
      ).writeAsString(jsonEncode({'docsRoot': docsRoot}), flush: true);

      // Stash Documents/ on the host so the verify phase can restore it into
      // the freshly-rotated container.
      final stash = Directory(_stash);
      if (await stash.exists()) await stash.delete(recursive: true);
      await copyTree(Directory(docsRoot), stash);
      say('STASHED', await stash.exists());
      expectPortable(
        'registry.canonicalPath',
        regRow['canonicalPath'] as String?,
        docsRoot,
      );
      if (diskKey != null) {
        expectPortable('security.keyFilePath', diskKey, docsRoot);
      }
      if (diskCachedKey != null) {
        expectPortable(
          'local_state.cachedKeyFilePath',
          diskCachedKey,
          docsRoot,
        );
      }
    } else {
      // ---------- AFTER RELOCATION ----------
      final breadcrumb = await readJsonFile(
        p.join(metadataDir, 'qa_state.json'),
      );
      final previousRoot = breadcrumb['docsRoot'] as String?;
      expect(
        previousRoot,
        isNotNull,
        reason: 'Documents/ was not restored into the new container',
      );
      // Compared here, asserted as a boolean: `isNot(docsRoot)` would print
      // both container paths, UUID and all, in the one run that matters.
      final rotated = previousRoot != docsRoot;
      say('CONTAINER_ROTATED', rotated);
      expect(
        rotated,
        isTrue,
        reason: 'container UUID did not change; the test proves nothing',
      );

      // P0.1 -- the real startup flow the app runs on launch.
      final boot = await coordinator.checkInitialDatabase();
      say('BOOT_STATUS', boot.status);
      say('BOOT_ITEMS', boot.items.length);
      final item = boot.items.firstWhere(
        (DatabaseSelectionItem i) => i.displayName.contains('qa_vault'),
      );
      say('ITEM_IS_MISSING', item.isMissing);
      say('ITEM_PATH_SHAPE', shape(item.canonicalPath, docsRoot));
      say('ITEM_KEYFILE_CONFIGURED', item.keyFileConfigured);
      expect(
        item.isMissing,
        isFalse,
        reason: 'the relocated database still reports missing',
      );
      expect(await File(item.canonicalPath).exists(), isTrue);

      // On-disk shape must still be portable after the reload+save cycle.
      final reg = await readJsonFile(
        p.join(metadataDir, 'database_registry_records.json'),
      );
      final regRow = (reg['_list'] as List).single as Map;
      say(
        'DISK_registry.canonicalPath(after)',
        shape(regRow['canonicalPath'] as String, docsRoot),
      );
      expectPortable(
        'registry.canonicalPath(after)',
        regRow['canonicalPath'] as String?,
        docsRoot,
      );

      // P2.4 -- key file resolves against the new root and the file is there.
      final record = (await registry.list()).single;
      final profile = await security.getProfile(record.databaseId);
      final keyPath = profile?.keyFilePath;
      say(
        'PROFILE_KEYFILE_SHAPE',
        keyPath == null ? 'NULL' : shape(keyPath, docsRoot),
      );
      expect(keyPath, isNotNull);
      expect(
        await File(keyPath!).exists(),
        isTrue,
        reason: 'key file path did not follow the container',
      );

      // P0.1 -- unlock end to end with the relocated key file.
      final bootstrap = await coordinator.initializeUnlock(
        databasePath: item.canonicalPath,
        biometricAvailable: false,
      );
      say(
        'UNLOCK_BOOTSTRAP_KEYFILE_SHAPE',
        bootstrap.keyFilePath == null
            ? 'NULL'
            : shape(bootstrap.keyFilePath!, docsRoot),
      );
      await coordinator.unlockWithManualCredentials(
        databasePath: item.canonicalPath,
        password: _password,
        keyFilePath: bootstrap.keyFilePath,
      );
      say('UNLOCK', 'OK');

      // P0.2 -- Locate, with the picker's resolved spelling of the same file.
      final pickerSpelling = p.join(
        Directory(p.dirname(item.canonicalPath)).resolveSymbolicLinksSync(),
        p.basename(item.canonicalPath),
      );
      say('PICKER_SPELLING_DIFFERS', pickerSpelling != item.canonicalPath);
      final located = await coordinator.locateMissingDatabase(
        databaseId: item.databaseId,
        selectedPath: pickerSpelling,
      );
      say('LOCATE_STATUS', located.status);
      final regAfterLocate = await readJsonFile(
        p.join(metadataDir, 'database_registry_records.json'),
      );
      final locatedRow = (regAfterLocate['_list'] as List).single as Map;
      say(
        'DISK_registry.canonicalPath(after Locate)',
        shape(locatedRow['canonicalPath'] as String, docsRoot),
      );
      expectPortable(
        'registry.canonicalPath(after Locate)',
        locatedRow['canonicalPath'] as String?,
        docsRoot,
        extra: 'Locate re-froze an absolute path: the original iOS bug is back',
      );

      // P2.4b -- cache fallback in local_state.json, for a path that is NOT
      // in the registry (the only branch that reads the cached key file).
      final ghost = p.join(docsRoot, 'databases', 'not-registered.kdbx');
      final fallback = await coordinator.initializeUnlock(
        databasePath: ghost,
        biometricAvailable: false,
      );
      say(
        'FALLBACK_CACHED_KEYFILE_SHAPE',
        fallback.keyFilePath == null
            ? 'NULL'
            : shape(fallback.keyFilePath!, docsRoot),
      );
      expect(
        fallback.keyFilePath,
        isNotNull,
        reason: 'local_state.json cached key file did not survive relocation',
      );
      expect(await File(fallback.keyFilePath!).exists(), isTrue);

      // P2.5 -- the delete guard, exercised the way the key-file sheet does.
      final managed = await MobileFileStorage.listFilesInAppDirectory(
        subdirectory: 'keys',
      );
      say('MANAGED_KEYFILES', managed.length);
      expect(managed, isNotEmpty);
      expect(
        await MobileFileStorage.isPathInAppDirectory(
          filePath: managed.first.path,
          subdirectory: 'keys',
        ),
        isTrue,
        reason: 'two-condition guard rejects a legitimate managed key file',
      );
      await MobileFileStorage.deleteFileFromAppDirectory(
        filePath: managed.first.path,
        subdirectory: 'keys',
      );
      say('DELETE_GUARD', 'allowed legitimate managed key file');
      expect(await File(managed.first.path).exists(), isFalse);

      // And still refuses something outside app storage.
      final outsider = p.join(Directory.systemTemp.path, 'outsider.keyx');
      await File(outsider).writeAsString('x');
      var refused = false;
      try {
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: outsider,
          subdirectory: 'keys',
        );
      } catch (_) {
        refused = true;
      }
      say('DELETE_GUARD_OUTSIDE_REFUSED', refused);
      expect(refused, isTrue);
      expect(await File(outsider).exists(), isTrue);
    }
  });
}
