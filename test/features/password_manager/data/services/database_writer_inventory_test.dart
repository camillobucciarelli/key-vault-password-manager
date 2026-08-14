import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// =============================================================================
// spec 008 Gate 0 (T007) — writer/path discovery.
//
// Scans the password-manager feature (plus the `lib/core` helpers it uses) for
// every filesystem mutation and reconciles the result against the inventory
// written into `spec.md` FR-8.
//
// The point of this task is NOT to confirm FR-8; it is to find what FR-8
// MISSED. The `documented gaps` group below is the deliverable: each test
// there records a writer that exists in the code but not in the spec, or a
// spec reference that no longer matches the code.
//
// This file is a guard, not a refactor: it changes no production behaviour.
// Gate 1 (T101-T105) is what routes these writers through a shared mutex.
// =============================================================================

void main() {
  group('inventory baseline', () {
    late Map<String, List<String>> discovered;

    setUpAll(() {
      discovered = _scanWriters();
    });

    test('every filesystem writer is accounted for', () {
      expect(
        discovered,
        _baseline,
        reason:
            'a filesystem writer appeared, moved or changed shape. Reconcile '
            'it with spec 008 FR-8 and update both the baseline below and '
            'specs/008-per-field-conflict-resolution/feasibility-report.md '
            'before touching the path mutex.',
      );
    });

    test('baseline covers every FR-8 writer that still exists', () {
      // Each entry is a writer FR-8 names explicitly.
      const fr8Paths = [
        'lib/features/password_manager/data/services/vault_kdbx_service.dart',
        'lib/features/password_manager/data/services/'
            'database_sync_orchestrator.dart',
        'lib/features/password_manager/data/services/'
            'database_import_service.dart',
        'lib/features/password_manager/presentation/coordinators/'
            'vault_session_coordinator.dart',
        'lib/features/password_manager/presentation/screens/'
            'database_selection_screen.dart',
      ];
      for (final path in fr8Paths) {
        expect(
          discovered.keys,
          contains(path),
          reason: 'FR-8 names $path as a writer',
        );
      }
    });

    test('KdbxFile.merge is absent from every production source', () {
      // Acceptance criterion 3, enforced over `lib/` from the writer side too.
      // The receiver must look kdbx-ish: a bare `merge(` matches any unrelated
      // API (this repo already has `VaultKdbxService.mergeEntries`) and would
      // be a false positive waiting to happen.
      final offenders = _dartFilesUnder(const ['lib'])
          .where((file) => _kdbxMerge.hasMatch(file.readAsStringSync()))
          .map((file) => file.path)
          .toList();
      expect(offenders, isEmpty);
    });

    test('the scanner itself catches sync writers and mixed lines', () {
      // The guard is only worth its claim ("any new writer fails the test")
      // if it sees the `*Sync` forms and does not discard a whole line just
      // because something clipboard-shaped shares it.
      const samples = <String, String>{
        'await file.renameSync(target);': 'rename',
        'File(p).writeAsBytesSync(bytes);': 'writeAsBytes',
        'dir.createSync(recursive: true);': 'create',
        'f.copySync(dest);': 'copy',
        'f.deleteSync();': 'delete',
        'sink = f.openWrite();': 'openWrite',
        "await di.sl<ClipboardGuard>().copy(t); await f.copy(dest);": 'copy',
        "Clipboard.setData(d); await f.writeAsString(s);": 'writeAsString',
      };
      samples.forEach((line, expected) {
        final scrubbed = line.replaceAll(_nonFilesystem, '');
        final matched = _operations.entries
            .where((op) => RegExp(op.value).hasMatch(scrubbed))
            .map((op) => op.key);
        expect(
          matched,
          contains(expected),
          reason: 'missed a writer in: $line',
        );
      });

      // ...and it still ignores the non-filesystem receivers on their own.
      for (final line in const [
        'await Clipboard.setData(data);',
        'await di.sl<ClipboardGuard>().copy(text);',
        'await secureStorage.delete(key: k);',
        'final f = KdbxFormat().create(credentials, name);',
      ]) {
        final scrubbed = line.replaceAll(_nonFilesystem, '');
        expect(
          _operations.values.where((p) => RegExp(p).hasMatch(scrubbed)),
          isEmpty,
          reason: 'false positive on: $line',
        );
      }
    });

    test('no shared database path mutex exists yet', () {
      // Gate 0 must not silently ship Gate 1. If these files appear, the
      // inventory below has to be re-derived against them first.
      expect(
        File(
          'lib/features/password_manager/data/services/'
          'database_path_mutex.dart',
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          'lib/features/password_manager/data/services/'
          'database_path_identity_resolver.dart',
        ).existsSync(),
        isFalse,
      );
    });
  });

  // ===========================================================================
  // The T007 deliverable: writers the spec does not list.
  // ===========================================================================
  group('inventory baseline documented gaps', () {
    late Map<String, List<String>> discovered;

    setUpAll(() {
      discovered = _scanWriters();
    });

    test('GAP 1: MobileFileStorage is an unlisted database-path writer', () {
      // Used by DatabaseImportService for managed databases AND by both
      // key-file manager widgets. FR-8 does not mention it at all.
      const path = 'lib/core/utils/mobile_file_storage.dart';
      expect(discovered[path], containsAll(<String>['writeAsBytes', 'delete']));

      final users = _dartFilesUnder(const ['lib/features/password_manager'])
          .where((f) => f.readAsStringSync().contains('MobileFileStorage'))
          .map((f) => f.path)
          .toList();
      expect(
        users,
        contains(
          'lib/features/password_manager/data/services/'
          'database_import_service.dart',
        ),
      );
    });

    test(
      'GAP 2: FR-8 points at the wrong presentation file for the export',
      () {
        // FR-8 says `vault_navigation.part.dart::_exportCurrentDatabase`.
        // The body actually lives in `vault_shared.part.dart` and is reachable
        // from three call sites, so a single-file fix would miss two of them.
        const shared =
            'lib/features/password_manager/presentation/screens/'
            'vault/vault_shared.part.dart';
        const navigation =
            'lib/features/password_manager/presentation/screens/'
            'vault/vault_navigation.part.dart';

        expect(discovered[shared], contains('copy'));
        expect(
          discovered.keys,
          isNot(contains(navigation)),
          reason: 'vault_navigation.part.dart performs no direct file mutation',
        );

        final callers =
            _dartFilesUnder(const [
                  'lib/features/password_manager/presentation/screens/vault',
                ])
                .where(
                  (f) => f.readAsStringSync().contains(
                    '_exportDatabaseBackup(context',
                  ),
                )
                .map((f) => f.path)
                .toList()
              ..sort();
        expect(callers, hasLength(3));
      },
    );

    test('GAP 3: key-file manager widgets write files from presentation', () {
      const dialog =
          'lib/features/password_manager/presentation/widgets/'
          'internal_key_file_manager_dialog.dart';
      const sheet =
          'lib/features/password_manager/presentation/widgets/'
          'internal_key_file_manager_sheet.dart';
      expect(discovered[dialog], contains('copy'));
      expect(discovered[sheet], contains('copy'));
    });

    test('GAP 4: the sync orchestrator has three replace sites, not one', () {
      // FR-8 describes `syncNow` replacement as a single path. There are three
      // independent `writeAsBytes` sites plus the backup copy.
      final source = File(
        'lib/features/password_manager/data/services/'
        'database_sync_orchestrator.dart',
      ).readAsStringSync();
      expect(RegExp(r'\.writeAsBytes\(').allMatches(source), hasLength(3));
      expect(RegExp(r'_backupFile\(').allMatches(source), hasLength(4));
    });

    test('GAP 5: the domain layer builds KDBX bytes directly', () {
      // `CreateDatabaseUseCase` constructs and serializes a `KdbxFile` inside
      // `domain/`. It writes through a repository port, so it is not a raw
      // filesystem writer, but it does own KDBX serialization in the wrong
      // layer and must acquire the same mutex as every other creator.
      final source = File(
        'lib/features/password_manager/domain/usecases/'
        'create_database_usecase.dart',
      ).readAsStringSync();
      expect(source, contains('KdbxFormat().create('));
      expect(source, contains('kdbx.save()'));
    });

    test('GAP 6: import service also writes a web-path copy', () {
      final source = File(
        'lib/features/password_manager/data/services/'
        'database_import_service.dart',
      ).readAsStringSync();
      expect(source, contains('File(webPath).writeAsBytes('));
    });

    test('CORRECTION: session coordinator deletes through a domain port', () {
      // FR-8 lists `DatabaseSessionCoordinator ... removeRecentDatabase file
      // delete` as a direct presentation write. It is not: it goes through
      // `DatabaseFileRepository.deleteFile`. The spec overstates this one.
      const path =
          'lib/features/password_manager/presentation/coordinators/'
          'database_session_coordinator.dart';
      expect(discovered.keys, isNot(contains(path)));
      expect(
        File(path).readAsStringSync(),
        contains('databaseFileRepository.deleteFile('),
      );
    });

    test('presentation layer still mutates database files directly', () {
      // Gate 1 T102 exit criterion. Recorded here so the list is explicit.
      final presentationWriters =
          discovered.keys
              .where((path) => path.contains('/presentation/'))
              .toList()
            ..sort();
      expect(presentationWriters, <String>[
        'lib/features/password_manager/presentation/coordinators/'
            'vault_session_coordinator.dart',
        'lib/features/password_manager/presentation/screens/'
            'database_selection_screen.dart',
        'lib/features/password_manager/presentation/screens/vault/'
            'vault_shared.part.dart',
        'lib/features/password_manager/presentation/widgets/'
            'internal_key_file_manager_dialog.dart',
        'lib/features/password_manager/presentation/widgets/'
            'internal_key_file_manager_sheet.dart',
      ]);
    });
  });
}

