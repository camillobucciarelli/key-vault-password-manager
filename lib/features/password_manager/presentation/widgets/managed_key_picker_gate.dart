import '../../data/datasources/biometric_data_source.dart';

/// spec 015 FR-12 (T018): app-managed key files appear in the picker only
/// after device authentication via `local_auth`, with system PIN/passcode
/// fallback. Without this gate, biometric protection on a key-only vault
/// would be cosmetic — the managed key already sits on the device.
///
/// On a device with no authentication capability at all the gate cannot be
/// enforced; blocking there would lock key-only vaults out entirely, so the
/// picker opens ungated (the vault's own credentials remain the boundary).
Future<bool> authorizeManagedKeyPickerAccess(
  BiometricDataSource biometrics,
) async {
  if (!await biometrics.isDeviceAuthSupported()) {
    return true;
  }
  return biometrics.authenticateWithDeviceCredential(
    reason: 'Authenticate to access managed key files',
  );
}
