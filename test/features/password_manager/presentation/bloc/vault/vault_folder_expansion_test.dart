// spec-019 T013 / FR-006g — folder expansion survives a lock, is per database,
// and is not a filter.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vault_bloc_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  Future<VaultBloc> unlock({String databasePath = testDatabasePath}) async {
    final bloc = buildTestVaultBloc(
      snapshot: nestedSnapshot(),
      kdbx: FakeVaultKdbxService(snapshot: nestedSnapshot()),
      folderExpansionPreferences: preferences,
      databasePath: databasePath,
    );
    bloc.add(const InitializeVault());
    await bloc.stream.firstWhere((s) => s.allEntries.length == 4);
    return bloc;
  }

  Future<void> expand(VaultBloc bloc, String groupId) async {
    bloc.add(SetVaultFolderExpanded(groupId, expanded: true));
    await bloc.stream.firstWhere((s) => s.expandedGroupIds.contains(groupId));
    // The write is fire-and-forget; give it the turn it needs to land.
    await Future<void>.delayed(Duration.zero);
  }

  test('an expanded folder is still expanded after a lock and unlock', () async {
    final first = await unlock();
    await expand(first, 'work');
    await first.close();

    final second = await unlock();
    expect(second.state.expandedGroupIds, contains('work'));
    await second.close();
  });

  test('collapsing is remembered too, not just expanding', () async {
    final first = await unlock();
    await expand(first, 'work');
    first.add(const SetVaultFolderExpanded('work', expanded: false));
    await first.stream.firstWhere(
      (s) => !s.expandedGroupIds.contains('work'),
    );
    await Future<void>.delayed(Duration.zero);
    await first.close();

    final second = await unlock();
    expect(second.state.expandedGroupIds, isNot(contains('work')));
    await second.close();
  });

  test('each database remembers its own folders', () async {
    final first = await unlock();
    await expand(first, 'work');
    await first.close();

    final other = await unlock(databasePath: '/other.kdbx');
    expect(other.state.expandedGroupIds, isNot(contains('work')));
    await other.close();
  });

  test('expanding a folder changes nothing about which records are visible', () async {
    final bloc = await unlock();
    final before = bloc.state.visibleEntries.map((e) => e.id).toList();
    await expand(bloc, 'work');
    expect(bloc.state.visibleEntries.map((e) => e.id).toList(), before);
    await bloc.close();
  });

  test('an unknown folder id is not written to disk', () async {
    final bloc = await unlock();
    bloc.add(const SetVaultFolderExpanded('does-not-exist', expanded: true));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.expandedGroupIds, isNot(contains('does-not-exist')));
    await bloc.close();
  });

  test('the preferences key does not contain the database path', () async {
    final bloc = await unlock();
    await expand(bloc, 'work');
    final keys = preferences.getKeys().where(
      (k) => k.startsWith('vault.folders.expanded.'),
    );
    expect(keys, hasLength(1));
    expect(keys.single, isNot(contains(testDatabasePath)));
    await bloc.close();
  });
}
