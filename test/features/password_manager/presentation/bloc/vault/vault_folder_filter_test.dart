// spec-019 T011 (T-FILTER) — the folder filter, counts, and the tripwire that
// keeps `All items` from disabling the add button.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_state.dart';

import 'vault_bloc_harness.dart';

void main() {
  late VaultBloc bloc;
  late FakeVaultKdbxService kdbx;

  setUp(() {
    kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot());
    bloc = buildTestVaultBloc(snapshot: nestedSnapshot(), kdbx: kdbx);
  });

  tearDown(() => bloc.close());

  Future<void> ready() async {
    bloc.add(const InitializeVault());
    await bloc.stream.firstWhere((s) => s.allEntries.length == 4);
  }

  Future<VaultState> select(String groupId) async {
    bloc.add(SelectVaultFolder(groupId));
    return bloc.stream.firstWhere((s) => s.currentGroupId == groupId);
  }

  Set<String> idsOf(VaultState state) =>
      state.visibleEntries.map((e) => e.id).toSet();

  group('subtree filtering (FR-006h)', () {
    test('All items — the root — shows the whole vault', () async {
      await ready();
      expect(bloc.state.currentGroupId, 'root');
      expect(idsOf(bloc.state), {
        'e-root',
        'e-work',
        'e-client',
        'e-personal',
      });
    });

    test('a folder with children shows its subtree, not just its own records', () async {
      await ready();
      final state = await select('work');
      expect(idsOf(state), {'e-work', 'e-client'});
    });

    test('a leaf folder shows only its own records', () async {
      await ready();
      expect(idsOf(await select('clients')), {'e-client'});
      expect(idsOf(await select('personal')), {'e-personal'});
    });

    test('an unknown folder id is ignored rather than emptying the list', () async {
      await ready();
      final before = idsOf(bloc.state);
      bloc.add(const SelectVaultFolder('does-not-exist'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.currentGroupId, 'root');
      expect(idsOf(bloc.state), before);
    });
  });

  group('counts (FR-006i, FR-002a)', () {
    test('a folder count includes its subfolders', () async {
      await ready();
      expect(bloc.state.folderCounts['work'], 2);
      expect(bloc.state.folderCounts['clients'], 1);
      expect(bloc.state.folderCounts['personal'], 1);
    });

    test('All items equals the whole vault and the root count is the same number', () async {
      await ready();
      expect(bloc.state.totalCount, 4);
      expect(bloc.state.folderCounts['root'], 4);
    });

    test('the recycle bin is in neither the counts nor the subtree', () async {
      await ready();
      expect(bloc.state.folderCounts.containsKey('bin'), isFalse);
      expect(bloc.state.descendantIds('root').contains('bin'), isFalse);
    });
  });

  group('folder, search and sort compose in any order', () {
    test('folder then search', () async {
      await ready();
      await select('work');
      bloc.add(const UpdateVaultSearchQuery('Cirrus'));
      await bloc.stream.firstWhere((s) => s.searchQuery == 'Cirrus');
      expect(idsOf(bloc.state), {'e-client'});
    });

    test('search then folder', () async {
      await ready();
      bloc.add(const UpdateVaultSearchQuery('Cirrus'));
      await bloc.stream.firstWhere((s) => s.searchQuery == 'Cirrus');
      final state = await select('work');
      expect(idsOf(state), {'e-client'});
    });

    test('a search that matches nothing inside the folder shows nothing', () async {
      await ready();
      await select('personal');
      bloc.add(const UpdateVaultSearchQuery('Cirrus'));
      await bloc.stream.firstWhere((s) => s.searchQuery == 'Cirrus');
      expect(bloc.state.visibleEntries, isEmpty);
    });

    test('sort reorders inside the folder without widening it', () async {
      await ready();
      await select('work');
      bloc.add(const SetVaultSort(VaultEntrySort.titleDesc));
      await bloc.stream.firstWhere(
        (s) => s.sortBy == VaultEntrySort.titleDesc,
      );
      expect(
        bloc.state.visibleEntries.map((e) => e.title).toList(),
        ['Cirrus', 'Borealis'],
      );
    });

    test('clearing the search keeps the folder', () async {
      await ready();
      await select('work');
      bloc.add(const UpdateVaultSearchQuery('Cirrus'));
      await bloc.stream.firstWhere((s) => s.searchQuery == 'Cirrus');
      bloc.add(const ClearVaultSearchQuery());
      await bloc.stream.firstWhere((s) => s.searchQuery.isEmpty);
      expect(bloc.state.currentGroupId, 'work');
      expect(idsOf(bloc.state), {'e-work', 'e-client'});
    });
  });

  group('selection does not disturb expansion (FR-006f)', () {
    test('selecting a folder leaves expandedGroupIds untouched', () async {
      await ready();
      final before = List<String>.of(bloc.state.expandedGroupIds);
      await select('clients');
      expect(bloc.state.expandedGroupIds, before);
    });
  });

  // FR-002a's whole reason for existing. `_onCreateVaultEntry` returns early
  // when `currentGroupId` is null — no entry, no error message. Representing
  // `All items` as null would therefore have made the add button dead in the
  // default state, and dead in a way nothing reports.
  test('with All items selected, adding a record still reaches the vault', () async {
    await ready();
    expect(bloc.state.currentGroupId, isNotNull);

    bloc.add(
      const CreateVaultEntry(
        title: 'New record',
        username: 'someone',
        password: 'secret',
        url: '',
        notes: '',
      ),
    );
    await bloc.stream.firstWhere((s) => s.allEntries.length == 5);

    expect(kdbx.createdInGroupIds, ['root']);
    expect(
      bloc.state.visibleEntries.map((e) => e.title),
      contains('New record'),
    );
  });
}
