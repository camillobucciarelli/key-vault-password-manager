import 'package:local_auth/local_auth.dart';
import 'package:loggy/loggy.dart';

abstract class BiometricDataSource {
  Future<bool> isBiometricAvailable();
  Future<bool> authenticate({required String reason});
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
}
