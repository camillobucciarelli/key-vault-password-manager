// spec-019 C-04-05 — `Duplicate`.
//
// The action is a new capability, so it gets the test the audit says it owes.
// What matters here is that the copy is made by the service (which is the only
// place that can carry protected strings, custom fields and attachment bytes)
// and that the bloc asks for it with the right record and the right suffix —
// not that the bloc reassembles a record out of fields it happens to know.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';

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

  test('duplicating asks the service, not the field list', () async {
    await ready();
    bloc.add(const DuplicateVaultEntry('e-work'));
    await bloc.stream.firstWhere((s) => s.allEntries.length == 5);

    expect(kdbx.duplicated, hasLength(1));
    expect(kdbx.duplicated.single.entryId, 'e-work');
    expect(kdbx.duplicated.single.titleSuffix, kDuplicateTitleSuffix);
  });

  test('the copy carries the suffix and appears in the list', () async {
    await ready();
    bloc.add(const DuplicateVaultEntry('e-work'));
    await bloc.stream.firstWhere((s) => s.allEntries.length == 5);

    expect(
      bloc.state.allEntries.map((entry) => entry.title),
      contains('Borealis copy'),
    );
  });

  test('the copy lands in the source folder, not the selected one', () async {
    await ready();
    // `All items` is selected; the source lives in `work`.
    bloc.add(const DuplicateVaultEntry('e-work'));
    await bloc.stream.firstWhere((s) => s.allEntries.length == 5);

    final copy = bloc.state.allEntries.firstWhere(
      (entry) => entry.title == 'Borealis copy',
    );
    expect(copy.groupId, 'work');
  });

  test('the copy keeps the password and the custom fields', () async {
    await ready();
    bloc.add(const DuplicateVaultEntry('e-work'));
    await bloc.stream.firstWhere((s) => s.allEntries.length == 5);

    final source = bloc.state.allEntries.firstWhere((e) => e.id == 'e-work');
    final copy = bloc.state.allEntries.firstWhere(
      (entry) => entry.title == 'Borealis copy',
    );
    // The TOTP secret lives in the custom fields, which is why the copy is
    // made in the service rather than through `CreateVaultEntry`.
    expect(copy.password, source.password);
    expect(copy.customFields, source.customFields);
  });

  test('a record that vanished first reports instead of throwing', () async {
    await ready();
    bloc.add(const DuplicateVaultEntry('does-not-exist'));
    // Asserted on the emitted state, not on `bloc.state`: a later state can
    // clear the message, and what this pins is that the failure was reported
    // at all rather than swallowed.
    final failed = await bloc.stream.firstWhere((s) => s.errorMessage != null);

    expect(failed.errorMessage, 'Unable to duplicate record.');
    expect(failed.isSaving, isFalse);
    expect(kdbx.duplicated, isEmpty);
  });
}
