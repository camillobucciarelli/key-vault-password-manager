import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class GoogleTokenDataSource {
  Future<void> saveDesktopCredentialsJson(String json);
  Future<String?> getDesktopCredentialsJson();
  Future<void> clearDesktopCredentialsJson();
}

class GoogleTokenDataSourceImpl implements GoogleTokenDataSource {
  GoogleTokenDataSourceImpl({required this.secureStorage});

  static const _desktopCredentialsJsonKey = 'GOOGLE_DESKTOP_CREDENTIALS_JSON';

  final FlutterSecureStorage secureStorage;

  @override
  Future<void> saveDesktopCredentialsJson(String json) {
    return secureStorage.write(key: _desktopCredentialsJsonKey, value: json);
  }

  @override
  Future<String?> getDesktopCredentialsJson() {
    return secureStorage.read(key: _desktopCredentialsJsonKey);
  }

  @override
  Future<void> clearDesktopCredentialsJson() {
    return secureStorage.delete(key: _desktopCredentialsJsonKey);
  }
}
