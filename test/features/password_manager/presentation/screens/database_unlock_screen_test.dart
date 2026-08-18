// spec-003: DatabaseUnlockScreen behaviour/copy/layout.
//
// Successful unlock navigates to `VaultScreen`, which needs its own large
// DI graph (VaultBloc, VaultSessionCoordinator, ...) outside spec-003's
// scope to fake here. Tests that need to observe a "would succeed" submit
// use `FakeUnlockDatabaseUseCase.hang = true` so the bloc reaches
// `decrypting` (proving the submit dispatched with the right arguments)
// without ever completing into `unlocked` and attempting that navigation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_security_profile.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_state.dart';

import 'database_selection_unlock_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() async {
    await (FontLoader(
      'Caprasimo',
    )..addFont(rootBundle.load('assets/fonts/Caprasimo-Regular.ttf'))).load();
    await (FontLoader('Figtree')
          ..addFont(rootBundle.load('assets/fonts/Figtree-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Figtree-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Figtree-Bold.ttf')))
        .load();
  });

  tearDown(resetDatabaseTestDi);

  const path = '/tmp/personal.kdbx';
  final records = [
    DatabaseRecord(
      databaseId: 'db-1',
      canonicalPath: path,
      displayName: 'personal.kdbx',
      sourceType: DatabaseSourceType.local,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];
  const profiles = {
    'db-1': DatabaseSecurityProfile(
      databaseId: 'db-1',
      biometricProtectionEnabled: false,
    ),
  };

  group('Submit', () {
    testWidgets('dispatches the entered password to the unlock use case', (
      tester,
    ) async {
      final result = await pumpableUnlockScreen(
        databasePath: path,
        records: records,
        securityProfiles: profiles,
      );
      result.harness.unlockUseCase.hang = true;

      await tester.pumpWidget(result.widget);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'kv-test-only-not-a-real-password');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock vault'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(result.harness.unlockUseCase.callCount, 1);
      expect(result.harness.unlockUseCase.lastPassword, 'kv-test-only-not-a-real-password');
      expect(result.harness.unlockUseCase.lastDatabasePath, path);
    });

    testWidgets('submit button is disabled with no credentials', (
      tester,
    ) async {
      final result = await pumpableUnlockScreen(
        databasePath: path,
        records: records,
        securityProfiles: profiles,
      );

      await tester.pumpWidget(result.widget);
      await tester.pumpAndSettle();

      final buttonFinder = find.ancestor(
        of: find.text('Unlock vault'),
        matching: find.byType(ElevatedButton),
      );
      expect(tester.widget<ElevatedButton>(buttonFinder).onPressed, isNull);
    });
  });

  group('Biometric gate', () {
    testWidgets(
      'failed authentication does not unlock and offers Retry',
      (tester) async {
        final result = await pumpableUnlockScreen(
          databasePath: path,
          records: records,
          securityProfiles: const {
            'db-1': DatabaseSecurityProfile(
              databaseId: 'db-1',
              biometricProtectionEnabled: true,
            ),
          },
          biometricAvailable: true,
          hangBiometricAuthenticate: true,
        );

        await tester.pumpWidget(result.widget);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(result.harness.unlockUseCase.callCount, 0);
        expect(find.text('Retry'), findsOneWidget);

        final blocContext = tester.element(find.byType(Scaffold).first);
        expect(
          blocContext.read<DatabaseUnlockBloc>().state.phase,
          UnlockPhase.biometricGate,
        );
      },
    );
  });

  group('Key file flow', () {
    testWidgets('selecting then removing a key file updates the form', (
      tester,
    ) async {
      // FR-5: the key-file card (with its Change/Remove buttons) is mobile
      // only — desktop uses a "Key file…" secondary pill instead. Pin the
      // viewport to mobile width so this card-focused test exercises the
      // surface it targets rather than the default (desktop-width) test
      // window.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final result = await pumpableUnlockScreen(
        databasePath: path,
        records: records,
        securityProfiles: profiles,
      );
      const keyPath = '/tmp/personal.key';
      result.harness.fileRepository.existingPaths.add(keyPath);

      await tester.pumpWidget(result.widget);
      await tester.pumpAndSettle();

      final bloc = tester
          .element(find.byType(Scaffold).first)
          .read<DatabaseUnlockBloc>();

      bloc.add(const UpdateKeyFilePath(keyPath));
      await tester.pumpAndSettle();
      expect(find.text('Unlock with key file'), findsOneWidget);
      expect(find.text('Remove key file'), findsOneWidget);

      await tester.tap(find.text('Remove key file'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Unlock vault'), findsOneWidget);
      // FR-5 mock alignment: the always-visible "Select key file" button is
      // gone; the no-key-file state now shows the "Use a key file" link.
      expect(find.text('Use a key file'), findsOneWidget);
    });
  });

  group('C-3 typed failure placement', () {
    Future<({dynamic harness, dynamic tester})> submitWithError(
      WidgetTester tester,
      DatabaseAccessFailure error,
    ) async {
      final result = await pumpableUnlockScreen(
        databasePath: path,
        records: records,
        securityProfiles: profiles,
      );
      result.harness.unlockUseCase.error = error;

      await tester.pumpWidget(result.widget);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'x');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock vault'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      return (harness: result.harness, tester: tester);
    }

    testWidgets(
      'InvalidCredentialsFailure: inline field error, credential form stays',
      (tester) async {
        await submitWithError(tester, const InvalidCredentialsFailure());

        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.descendant(
            of: find.byType(TextFormField),
            matching: find.text('Incorrect master password or key file.'),
          ),
          findsOneWidget,
        );
        expect(find.text('Unlock vault'), findsOneWidget);
      },
    );

    testWidgets(
      'KeyFileMissingFailure: inline field error naming the required action',
      (tester) async {
        await submitWithError(tester, const KeyFileMissingFailure());

        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.descendant(
            of: find.byType(TextFormField),
            matching: find.text(
              'Key file not found. Locate or select the required key file.',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'DatabaseFileMissingFailure: replaces the credential form with the '
      'failure surface',
      (tester) async {
        await submitWithError(
          tester,
          const DatabaseFileMissingFailure('personal.kdbx'),
        );

        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('Back to database list'), findsOneWidget);
      },
    );

    testWidgets(
      'InvalidDatabaseFileFailure: replaces the credential form with the '
      'failure surface',
      (tester) async {
        await submitWithError(
          tester,
          const InvalidDatabaseFileFailure('personal.kdbx'),
        );

        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('Back to database list'), findsOneWidget);
      },
    );

    testWidgets(
      'CorruptDatabaseFailure: failure surface, never phrased as wrong '
      'password',
      (tester) async {
        await submitWithError(
          tester,
          const CorruptDatabaseFailure('personal.kdbx'),
        );

        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.textContaining('password'), findsNothing);
        expect(find.text('Back to database list'), findsOneWidget);
      },
    );
  });
}