// =============================================================================
// Scanner.
// =============================================================================

/// Matches a `merge` call whose receiver token contains `kdbx` (any case) —
/// the `KdbxFile` merge API and any variable named after it. A receiver that
/// is a `KdbxFile` under a name with no `kdbx` in it is not caught; that is a
/// deliberate trade for not matching every `merge(` in the codebase, which
/// this repo already has (`VaultKdbxService.mergeEntries`).
///
/// Written without a literal example on purpose: the sibling scan in
/// `vault_kdbx_service_test.dart` reads this file too.
final _kdbxMerge = RegExp(
  r'(?<![A-Za-z0-9_])[A-Za-z0-9_]*[Kk]dbx[A-Za-z0-9_]*\.merge\s*\(',
);

/// Filesystem mutation operations searched for, by name.
///
/// Every pattern also matches the `*Sync` variant: without it a future
/// `renameSync`/`writeAsBytesSync` would slip past this guard silently, which
/// would make the "any new writer fails the test" claim false. `openWrite`
/// has no `Sync` form; the optional suffix is harmless there.
const _operations = <String, String>{
  'writeAsBytes': r'\.writeAsBytes(Sync)?\(',
  'writeAsString': r'\.writeAsString(Sync)?\(',
  'openWrite': r'\.openWrite(Sync)?\(',
  'rename': r'\.rename(Sync)?\(',
  'copy': r'\.copy(Sync)?\(',
  'delete': r'\.delete(Sync)?\(',
  'create': r'\.create(Sync)?\(',
};

