// spec-019 T006 — the readers of `allEntries`, pinned before `visibleEntries`
// changes meaning.
//
// Spec 019 teaches `_computeVisibleEntries` a folder filter (T010), so from
// T010 onwards `visibleEntries` can be a strict subset of the vault even with
// no search query. Three consumers must not notice: the duplicate service, the
// health report and the autofill publisher all reason about the WHOLE vault,
// and quietly narrowing any of them to the selected folder would under-report
// duplicates, inflate the health score and publish a partial credential set to
// the OS — three silent wrongs, none of which shows up as a crash.
//
// Research R1 records that all three read `allEntries` today. This test pins
// that behaviourally rather than by reading the source: it drives the bloc with
// a search query narrow enough to leave one visible record, then asserts each
// consumer still saw all four.
//
// Written and green BEFORE T007-T010 touch the bloc.

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/vault_csv_import_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_duplicate_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/duplicate_group.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_health_report.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_group.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/domain/services/vault_health_service.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/apple_autofill_v2_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';

const _dbPath = '/vault.kdbx';
const _root = 'root';
const _work = 'work';

VaultEntry _entry(String id, String group, String title, String username) =>
    VaultEntry(
      id: id,
      groupId: group,
      title: title,
      username: username,
      password: 'p-$id',
      url: '',
      notes: '',
    );

// Two of these share a title+username pair, so the real duplicate service has
// something to find; only one matches the search query used below.
final _entries = <VaultEntry>[
  _entry('1', _root, 'Aurora', 'ada'),
  _entry('2', _work, 'Borealis', 'ben'),
  _entry('3', _work, 'Borealis', 'ben'),
  _entry('4', _work, 'Cirrus', 'cy'),
];

final _snapshot = VaultSnapshot(
  rootGroupId: _root,
  currentGroupId: _root,
  groups: const [
    VaultGroup(id: _root, name: 'Vault', parentId: null),
    VaultGroup(id: _work, name: 'Work', parentId: _root),
  ],
  entries: _entries,
  allEntries: _entries,
);

void main() {
  late _SpyDuplicateService duplicates;
  late _SpyHealthService health;
  late _SpyAutofill autofill;
  late VaultBloc bloc;

  setUp(() {
    duplicates = _SpyDuplicateService();
    health = _SpyHealthService();
    autofill = _SpyAutofill();
    bloc = VaultBloc(
      databasePath: _dbPath,
      getSelectedKeyFilePath: () async => null,
      sessionSecretHolder: SessionSecretHolder()..set('secret'),
      vaultKdbxService: _FakeKdbx(),
      vaultCsvImportService: VaultCsvImportService(),
      vaultDuplicateService: duplicates,
      databaseSyncRepository: _FakeSyncRepo(),
      appleAutofillV2Coordinator: autofill,
      vaultHealthService: health,
    );
  });

  tearDown(() => bloc.close());

  Future<void> initialize() async {
    bloc.add(const InitializeVault());
    await bloc.stream.firstWhere((s) => s.allEntries.length == _entries.length);
    // The duplicate and health passes run after the reload inside the same
    // handler; give the event loop a turn so both have landed.
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'a search that hides three records changes none of the three readers',
    () async {
      await initialize();
      expect(duplicates.seen, isNotEmpty, reason: 'duplicates never ran');
      expect(health.seen, isNotEmpty, reason: 'health never ran');
      expect(autofill.seen, isNotEmpty, reason: 'autofill never published');

      final duplicatesBefore = duplicates.seen.last;
      final healthBefore = health.seen.last;
      final autofillBefore = autofill.seen.last;

      bloc.add(const UpdateVaultSearchQuery('Aurora'));
      await bloc.stream.firstWhere((s) => s.visibleEntries.length == 1);

      // The premise: the search really did narrow the visible set.
      expect(bloc.state.visibleEntries.single.title, 'Aurora');
      expect(bloc.state.allEntries.length, 4);

      // …and none of the three readers moved with it.
      expect(duplicates.seen.last, duplicatesBefore);
      expect(health.seen.last, healthBefore);
      expect(autofill.seen.last, autofillBefore);
    },
  );

  test(
    'the duplicate service is handed the whole vault, not the visible list',
    () async {
      await initialize();
      expect(duplicates.seen.last.map((e) => e.id).toSet(), {
        '1',
        '2',
        '3',
        '4',
      });
    },
  );

  test('the health report is built over the whole vault', () async {
    await initialize();
    expect(health.seen.last.map((e) => e.id).toSet(), {'1', '2', '3', '4'});
  });

  test('autofill publishes every credential, not the visible ones', () async {
    await initialize();
    expect(autofill.seen.last.map((e) => e.id).toSet(), {'1', '2', '3', '4'});
  });
}

class _SpyDuplicateService implements VaultDuplicateService {
  final List<List<VaultEntry>> seen = [];
  final _real = VaultDuplicateService();

  @override
  List<DuplicateGroup> findDuplicates(List<VaultEntry> allEntries) {
    seen.add(List<VaultEntry>.of(allEntries));
    return _real.findDuplicates(allEntries);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyHealthService extends VaultHealthService {
  _SpyHealthService();

  final List<List<VaultEntry>> seen = [];

  @override
  VaultHealthReport buildReport({
    required List<VaultEntry> activeEntries,
    required List<DuplicateGroup> duplicateGroups,
    required DateTime now,
  }) {
    seen.add(List<VaultEntry>.of(activeEntries));
    return super.buildReport(
      activeEntries: activeEntries,
      duplicateGroups: duplicateGroups,
      now: now,
    );
  }
}

class _SpyAutofill implements AppleAutofillV2CoordinatorContract {
  final List<List<VaultEntry>> seen = [];

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    seen.add(List<VaultEntry>.of(entries));
  }

  @override
  Future<void> clearCredentials({String? databasePath}) async {}

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async => const [];

  @override
  Future<void> clearPendingAssociations({List<String>? ids}) async {}
}

class _FakeKdbx implements VaultKdbxService {
  @override
  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async => _snapshot;

  @override
  Future<List<VaultEntry>> loadRecycleBinEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncRepo implements DatabaseSyncRepository {
  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) async => null;

  @override
  Future<bool> isConnected() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
