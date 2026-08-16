import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/theme/app_theme.dart';
import 'package:password_manager/features/password_manager/data/services/browser_setup_service.dart';
import 'package:password_manager/features/password_manager/presentation/screens/browser_setup_screen.dart';

void main() {
  group('BrowserSetupScreen', () {
    test('does not complete setup from app bridge alone', () {
      final status = browserSetupInitialStatusForBridge(
        BridgeCheckResult.connected,
      );

      expect(status.appBridgeConnected, isTrue);
      expect(status.extensionStepCompleted, isFalse);
      expect(status.nativeHostStepCompleted, isFalse);
      expect(status.connectionStepCompleted, isFalse);
      expect(status.allConfigured, isFalse);
    });

    testWidgets('shows Chrome-only setup and configures without step 1', (
      tester,
    ) async {
      final installResult = Completer<NativeHostInstallResult>();
      final service = _FakeBrowserSetupService(
        installResult: installResult.future,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BrowserSetupScreen(service: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Apri Chrome Web Store'), findsOneWidget);
      expect(find.text('Configura Chrome'), findsOneWidget);
      expect(find.text('Verifica la connessione'), findsOneWidget);
      expect(find.textContaining('Modalità sviluppatore'), findsNothing);
      expect(find.textContaining('Edge'), findsNothing);
      expect(find.textContaining('Extension ID'), findsNothing);

      // spec-006 T8: action buttons restyled from `FilledButton.tonal` to
      // `KvPillButton` (ElevatedButton-backed).
      final configureButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Configura Chrome'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(configureButton.onPressed, isNotNull);

      await tester.ensureVisible(find.text('Configura Chrome'));
      await tester.tap(find.text('Configura Chrome'));
      await tester.pump();

      expect(service.installCalls, 1);
      expect(find.text('Configurazione in corso…'), findsOneWidget);

      installResult.complete(NativeHostInstallResult.success);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Chrome configurato. Riavvia Chrome e verifica la connessione.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Tutto configurato'), findsNothing);
    });

    testWidgets('explains when Chrome installer is unavailable', (
      tester,
    ) async {
      final service = _FakeBrowserSetupService(
        canRunInstaller: false,
        installResult: Future.value(NativeHostInstallResult.scriptNotFound),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BrowserSetupScreen(service: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Installer Chrome non disponibile in questa versione di KDBX Vault Manager.',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Configura Chrome'));
      await tester.tap(find.text('Configura Chrome'));
      await tester.pumpAndSettle();

      expect(service.installCalls, 1);
      expect(
        find.text(
          'Installer Chrome non disponibile in questa versione di KDBX Vault Manager.',
        ),
        findsNWidgets(2),
      );
    });
  });
}

class _FakeBrowserSetupService extends BrowserSetupService {
  _FakeBrowserSetupService({
    required this.installResult,
    this.canRunInstaller = true,
  });

  final Future<NativeHostInstallResult> installResult;
  final bool canRunInstaller;
  int installCalls = 0;

  @override
  bool get canRunNativeHostInstaller => canRunInstaller;

  @override
  Future<BridgeCheckResult> checkBridgeConnection() async {
    return BridgeCheckResult.notRunning;
  }

  @override
  Future<NativeHostInstallResult> installNativeHost() {
    installCalls++;
    return installResult;
  }
}
