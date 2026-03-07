import 'dart:io';
import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';

class UnlockDatabaseUseCase {
  Future<void> call({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async {
    final dbFile = File(databasePath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found.');
    }

    Uint8List? keyFileBytes;
    if (keyFilePath != null && keyFilePath.trim().isNotEmpty) {
      final keyFile = File(keyFilePath);
      if (!await keyFile.exists()) {
        throw Exception('Key file not found.');
      }
      keyFileBytes = await keyFile.readAsBytes();
    }

    final credentials = Credentials.composite(
      ProtectedValue.fromString(password),
      keyFileBytes,
    );

    final dbBytes = await dbFile.readAsBytes();
    await KdbxFormat().read(dbBytes, credentials);
  }
}
