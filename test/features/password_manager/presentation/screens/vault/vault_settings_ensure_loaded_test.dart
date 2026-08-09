// Regression test for the `_ensureLoaded` re-entrancy race in
// `_VaultSettingsDestinationState` (vault_settings.part.dart): `build()`
// calls `_ensureLoaded(databasePath)` on every rebuild, and the
// `_loadedForPath` guard is only set *after* three awaited coordinator
// calls complete. A concurrent rebuild that lands before those awaits
// resolve used to slip past the guard and fire a second, identical set of
// coordinator calls. `_loadingForPath` closes that window.
import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/vault_session_coordinator.dart';

import 'vault_shell_test_utils.dart';

void main() {
  tearDown(resetVaultShellTestDi);

  testWidgets(
    'concurrent rebuilds of the Settings destination query the coordinator '
    'only once per path',
    (tester) async {
      final spy = _SpyVaultSessionCoordinator();
      final widget = await pumpableVaultShell(
        vaultSessionCoordinator: spy,
      );

      await tester.pumpWidget(widget);
      await tester.pump();

      // Navigate to the Settings destination: first build() call, which
      // starts (but — gated by `spy.biometricGate` — never finishes) the
      // coordinator lookups.
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pump();
      expect(spy.biometricCallCount, 1);

      // Force a second build() of the still-mounted Settings destination
      // (same State instance, same databasePath) before the first lookup's
      // await resolves — the exact race the PM flagged (a resize forces a
      // fresh, non-identical widget subtree from the LayoutBuilder the
      // navigation rail sits under, so `Element.updateChild`'s `identical()`
      // fast path doesn't apply and `BlocBuilder` re-runs its builder).
      // Set devicePixelRatio explicitly so the logical (not physical) size
      // change is unambiguous and stays clear of the mobile/desktop layout
      // breakpoint (600) either way.
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(801, 601);
      await tester.pump();

      // Unblock the pending lookups and let `_ensureLoaded` finish.
      spy.biometricGate.complete(false);
      await tester.pumpAndSettle();

      expect(
        spy.biometricCallCount,
        1,
        reason:
            'a second concurrent build() must not re-query the coordinator '
            'for a load already in flight',
      );
    },
  );
}

class _SpyVaultSessionCoordinator implements VaultSessionCoordinator {
  int biometricCallCount = 0;
  final Completer<bool> biometricGate = Completer<bool>();

  @override
  Future<bool> getBiometricProtectionEnabledForPath({
    required String databasePath,
  }) async {
    biometricCallCount++;
    return biometricGate.future;
  }

  @override
  Future<int?> getInactivityLockTimeoutForPath({
    required String databasePath,
  }) async => null;

  @override
  Future<String?> getPersistedKeyFilePath(String databasePath) async => null;

  @override
  Future<String?> getSelectedKeyFilePath() async => null;

  @override
  Future<Set<String>> getProtectedKeyFilePaths() async => const {};

  @override
  Future<void> changeDatabase({required String currentDatabasePath}) async {}

  @override
  Future<void> lockVault({required String currentDatabasePath}) async {}

  @override
  Future<DatabaseSettingsUpdateResult> updateDatabaseSettings(
    DatabaseSettingsUpdateRequest request,
  ) => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
