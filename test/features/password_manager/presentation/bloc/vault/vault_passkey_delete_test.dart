// spec 023 T205 — DeletePasskey: translate and delegate. The bloc sequences
// nothing itself; it forwards the credential to the coordinator, reloads and
// reports, and never names the passkey's secret (FR-010).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/passkey_coordinator.dart';

import 'vault_bloc_harness.dart';

final _credentialId = Uint8List.fromList([1, 2, 3]);

DeletePasskey _event() => DeletePasskey(
  entryId: 'e-root',
  relyingPartyId: 'webauthn.io',
  credentialId: _credentialId,
);

void main() {
  test('done reloads and names the backup', () async {
    final coordinator = _FakePasskeyCoordinator(PasskeyOutcome.done);
    final bloc = buildTestVaultBloc(
      snapshot: nestedSnapshot(),
      passkeyCoordinator: coordinator,
    );
    addTearDown(bloc.close);
    bloc.add(const InitializeVault());
    await Future<void>.delayed(Duration.zero);

    bloc.add(_event());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.deletes, [('e-root', 'webauthn.io')]);
    expect(
      bloc.state.infoMessage,
      'Passkey deleted. A backup was saved as '
      'vault.20260301-120000-000000.pre-delete-passkey.kdbx.',
    );
    expect(bloc.state.isSaving, isFalse);
  });

  test('vaultLocked reports without writing', () async {
    final coordinator = _FakePasskeyCoordinator(PasskeyOutcome.vaultLocked);
    final bloc = buildTestVaultBloc(
      snapshot: nestedSnapshot(),
      passkeyCoordinator: coordinator,
    );
    addTearDown(bloc.close);

    bloc.add(_event());
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.errorMessage, contains('locked'));
    expect(bloc.state.infoMessage, isNull);
  });

  test('failed after the backup says the backup was kept', () async {
    final bloc = buildTestVaultBloc(
      snapshot: nestedSnapshot(),
      passkeyCoordinator: _FakePasskeyCoordinator(PasskeyOutcome.failed),
    );
    addTearDown(bloc.close);

    bloc.add(_event());
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.errorMessage, contains('was kept'));
    expect(bloc.state.isSaving, isFalse);
  });

  test(
    'a passkey already gone reloads and says so, without an error',
    () async {
      final bloc = buildTestVaultBloc(
        snapshot: nestedSnapshot(),
        passkeyCoordinator: _FakePasskeyCoordinator(PasskeyOutcome.notFound),
      );
      addTearDown(bloc.close);
      bloc.add(const InitializeVault());
      await Future<void>.delayed(Duration.zero);

      bloc.add(_event());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.infoMessage, contains('no longer on this record'));
      expect(bloc.state.errorMessage, isNull);
    },
  );

  test('without a coordinator the event reports instead of throwing', () async {
    final bloc = buildTestVaultBloc(snapshot: nestedSnapshot());
    addTearDown(bloc.close);

    bloc.add(_event());
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.errorMessage, 'Unable to delete this passkey.');
  });
}

class _FakePasskeyCoordinator implements PasskeyCoordinator {
  _FakePasskeyCoordinator(this.outcome);

  final PasskeyOutcome outcome;
  final List<(String, String)> deletes = [];

  @override
  Future<PasskeyDeleteResult> deletePasskey({
    required String databasePath,
    String? keyFilePath,
    required String entryId,
    required String relyingPartyId,
    required Uint8List credentialId,
  }) async {
    deletes.add((entryId, relyingPartyId));
    // The real coordinator reports the backup whenever it was written,
    // which for this fake is every outcome but a locked vault.
    return PasskeyDeleteResult(
      outcome,
      backupPath: outcome == PasskeyOutcome.vaultLocked
          ? null
          : '/tmp/vault.20260301-120000-000000.pre-delete-passkey.kdbx',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
