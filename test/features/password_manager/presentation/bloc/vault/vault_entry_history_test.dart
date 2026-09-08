// spec 017 T201 — history in the vault state: loaded on demand, cleared when
// the view closes, and never describing a secret.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry_revision.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';

import 'vault_bloc_harness.dart';

/// A fixture secret, written to look like one: the point of these tests is
/// that this string never reaches a description of the state.
const _historicalSecret = 'fixture-old-secret-42';

VaultEntryRevision _revision(DateTime replacedAt) => VaultEntryRevision(
  entryId: 'e-root',
  replacedAt: replacedAt,
  title: 'Aurora',
  username: 'ada',
  password: _historicalSecret,
  url: '',
  notes: 'fixture-old-notes',
);

void main() {
  test('loading populates the history of the asked-for entry', () async {
    final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot())
      ..entryHistory = VaultEntryHistory(
        revisions: [
          _revision(DateTime.utc(2026, 3, 2)),
          _revision(DateTime.utc(2026, 3, 1)),
        ],
        retention: const VaultHistoryRetention(maxItems: 10),
      );
    final bloc = buildTestVaultBloc(snapshot: nestedSnapshot(), kdbx: kdbx);
    addTearDown(bloc.close);
    bloc.add(const InitializeVault());
    await Future<void>.delayed(Duration.zero);

    // FR-015: nothing is read until it is asked for.
    expect(kdbx.historyReads, isEmpty);
    expect(bloc.state.entryHistory, isNull);

    bloc.add(const LoadEntryHistory('e-root'));
    await Future<void>.delayed(Duration.zero);

    expect(kdbx.historyReads, ['e-root']);
    expect(bloc.state.entryHistoryEntryId, 'e-root');
    expect(bloc.state.isEntryHistoryLoading, isFalse);
    expect(bloc.state.entryHistory!.revisions, hasLength(2));
    expect(bloc.state.entryHistory!.retention.maxItems, 10);
  });

  test('closing the view clears the revisions (D6)', () async {
    final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot())
      ..entryHistory = VaultEntryHistory(
        revisions: [_revision(DateTime.utc(2026, 3, 2))],
        retention: const VaultHistoryRetention(maxItems: 10),
      );
    final bloc = buildTestVaultBloc(snapshot: nestedSnapshot(), kdbx: kdbx);
    addTearDown(bloc.close);
    bloc.add(const LoadEntryHistory('e-root'));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.entryHistory, isNotNull);

    bloc.add(const ClearEntryHistory());
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.entryHistory, isNull);
    expect(bloc.state.entryHistoryEntryId, isNull);
    expect(bloc.state.isEntryHistoryLoading, isFalse);
    expect(bloc.state.entryHistoryError, isNull);
  });

  test('the state describes a count, never a revision', () async {
    final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot())
      ..entryHistory = VaultEntryHistory(
        revisions: [
          _revision(DateTime.utc(2026, 3, 2)),
          _revision(DateTime.utc(2026, 3, 1)),
        ],
        retention: const VaultHistoryRetention(maxItems: 10),
      );
    final bloc = buildTestVaultBloc(snapshot: nestedSnapshot(), kdbx: kdbx);
    addTearDown(bloc.close);
    bloc.add(const LoadEntryHistory('e-root'));
    await Future<void>.delayed(Duration.zero);

    final described = bloc.state.toString();
    expect(described, contains('entryHistoryRevisions: 2'));
    expect(described, isNot(contains(_historicalSecret)));
    expect(described, isNot(contains('fixture-old-notes')));
  });

  test('a failed read reports a safe message and no history', () async {
    final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot())
      ..entryHistoryError = StateError('boom');
    final bloc = buildTestVaultBloc(snapshot: nestedSnapshot(), kdbx: kdbx);
    addTearDown(bloc.close);
    bloc.add(const LoadEntryHistory('e-root'));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.entryHistory, isNull);
    expect(bloc.state.isEntryHistoryLoading, isFalse);
    expect(bloc.state.entryHistoryError, isNotNull);
    expect(bloc.state.entryHistoryError, isNot(contains('boom')));
  });
}
