import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureDataSource {
  Future<void> saveMasterPassword(String password);
  Future<String?> getMasterPassword();
  Future<void> clearMasterPassword();
}

class SecureDataSourceImpl implements SecureDataSource {
  static const _masterPasswordKey = 'MASTER_PASSWORD';

  final FlutterSecureStorage secureStorage;

  SecureDataSourceImpl({required this.secureStorage});

  @override
  Future<void> saveMasterPassword(String password) async {
    await secureStorage.write(key: _masterPasswordKey, value: password);
  }

  @override
  Future<String?> getMasterPassword() async {
    return await secureStorage.read(key: _masterPasswordKey);
  }

  @override
  Future<void> clearMasterPassword() async {
    await secureStorage.delete(key: _masterPasswordKey);
  }
}
