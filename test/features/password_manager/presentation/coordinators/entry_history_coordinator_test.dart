// spec 017 T302 — the restore sequence, with fakes: a locked session writes
// nothing, a good write reports done, a bad one reports failed.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/entry_history_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';

class _FakeVaultKdbxService implements VaultKdbxService {
  final List<(String entryId, DateTime replacedAt)> restores = [];
  Object? restoreError;

  @override
  Future<void> restoreEntryRevision({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required DateTime replacedAt,
  }) async {
    if (restoreError != null) throw restoreError!;
    restores.add((entryId, replacedAt));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final replacedAt = DateTime.utc(2026, 3, 1, 12);

  ({EntryHistoryCoordinator coordinator, _FakeVaultKdbxService service}) build({
    bool locked = false,
  }) {
    final service = _FakeVaultKdbxService();
    final holder = SessionSecretHolder();
    if (!locked) holder.set('secret');
    return (
      coordinator: EntryHistoryCoordinator(
        vaultKdbxService: service,
        sessionSecretHolder: holder,
      ),
      service: service,
    );
  }

  test('a locked session writes nothing and reports vaultLocked', () async {
    final (:coordinator, :service) = build(locked: true);

    final result = await coordinator.restore(
      databasePath: '/tmp/v.kdbx',
      entryId: 'e1',
      replacedAt: replacedAt,
    );

    expect(result.outcome, EntryHistoryOutcome.vaultLocked);
    expect(service.restores, isEmpty);
  });

  test('a successful restore reports done', () async {
    final (:coordinator, :service) = build();

    final result = await coordinator.restore(
      databasePath: '/tmp/v.kdbx',
      entryId: 'e1',
      replacedAt: replacedAt,
    );

    expect(result.outcome, EntryHistoryOutcome.done);
    expect(service.restores, [('e1', replacedAt)]);
  });

  test('a failing write reports failed', () async {
    final (:coordinator, :service) = build();
    service.restoreError = StateError('no such revision');

    final result = await coordinator.restore(
      databasePath: '/tmp/v.kdbx',
      entryId: 'e1',
      replacedAt: replacedAt,
    );

    expect(result.outcome, EntryHistoryOutcome.failed);
  });
}