/// Same-named methods on non-filesystem receivers.
///
/// These are SCRUBBED out of the line rather than used to skip it: a single
/// line holding both a clipboard call and a real filesystem write must still
/// report the write.
final _nonFilesystem = RegExp(
  // Covers both `Clipboard.setData(` and `di.sl<ClipboardGuard>().copy(`.
  r'Clipboard[A-Za-z]*(>\(\))?\.[A-Za-z_]+\(|'
  r'secureStorage\.delete(Sync)?\(|'
  r'Kdbx[A-Za-z]*\.create(Sync)?\(|'
  r'KdbxFormat\(\)\.create(Sync)?\(',
);

/// All of `lib/`: narrowing this to the feature package would let a writer
/// added to `lib/main.dart` or `lib/injection_container.dart` go unnoticed.
const _roots = ['lib'];

Map<String, List<String>> _scanWriters() {
  final result = <String, List<String>>{};
  for (final file in _dartFilesUnder(_roots)) {
    final found = <String>{};
    for (final line in file.readAsLinesSync()) {
      final scrubbed = line.replaceAll(_nonFilesystem, '');
      _operations.forEach((name, pattern) {
        if (RegExp(pattern).hasMatch(scrubbed)) {
          found.add(name);
        }
      });
    }
    if (found.isNotEmpty) {
      result[file.path] = found.toList()..sort();
    }
  }
  return Map.fromEntries(
    result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

List<File> _dartFilesUnder(List<String> roots) => [
  for (final root in roots)
    ...Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
]..sort((a, b) => a.path.compareTo(b.path));

/// Frozen result of the T007 scan. Every entry is reconciled against FR-8 in
/// `specs/008-per-field-conflict-resolution/feasibility-report.md`.
const _baseline = <String, List<String>>{
  // --- unlisted by FR-8 ----------------------------------------------------
  'lib/core/utils/mobile_file_storage.dart': [
    'create',
    'delete',
    'writeAsBytes',
  ],
  // --- non-database local state (must not take the database mutex) ---------
  'lib/features/password_manager/data/datasources/'
      'database_registry_local_data_source.dart': [
    'create',
    'writeAsString',
  ],
  'lib/features/password_manager/data/datasources/'
      'database_security_local_data_source.dart': [
    'create',
    'writeAsString',
  ],
  'lib/features/password_manager/data/datasources/local_data_source.dart': [
    'create',
    'writeAsString',
  ],
  'lib/features/password_manager/data/datasources/'
      'sync_metadata_data_source.dart': [
    'create',
    'writeAsString',
  ],
  // --- FR-8 database writers ----------------------------------------------
  'lib/features/password_manager/data/services/database_import_service.dart': [
    'delete',
    'rename',
    'writeAsBytes',
  ],
  'lib/features/password_manager/data/services/'
      'database_sync_orchestrator.dart': [
    'copy',
    'writeAsBytes',
  ],
  // --- unlisted by FR-8, non-database -------------------------------------
  'lib/features/password_manager/data/services/'
      'desktop_browser_autofill_cache.dart': [
    'create',
    'delete',
    'rename',
    'writeAsString',
  ],
  'lib/features/password_manager/data/services/vault_kdbx_service.dart': [
    'delete',
    'rename',
    'writeAsBytes',
  ],
  'lib/features/password_manager/presentation/coordinators/'
      'vault_session_coordinator.dart': [
    'copy',
    'rename',
  ],
  'lib/features/password_manager/presentation/screens/'
      'database_selection_screen.dart': [
    'copy',
  ],
  // --- FR-8 points at vault_navigation.part.dart; the real site is here ----
  'lib/features/password_manager/presentation/screens/vault/'
      'vault_shared.part.dart': [
    'copy',
  ],
  // --- unlisted by FR-8 ----------------------------------------------------
  'lib/features/password_manager/presentation/widgets/'
      'internal_key_file_manager_dialog.dart': [
    'copy',
  ],
  'lib/features/password_manager/presentation/widgets/'
      'internal_key_file_manager_sheet.dart': [
    'copy',
  ],
};
