// spec 023 T405 — the Android-only "Passkey sign-in" row.
//
// FR-013: below API 34 the platform has no credential provider to register
// with, so the row must say so rather than offer a switch that does nothing.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/repositories/autofill_ports.dart';
import 'package:password_manager/injection_container.dart' as di;

import 'vault_shell_test_utils.dart';

class _FakeAutofillClient implements AppleAutofillV2Client {
  _FakeAutofillClient(this.availability);

  final AndroidPasskeyProviderAvailability availability;

  @override
  bool get isSupported => true;

  @override
  Future<AndroidPasskeyProviderAvailability>
  getPasskeyProviderAvailability() async => availability;

  @override
  Future<bool?> getExtensionEnabled() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(resetVaultShellTestDi);

  /// The override is cleared inside the body, not in `tearDown`:
  /// `_verifyInvariants` runs before teardown and fails a test that leaves a
  /// foundation debug variable set.
  Future<void> asAndroid(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> openSettings(
    WidgetTester tester, {
    required AndroidPasskeyProviderAvailability availability,
  }) async {
    final widget = await pumpableVaultShell();
    di.sl.registerLazySingleton<AppleAutofillV2Client>(
      () => _FakeAutofillClient(availability),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('on API 34+ the row says passkey sign-in is available', (
    tester,
  ) async {
    await asAndroid(() async {
      await openSettings(
        tester,
        availability: const AndroidPasskeyProviderAvailability(
          available: true,
          apiLevel: 34,
        ),
      );

      expect(find.text('Passkey sign-in'), findsOneWidget);
      expect(find.textContaining('Available'), findsOneWidget);
    });
  });

  testWidgets('below API 34 the row says the device is too old, and why', (
    tester,
  ) async {
    await asAndroid(() async {
      await openSettings(
        tester,
        availability: const AndroidPasskeyProviderAvailability(
          available: false,
          apiLevel: 31,
        ),
      );

      expect(find.text('Passkey sign-in'), findsOneWidget);
      expect(find.textContaining('Needs Android 14 or later'), findsOneWidget);
      // The device's own level, so the user can tell what they have.
      expect(find.textContaining('API 31'), findsOneWidget);
    });
  });

  testWidgets('with no client registered the row is simply absent', (
    tester,
  ) async {
    await asAndroid(() async {
      await tester.pumpWidget(await pumpableVaultShell());
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();

      // A host without the platform channel must not show a row it cannot
      // answer for — and must not crash reaching for it.
      expect(find.text('Passkey sign-in'), findsNothing);
    });
  });
}
