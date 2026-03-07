import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:loggy/loggy.dart';

class ValidateDatabaseUseCase {
  Future<bool> call(String path) async {
    if (kIsWeb) {
      // On web we cannot reliably use dart:io File. Return true to assume valid
      // or implement web-specific validation.
      return true;
    }

    final file = File(path);
    if (!await file.exists()) {
      return false;
    }

    try {
      final RandomAccessFile raf = await file.open(mode: FileMode.read);
      // Ensure file has at least 8 bytes for checking signatures
      if (await file.length() < 8) {
        await raf.close();
        return false;
      }

      final Uint8List headerBytes = await raf.read(8);
      await raf.close();

      final ByteData bd = ByteData.sublistView(headerBytes);
      final int sig1 = bd.getUint32(0, Endian.little);
      final int sig2 = bd.getUint32(4, Endian.little);

      // KDBX Magic numbers
      // Signature 1: 0x9AA2D903
      // Signature 2: 0xB54BFB67 (KDBX 3.x and 4.x)
      if (sig1 == 0x9AA2D903 && sig2 == 0xB54BFB67) {
        return true;
      }

      return false;
    } catch (e, st) {
      logError('Failed while validating KDBX file header.', e, st);
      return false;
    }
  }
}
