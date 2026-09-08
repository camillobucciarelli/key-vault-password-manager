// spec 017 T201 — history in the vault state: loaded on demand, cleared when
// the view closes, and never describing a secret.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry_revision.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/entry_history_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';

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

  // spec 017 T304 — the restore event: translate, delegate, reload, tell.
  group('RestoreEntryRevision', () {
    final replacedAt = DateTime.utc(2026, 3, 1);

    test(
      'done reloads, re-reads the open history and tells the user',
      () async {
        final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot());
        final coordinator = _FakeEntryHistoryCoordinator(
          EntryHistoryOutcome.done,
        );
        final bloc = buildTestVaultBloc(
          snapshot: nestedSnapshot(),
          kdbx: kdbx,
          entryHistoryCoordinator: coordinator,
        );
        addTearDown(bloc.close);
        bloc.add(const InitializeVault());
        bloc.add(const LoadEntryHistory('e-root'));
        await Future<void>.delayed(Duration.zero);
        expect(kdbx.historyReads, ['e-root']);

        bloc.add(
          RestoreEntryRevision(entryId: 'e-root', replacedAt: replacedAt),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(coordinator.restores, [('e-root', replacedAt)]);
        expect(bloc.state.infoMessage, 'Previous version restored.');
        expect(bloc.state.errorMessage, isNull);
        expect(bloc.state.isSaving, isFalse);
        // FR-007: the view still open shows the history as it now stands.
        expect(kdbx.historyReads, ['e-root', 'e-root']);
      },
    );

    test('vaultLocked reports without reloading', () async {
      final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot());
      final bloc = buildTestVaultBloc(
        snapshot: nestedSnapshot(),
        kdbx: kdbx,
        entryHistoryCoordinator: _FakeEntryHistoryCoordinator(
          EntryHistoryOutcome.vaultLocked,
        ),
      );
      addTearDown(bloc.close);

      bloc.add(RestoreEntryRevision(entryId: 'e-root', replacedAt: replacedAt));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.errorMessage, contains('locked'));
      expect(bloc.state.infoMessage, isNull);
      expect(bloc.state.isSaving, isFalse);
    });

    test('failed reports a safe message', () async {
      final bloc = buildTestVaultBloc(
        snapshot: nestedSnapshot(),
        entryHistoryCoordinator: _FakeEntryHistoryCoordinator(
          EntryHistoryOutcome.failed,
        ),
      );
      addTearDown(bloc.close);

      bloc.add(RestoreEntryRevision(entryId: 'e-root', replacedAt: replacedAt));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.errorMessage, 'Unable to restore this version.');
      expect(bloc.state.isSaving, isFalse);
    });
  });

  // spec 017 T403 — delete is one service call; clear goes through the
  // coordinator and names the backup.
  group('DeleteEntryRevision', () {
    final replacedAt = DateTime.utc(2026, 3, 1);

    test('deletes, reloads and tells the user', () async {
      final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot());
      final bloc = buildTestVaultBloc(snapshot: nestedSnapshot(), kdbx: kdbx);
      addTearDown(bloc.close);
      bloc.add(const InitializeVault());
      bloc.add(const LoadEntryHistory('e-root'));
      await Future<void>.delayed(Duration.zero);

      bloc.add(DeleteEntryRevision(entryId: 'e-root', replacedAt: replacedAt));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(kdbx.deletedRevisions, [('e-root', replacedAt)]);
      expect(bloc.state.infoMessage, 'Previous version deleted.');
      expect(bloc.state.isSaving, isFalse);
      expect(kdbx.historyReads, ['e-root', 'e-root']);
    });

    test('a locked vault refuses without writing', () async {
      final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot());
      final bloc = buildTestVaultBloc(
        snapshot: nestedSnapshot(),
        kdbx: kdbx,
        sessionSecretHolder: SessionSecretHolder(),
      );
      addTearDown(bloc.close);

      bloc.add(DeleteEntryRevision(entryId: 'e-root', replacedAt: replacedAt));
      await Future<void>.delayed(Duration.zero);

      expect(kdbx.deletedRevisions, isEmpty);
      expect(bloc.state.errorMessage, contains('locked'));
      expect(bloc.state.isSaving, isFalse);
    });

    test('a failing delete reports a safe message', () async {
      final kdbx = FakeVaultKdbxService(snapshot: nestedSnapshot())
        ..deleteRevisionError = StateError('boom');
      final bloc = buildTestVaultBloc(snapshot: nestedSnapshot(), kdbx: kdbx);
      addTearDown(bloc.close);

      bloc.add(DeleteEntryRevision(entryId: 'e-root', replacedAt: replacedAt));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.errorMessage, 'Unable to delete this version.');
      expect(bloc.state.errorMessage, isNot(contains('boom')));
      expect(bloc.state.isSaving, isFalse);
    });
  });

  group('ClearEntryHistoryInFile', () {
    test('done names the backup', () async {
      final coordinator = _FakeEntryHistoryCoordinator(
        EntryHistoryOutcome.done,
      );
      final bloc = buildTestVaultBloc(
        snapshot: nestedSnapshot(),
        entryHistoryCoordinator: coordinator,
      );
      addTearDown(bloc.close);
      bloc.add(const InitializeVault());
      await Future<void>.delayed(Duration.zero);

      bloc.add(const ClearEntryHistoryInFile('e-root'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.clears, ['e-root']);
      expect(
        bloc.state.infoMessage,
        'History cleared. A backup was saved as '
        'vault.20260301-120000-000000.pre-clear-history.kdbx.',
      );
    });

    test('failed after the backup says the backup was kept', () async {
      final bloc = buildTestVaultBloc(
        snapshot: nestedSnapshot(),
        entryHistoryCoordinator: _FakeEntryHistoryCoordinator(
          EntryHistoryOutcome.failed,
        ),
      );
      addTearDown(bloc.close);

      bloc.add(const ClearEntryHistoryInFile('e-root'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.errorMessage, contains('was kept'));
      expect(bloc.state.isSaving, isFalse);
    });

    test('vaultLocked reports without writing', () async {
      final coordinator = _FakeEntryHistoryCoordinator(
        EntryHistoryOutcome.vaultLocked,
      );
      final bloc = buildTestVaultBloc(
        snapshot: nestedSnapshot(),
        entryHistoryCoordinator: coordinator,
      );
      addTearDown(bloc.close);

      bloc.add(const ClearEntryHistoryInFile('e-root'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.errorMessage, contains('locked'));
      expect(bloc.state.infoMessage, isNull);
    });
  });
}

class _FakeEntryHistoryCoordinator implements EntryHistoryCoordinator {
  _FakeEntryHistoryCoordinator(this.outcome);

  final EntryHistoryOutcome outcome;
  final List<(String, DateTime)> restores = [];
  final List<String> clears = [];

  @override
  Future<EntryHistoryRestoreResult> restore({
    required String databasePath,
    String? keyFilePath,
    required String entryId,
    required DateTime replacedAt,
    int ordinal = 0,
  }) async {
    restores.add((entryId, replacedAt));
    return EntryHistoryRestoreResult(outcome);
  }

  @override
  Future<EntryHistoryClearResult> clearHistory({
    required String databasePath,
    String? keyFilePath,
    required String entryId,
  }) async {
    clears.add(entryId);
    // The coordinator reports the backup whenever it was written, which
    // for these fakes is every outcome but a locked vault.
    return EntryHistoryClearResult(
      outcome,
      backupPath: outcome == EntryHistoryOutcome.vaultLocked
          ? null
          : '/tmp/vault.20260301-120000-000000.pre-clear-history.kdbx',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
