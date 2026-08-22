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
      discovered = _discoveredWriters;
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
      // Each entry is a *data-layer* writer FR-8 names explicitly. The
      // presentation writers FR-8 also named (vault_session_coordinator,
      // database_selection_screen, exports) were removed by Gate 1 T102:
      // they now route through `DatabaseFileRepository.copyFile/renameFile`,
      // implemented by `DatabaseImportService` — asserted by the
      // `T102 architecture` group below.
      const fr8Paths = [
        'lib/features/password_manager/data/services/vault_kdbx_service.dart',
        'lib/features/password_manager/data/services/'
            'database_sync_orchestrator.dart',
        'lib/features/password_manager/data/services/'
            'database_import_service.dart',
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
        'final raf = await file.open(mode: FileMode.write);': 'openWriteMode',
        'raf.openSync(mode: FileMode.writeOnlyAppend);': 'openWriteMode',
        'await raf.writeFrom(bytes, 0, bytes.length);': 'writeFrom',
        'databaseSink.add(chunk);': 'sinkAdd',
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
        'final pending = pendingGeneration.create(databaseId: databaseId);',
        'final response = await _client.delete(uri, headers: headers);',
        // LOW-1 negatives: read-only open, FFI open, non-sink `.add`.
        'final raf = await file.open(mode: FileMode.read);',
        "final lib = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');",
        'controller.add(event); results.add(value);',
      ]) {
        final scrubbed = line.replaceAll(_nonFilesystem, '');
        expect(
          _operations.values.where((p) => RegExp(p).hasMatch(scrubbed)),
          isEmpty,
          reason: 'false positive on: $line',
        );
      }
    });

    test('every frozen database writer routes through the path mutex', () {
      // spec 008 T105: the mutex is no longer DI-only — every T101 database
      // writer acquires it. This static half of the guard pins the exact set
      // of production files that may reference the mutex (a NEW writer that
      // starts mutating database files without appearing here fails the
      // `discovered` baseline above AND this list) and requires each of them
      // to actually acquire (`withDatabaseLock(`), not merely import.
      // The executable half — "a censited writer mutating OUTSIDE the lock
      // fails a test" — lives in `database_writer_lock_routing_test.dart`:
      // every entry point is invoked with a refusing mutex and must then
      // leave the filesystem untouched.
      List<String> referencing(String fileName) =>
          _dartFilesUnder(const ['lib'])
              .where(
                (f) =>
                    !f.path.endsWith(fileName) &&
                    f.readAsStringSync().contains(fileName),
              )
              .map((f) => f.path)
              .toList();

      const routedWriters = [
        'lib/features/password_manager/data/services/'
            'database_import_service.dart',
        'lib/features/password_manager/data/services/'
            'database_rename_transaction.dart',
        'lib/features/password_manager/data/services/'
            'database_sync_orchestrator.dart',
        'lib/features/password_manager/data/services/'
            'vault_kdbx_service.dart',
      ];
      expect(
        referencing('database_path_mutex.dart')..sort(),
        [
          ...routedWriters,
          'lib/features/password_manager/di/password_manager_data_di.dart',
        ]..sort(),
        reason:
            'the set of mutex-routed writers changed. A new database writer '
            'must acquire the shared DatabasePathMutex (audit it for nesting '
            '— the mutex is NOT reentrant) and be added to '
            'database_writer_lock_routing_test.dart; a writer must never '
            'lose its routing silently.',
      );
      for (final path in routedWriters) {
        expect(
          File(path).readAsStringSync(),
          contains('withDatabaseLock('),
          reason: '$path imports the mutex but never acquires it',
        );
      }
      expect(referencing('database_path_identity_resolver.dart'), [
        'lib/features/password_manager/data/services/'
            'database_path_mutex.dart',
      ]);
    });
  });

  // ===========================================================================
  // The T007 deliverable: writers the spec does not list.
  // ===========================================================================
  group('inventory baseline documented gaps', () {
    late Map<String, List<String>> discovered;

    setUpAll(() {
      discovered = _discoveredWriters;
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
        // Since T102 the body no longer mutates files directly: it delegates
        // to `DatabaseFileRepository.copyFile`.
        const shared =
            'lib/features/password_manager/presentation/screens/'
            'vault/vault_shared.part.dart';
        const navigation =
            'lib/features/password_manager/presentation/screens/'
            'vault/vault_navigation.part.dart';

        expect(
          discovered.keys,
          isNot(contains(shared)),
          reason:
              'T102 routed the export body through the domain port; a direct '
              'mutation reappearing here is a Gate 1 regression',
        );
        expect(File(shared).readAsStringSync(), contains('.copyFile('));
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

    test('GAP 3: key-file manager widgets export through the domain port', () {
      // Pre-T102 both widgets copied key files with `File.copy` directly.
      // They now delegate to `DatabaseFileRepository.copyFile` and must not
      // reappear as direct writers.
      const dialog =
          'lib/features/password_manager/presentation/widgets/'
          'internal_key_file_manager_dialog.dart';
      const sheet =
          'lib/features/password_manager/presentation/widgets/'
          'internal_key_file_manager_sheet.dart';
      expect(discovered.keys, isNot(contains(dialog)));
      expect(discovered.keys, isNot(contains(sheet)));
      expect(File(dialog).readAsStringSync(), contains('.copyFile('));
      expect(File(sheet).readAsStringSync(), contains('.copyFile('));
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
  });

  // ===========================================================================
  // Gate 1 T102 — architecture guard: the presentation layer performs no
  // direct `dart:io` file mutation. Export/copy/rename/delete flows go
  // through `DatabaseFileRepository` (domain port, data implementation).
  // ===========================================================================
  group('T102 architecture', () {
    test('presentation layer performs no direct file mutation', () {
      final presentationWriters =
          _discoveredWriters.keys
              .where((path) => path.contains('/presentation/'))
              .toList()
            ..sort();
      expect(
        presentationWriters,
        isEmpty,
        reason:
            'a dart:io file mutation appeared in the presentation layer. '
            'Route it through DatabaseFileRepository (domain port, data '
            'implementation) instead — spec 008 T102.',
      );
    });

    test('the pre-T102 presentation writers now delegate to the port', () {
      // Behaviour anchor: each former direct writer still performs its
      // operation, but through the domain port.
      const delegating = <String, String>{
        'lib/features/password_manager/presentation/coordinators/'
                'vault_session_coordinator.dart':
            'databaseFileRepository.renameFile(',
        'lib/features/password_manager/presentation/screens/'
                'database_selection_screen.dart':
            '.copyFile(',
        'lib/features/password_manager/presentation/screens/vault/'
                'vault_shared.part.dart':
            '.copyFile(',
        'lib/features/password_manager/presentation/widgets/'
                'internal_key_file_manager_dialog.dart':
            '.copyFile(',
        'lib/features/password_manager/presentation/widgets/'
                'internal_key_file_manager_sheet.dart':
            '.copyFile(',
      };
      delegating.forEach((path, marker) {
        expect(
          File(path).readAsStringSync(),
          contains(marker),
          reason: '$path lost its port delegation',
        );
      });
    });
  });

  // ===========================================================================
  // Gate 1 T101 — frozen writer inventory. Beyond the shape baseline above
  // (file -> operation kinds), this freezes the *call-site count* of every
  // mutation operation in the database-writer files, so a new write site
  // added to an already-listed file fails too. Counts use the same scrub
  // rules as the scanner.
  // ===========================================================================
  group('T101 frozen writer inventory', () {
    test('database-writer files have exactly the frozen mutation sites', () {
      const frozenCounts = <String, Map<String, int>>{
        'lib/features/password_manager/data/services/'
            'vault_kdbx_service.dart': {
          // saveVault temp write, attachment export, raw byte write
          'writeAsBytes': 3,
          // credential transaction: begin/finalize/rollback renames
          'rename': 6,
          'delete': 3,
        },
        'lib/features/password_manager/data/services/'
            'database_import_service.dart': {
          // stage/commit/create/web-path/key-file writes
          'writeAsBytes': 4,
          // commit/finalize/rollback/move/replace renames
          'rename': 12,
          'delete': 8,
          // T102: DatabaseFileRepository.copyFile implementation
          'copy': 1,
        },
        'lib/features/password_manager/data/services/'
            'database_sync_orchestrator.dart': {
          // three independent replacement sites (GAP 4)
          'writeAsBytes': 3,
          // _backupFile
          'copy': 1,
        },
        // T106: rename transaction — forward rename + rollback rename.
        'lib/features/password_manager/data/services/'
            'database_rename_transaction.dart': {
          'rename': 2,
        },
        'lib/core/utils/mobile_file_storage.dart': {
          'writeAsBytes': 1,
          'delete': 1,
          'create': 1,
        },
      };

      final actual = <String, Map<String, int>>{};
      for (final entry in frozenCounts.entries) {
        final counts = <String, int>{};
        for (final line in File(entry.key).readAsLinesSync()) {
          final scrubbed = line.replaceAll(_nonFilesystem, '');
          _operations.forEach((name, pattern) {
            final matches = RegExp(pattern).allMatches(scrubbed).length;
            if (matches > 0) {
              counts[name] = (counts[name] ?? 0) + matches;
            }
          });
        }
        actual[entry.key] = counts;
      }
      expect(
        actual,
        frozenCounts,
        reason:
            'a mutation call site was added to or removed from a frozen '
            'database writer. Update this table, the FR-8 reconciliation in '
            'specs/008-per-field-conflict-resolution/feasibility-report.md '
            'and route the new site through the T104 path mutex when it '
            'lands.',
      );
    });

    test('the frozen entry points still exist by name', () {
      // T101 names these paths explicitly; a rename or removal must be a
      // conscious inventory update, not an accident.
      const entryPoints = <String, List<String>>{
        'lib/features/password_manager/data/services/'
            'vault_kdbx_service.dart': [
          'beginCredentialChange',
          'finalizeCredentialChange',
          'rollbackCredentialChange',
        ],
        'lib/features/password_manager/data/services/'
            'database_sync_orchestrator.dart': [
          'syncNow',
          '_backupFile',
        ],
        'lib/features/password_manager/data/services/'
            'database_import_service.dart': [
          'stageLocalSelection',
          'stageDriveDownload',
          'commitStagedDatabase',
          'finalizeDatabaseCommit',
          'rollbackDatabaseCommit',
          'createDatabase',
          'copyFile',
          'renameFile',
        ],
        'lib/features/password_manager/data/services/'
            'database_rename_transaction.dart': [
          'renameDatabase',
        ],
        'lib/features/password_manager/presentation/coordinators/'
            'database_session_coordinator.dart': [
          'createNewDatabase',
          '_commitStagedImport',
          'removeRecentDatabase',
        ],
        'lib/features/password_manager/presentation/coordinators/'
            'vault_session_coordinator.dart': [
          'updateDatabaseSettings',
          '_writeDatedPreRekeyBackup',
        ],
        'lib/features/password_manager/presentation/screens/vault/'
            'vault_shared.part.dart': [
          '_exportDatabaseBackup',
        ],
      };
      entryPoints.forEach((path, names) {
        final source = File(path).readAsStringSync();
        for (final name in names) {
          expect(
            source,
            contains(name),
            reason: '$path no longer contains frozen entry point $name',
          );
        }
      });
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
  // LOW-1 (T101 follow-up): RandomAccessFile writers. `File.open` in a
  // writable mode plus `writeFrom` would otherwise bypass the inventory
  // entirely. `FileMode.read` deliberately does not match (the validate
  // use case opens read-only); a `mode:` split across lines evades this
  // line-based scanner — same known limit as every pattern here.
  'openWriteMode': r'\.open(Sync)?\([^)]*FileMode\.(write|append)',
  'writeFrom': r'\.writeFrom(Sync)?\(',
  // LOW-1: an `IOSink.add` on a sink NOT obtained from `openWrite` (e.g. a
  // sink passed in or stored on a field). Receiver must look sink-ish —
  // same trade as `_kdbxMerge`: a bare `.add(` matches every collection in
  // the codebase.
  'sinkAdd': r'(?<![A-Za-z0-9_])[A-Za-z0-9_]*[Ss]ink[A-Za-z0-9_]*\.add\(',
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
  r'KdbxFormat\(\)\.create(Sync)?\(|'
  // 009 / B006: `DesktopBrowserPendingGenerationService.create` is a pure
  // in-memory record constructor — the service touches no file by contract
  // (and its own tests search the disk for the secret to prove it).
  r'pendingGeneration[!?]?\.create(Sync)?\(|'
  // `tool/drive_conditional_spike.dart` issues an HTTP DELETE against the
  // Drive API through its `http.Client` field — a network call, not a
  // filesystem mutation. This is the only allowlisted receiver in `tool/`:
  // anything else that writes there (the native host above all, which must
  // persist nothing by contract — 009 B008) fails the baseline.
  r'_client\.delete(Sync)?\(',
);

/// All of `lib/`, plus `tool/`: narrowing this to the feature package would
/// let a writer added to `lib/main.dart` or `lib/injection_container.dart` go
/// unnoticed. `tool/` is included since 009 B1 because the native host
/// (`tool/native_host.dart` + `tool/native_host_protocol.dart`) handles
/// revealed and generated secrets and its contract is to persist *nothing*:
/// a filesystem writer appearing there — even one aimed at
/// `Directory.systemTemp`, which no runtime test watches — must fail this
/// baseline. Legitimate non-filesystem receivers in `tool/` are scrubbed
/// above, one by one, with the reason next to each.
const _roots = ['lib', 'tool'];

/// Memoized scan, shared by both groups.
///
/// Guard semantics are unchanged: the scan is a pure read of `lib/`, which
/// cannot change while the run is in flight, so caching only removes a second
/// identical walk. A new writer still fails the baseline comparison. The view
/// is unmodifiable so one group can never perturb what the other asserts on.
///
/// Top-level `final` is lazily initialized on first access, so the walk still
/// happens inside the first `setUpAll`, not at import time.
final Map<String, List<String>> _discoveredWriters = Map.unmodifiable(
  _scanWriters(),
);

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
    // 'copy' is the T102 `DatabaseFileRepository.copyFile` implementation:
    // the presentation export/backup copies moved behind this port.
    'copy',
    'delete',
    'rename',
    'writeAsBytes',
  ],
  'lib/features/password_manager/data/services/'
      'database_sync_orchestrator.dart': [
    'copy',
    'writeAsBytes',
  ],
  // T106: rename transaction (forward + rollback rename under one lock).
  'lib/features/password_manager/data/services/'
      'database_rename_transaction.dart': [
    'rename',
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
  // Gate 1 T102: the five pre-T102 presentation writers
  // (vault_session_coordinator, database_selection_screen,
  // vault_shared.part, both internal_key_file_manager widgets) no longer
  // mutate files directly — they delegate to
  // `DatabaseFileRepository.copyFile/renameFile`. The `T102 architecture`
  // group pins the presentation layer at zero direct writers.
};
