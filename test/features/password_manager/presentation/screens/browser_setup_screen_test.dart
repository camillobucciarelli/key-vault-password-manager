import 'package:flutter_test/flutter_test.dart';
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
  });
}
