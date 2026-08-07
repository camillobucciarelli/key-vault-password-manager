// spec-003 C-3: ValidateDatabaseUseCase distinguishes "missing" from
// "present but not a valid KDBX structure" (InvalidDatabaseFileFailure at
// the DatabaseImportService layer switches on exactly this enum).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:password_manager/features/password_manager/domain/usecases/validate_database_usecase.dart';

void main() {
  group('ValidateDatabaseUseCase', () {
    late Directory tempDir;
    late ValidateDatabaseUseCase useCase;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('validate-db-usecase');
      useCase = ValidateDatabaseUseCase();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns missing when the file does not exist', () async {
      final result = await useCase(p.join(tempDir.path, 'nope.kdbx'));
      expect(result, DatabaseFileValidation.missing);
    });

    test(
      'returns invalidStructure for a present file with the wrong header',
      () async {
        final path = p.join(tempDir.path, 'not-a-vault.kdbx');
        await File(
          path,
        ).writeAsBytes(Uint8List.fromList('not a kdbx'.codeUnits));

        final result = await useCase(path);

        expect(result, DatabaseFileValidation.invalidStructure);
      },
    );

    test(
      'returns invalidStructure for a file shorter than the 8-byte header',
      () async {
        final path = p.join(tempDir.path, 'too-short.kdbx');
        await File(path).writeAsBytes(Uint8List.fromList([1, 2, 3]));

        final result = await useCase(path);

        expect(result, DatabaseFileValidation.invalidStructure);
      },
    );

    test('returns valid for a correct KDBX magic-number header', () async {
      final path = p.join(tempDir.path, 'real.kdbx');
      // KDBX signature bytes: 0x9AA2D903 (sig1), 0xB54BFB67 (sig2), both
      // little-endian, matching CreateDatabaseUseCase's real output header.
      final bytes = ByteData(8)
        ..setUint32(0, 0x9AA2D903, Endian.little)
        ..setUint32(4, 0xB54BFB67, Endian.little);
      await File(path).writeAsBytes(bytes.buffer.asUint8List());

      final result = await useCase(path);

      expect(result, DatabaseFileValidation.valid);
    });
  });
}
