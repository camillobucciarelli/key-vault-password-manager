import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/otpauth_deep_link_coordinator.dart';

void main() {
  group('OtpAuthPayload', () {
    test('parses standard TOTP URI without exposing the secret', () {
      final payload = OtpAuthPayload.tryParse(
        'otpauth://totp/Example:alice@example.com?secret=ABC123&issuer=Example',
      );

      expect(payload, isNotNull);
      expect(payload!.title, 'Example');
      expect(payload.username, 'alice@example.com');
      expect(payload.label, 'Example:alice@example.com');
    });

    test('rejects HOTP and migration links', () {
      expect(
        OtpAuthPayload.tryParse(
          'otpauth://hotp/Example:alice?secret=ABC123&counter=1',
        ),
        isNull,
      );
      expect(
        OtpAuthPayload.tryParse('otpauth://migration/offline?data=abc'),
        isNull,
      );
    });

    test('rejects TOTP URI without secret', () {
      expect(
        OtpAuthPayload.tryParse('otpauth://totp/Example:alice?issuer=Example'),
        isNull,
      );
    });
  });

  group('OtpAuthDeepLinkCoordinator', () {
    test('buffers inbound links until vault is available', () async {
      final coordinator = OtpAuthDeepLinkCoordinator();
      coordinator.receiveUrl(
        'otpauth://totp/Example:alice?secret=ABC123&issuer=Example',
      );

      expect(coordinator.pendingCount, 1);

      final eventFuture = coordinator.events.first;
      coordinator.markVaultAvailable();
      final event = await eventFuture;

      expect(event.isValid, isTrue);
      expect(event.otpAuth!.title, 'Example');
      expect(coordinator.pendingCount, 0);
    });

    test('emits controlled error for unsupported links', () async {
      final coordinator = OtpAuthDeepLinkCoordinator();
      final eventFuture = coordinator.events.first;

      coordinator.markVaultAvailable();
      coordinator.receiveUrl('otpauth://migration/offline?data=abc');
      final event = await eventFuture;

      expect(event.isValid, isFalse);
      expect(event.errorMessage, contains('totp'));
    });
  });
}
