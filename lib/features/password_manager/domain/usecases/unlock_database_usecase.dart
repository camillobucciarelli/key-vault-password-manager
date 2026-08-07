import 'dart:io';
import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';
import 'package:path/path.dart' as p;

import '../errors/database_access_failure.dart';

/// KDBX read/unlock boundary. Maps concrete `kdbx` package exceptions to
/// C-3 typed [DatabaseAccessFailure]s so no coordinator/BLoC/UI code needs to
/// inspect raw exception text (and never confuses "corrupted" with "wrong
/// password").
class UnlockDatabaseUseCase {
  Future<void> call({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async {
    final dbFile = File(databasePath);
    if (!await dbFile.exists()) {
      throw DatabaseFileMissingFailure(p.basename(databasePath));
    }

    Uint8List? keyFileBytes;
    if (keyFilePath != null && keyFilePath.trim().isNotEmpty) {
      final keyFile = File(keyFilePath);
      if (!await keyFile.exists()) {
        throw const KeyFileMissingFailure();
      }
      keyFileBytes = await keyFile.readAsBytes();
    }

    final credentials = Credentials.composite(
      ProtectedValue.fromString(password),
      keyFileBytes,
    );

    final dbBytes = await dbFile.readAsBytes();
    try {
      await KdbxFormat().read(dbBytes, credentials);
    } on KdbxInvalidKeyException {
      throw const InvalidCredentialsFailure();
    } on KdbxCorruptedFileException {
      throw CorruptDatabaseFailure(p.basename(databasePath));
    } on KdbxInvalidFileStructure {
      throw CorruptDatabaseFailure(p.basename(databasePath));
    } on KdbxUnsupportedException {
      throw InvalidDatabaseFileFailure(p.basename(databasePath));
    } on DatabaseAccessFailure {
      rethrow;
    } catch (_) {
      // The `kdbx` package can raise plain platform errors (e.g. a
      // `RangeError` while walking a truncated header) for malformed
      // input that never reaches its own `KdbxException` hierarchy. Any
      // such parse-time failure is still a corrupt/unreadable file, never
      // a credentials problem, and must never surface as a raw exception.
      throw CorruptDatabaseFailure(p.basename(databasePath));
    }
  }
}
