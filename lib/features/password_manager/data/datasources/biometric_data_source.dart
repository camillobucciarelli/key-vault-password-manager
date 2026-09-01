import 'package:local_auth/local_auth.dart';
import 'package:loggy/loggy.dart';

abstract class BiometricDataSource {
  Future<bool> isBiometricAvailable();
  Future<bool> authenticate({required String reason});

  /// spec 015 FR-12: whether ANY device authentication (biometric or system
  /// PIN/passcode) can be requested on this device.
  Future<bool> isDeviceAuthSupported();

  /// spec 015 FR-12: device authentication with system PIN/passcode
  /// fallback — the gate on the managed key-file picker. Unlike
  /// [authenticate], this is not biometric-only.
  Future<bool> authenticateWithDeviceCredential({required String reason});
}

class BiometricDataSourceImpl implements BiometricDataSource {
  final LocalAuthentication localAuthentication;

  BiometricDataSourceImpl({required this.localAuthentication});

  @override
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheckBiometrics = await localAuthentication.canCheckBiometrics;
      final isDeviceSupported = await localAuthentication.isDeviceSupported();
      return canCheckBiometrics && isDeviceSupported;
    } catch (e, st) {
      logError('Unable to check biometric availability.', e, st);
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e, st) {
      logError('Biometric authentication request failed.', e, st);
      return false;
    }
  }

  @override
  Future<bool> isDeviceAuthSupported() async {
    try {
      return await localAuthentication.isDeviceSupported();
    } catch (e, st) {
      logError('Unable to check device authentication support.', e, st);
      return false;
    }
  }

  @override
  Future<bool> authenticateWithDeviceCredential({
    required String reason,
  }) async {
    try {
      return await localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e, st) {
      logError('Device credential authentication request failed.', e, st);
      return false;
    }
  }
}
