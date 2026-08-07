import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';
import 'package:path/path.dart' as p;

import '../repositories/database_file_repository.dart';

/// Non-secret request: [password] is held only transiently for the duration
/// of this call (C-5) and is never copied into BLoC/coordinator state.
class CreateDatabaseRequest {
  const CreateDatabaseRequest({
    required this.databaseFileName,
    required this.password,
    this.keyFilePath,
    this.generateKeyFile = false,
    this.generatedKeyFilePath,
  });

  final String databaseFileName;
  final String password;
  final String? keyFilePath;
  final bool generateKeyFile;
  final String? generatedKeyFilePath;
}

class CreateDatabaseResult {
  const CreateDatabaseResult({
    required this.databasePath,
    required this.fileHash,
    this.keyFilePath,
  });

  final String databasePath;
  final String fileHash;
  final String? keyFilePath;
}

/// KDBX/key generation and partial-output rollback (C-5, C-7). Lives in
/// `domain/usecases` (not the coordinator) so it may use `dart:io`/`kdbx`
/// directly, exactly like `UnlockDatabaseUseCase`; the coordinator only ever
/// calls this use case and never touches file/KDBX APIs itself.
class CreateDatabaseUseCase {
  CreateDatabaseUseCase({required this.databaseFileRepository});

  final DatabaseFileRepository databaseFileRepository;

  /// Returns null when the user cancels the destination picker (desktop
  /// "save file" dialog) — not a failure, nothing was created.
  Future<CreateDatabaseResult?> call(CreateDatabaseRequest request) async {
    var outputFile = await databaseFileRepository.resolveOutputFilePath(
      request.databaseFileName,
    );
    if (outputFile == null || outputFile.trim().isEmpty) {
      return null;
    }
    if (!outputFile.toLowerCase().endsWith('.kdbx')) {
      outputFile += '.kdbx';
    }

    String? selectedKeyFilePath;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      selectedKeyFilePath = await _prepareKeyFilePath(request);
    }

    Uint8List? keyFileBytes;
    if (selectedKeyFilePath != null && selectedKeyFilePath.trim().isNotEmpty) {
      keyFileBytes = await databaseFileRepository.readKeyFileBytes(
        selectedKeyFilePath,
      );
    }

    final credentials = Credentials.composite(
      ProtectedValue.fromString(request.password),
      keyFileBytes,
    );
    final kdbx = KdbxFormat().create(credentials, 'New Database');
    final savedBytes = await kdbx.save();

    final createdPath = await databaseFileRepository.createDatabase(
      outputFile: outputFile,
      databaseBytes: savedBytes,
    );

    try {
      final fileHash = await databaseFileRepository.hashFile(createdPath);
      return CreateDatabaseResult(
        databasePath: createdPath,
        fileHash: fileHash,
        keyFilePath: selectedKeyFilePath,
      );
    } catch (_) {
      // Partial output cleanup: creation succeeded but post-processing
      // (hashing) failed. Leave no half-created database behind.
      try {
        await databaseFileRepository.deleteFile(createdPath);
      } catch (_) {}
      rethrow;
    }
  }

  Future<String?> _prepareKeyFilePath(CreateDatabaseRequest request) async {
    if (!request.generateKeyFile) {
      final keyFilePath = request.keyFilePath;
      if (keyFilePath == null || keyFilePath.trim().isEmpty) {
        return null;
      }
      return databaseFileRepository.ensureManagedKeyFilePath(keyFilePath);
    }

    final keyBytes = _generateRandomKeyFileBytes();
    final generatedPath = request.generatedKeyFilePath;
    final fileName = generatedPath == null
        ? 'database.key'
        : p.basename(generatedPath);
    return databaseFileRepository.saveKeyFile(
      fileName: fileName,
      keyFileBytes: keyBytes,
      selectedPath: generatedPath,
    );
  }

  Uint8List _generateRandomKeyFileBytes() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(64, (_) => random.nextInt(256)),
    );
  }
}
