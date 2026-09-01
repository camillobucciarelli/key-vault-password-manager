import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/biometric_data_source.dart';
import 'package:password_manager/features/password_manager/presentation/widgets/managed_key_picker_gate.dart';

/// spec 015 FR-12 / AC-7 (T018/T019): the internal managed-key picker is
/// reachable only after device authentication.
void main() {
  test('grants access after successful device authentication', () async {
    final biometrics = _FakeBiometrics()
      ..deviceAuthSupported = true
      ..deviceCredentialResult = true;
    expect(await authorizeManagedKeyPickerAccess(biometrics), isTrue);
    expect(biometrics.deviceCredentialRequests, 1);
  });

  test('denies access when device authentication is refused', () async {
    final biometrics = _FakeBiometrics()
      ..deviceAuthSupported = true
      ..deviceCredentialResult = false;
    expect(await authorizeManagedKeyPickerAccess(biometrics), isFalse);
  });

  test('a device with no authentication capability cannot be gated and is '
      'not locked out', () async {
    final biometrics = _FakeBiometrics()..deviceAuthSupported = false;
    expect(await authorizeManagedKeyPickerAccess(biometrics), isTrue);
    expect(
      biometrics.deviceCredentialRequests,
      0,
      reason: 'no prompt can exist on such a device',
    );
  });

  test('the gate uses device-credential auth (PIN/passcode fallback), not '
      'biometric-only', () async {
    final biometrics = _FakeBiometrics()
      ..deviceAuthSupported = true
      ..deviceCredentialResult = true;
    await authorizeManagedKeyPickerAccess(biometrics);
    expect(biometrics.biometricOnlyRequests, 0);
    expect(biometrics.deviceCredentialRequests, 1);
  });
}

class _FakeBiometrics implements BiometricDataSource {
  bool deviceAuthSupported = true;
  bool deviceCredentialResult = true;
  int deviceCredentialRequests = 0;
  int biometricOnlyRequests = 0;

  @override
  Future<bool> isBiometricAvailable() async => deviceAuthSupported;

  @override
  Future<bool> authenticate({required String reason}) async {
    biometricOnlyRequests += 1;
    return false;
  }

  @override
  Future<bool> isDeviceAuthSupported() async => deviceAuthSupported;

  @override
  Future<bool> authenticateWithDeviceCredential({
    required String reason,
  }) async {
    deviceCredentialRequests += 1;
    return deviceCredentialResult;
  }
}
