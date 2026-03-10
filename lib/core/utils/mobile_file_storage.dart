import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MobileFileStorage {
  static bool get isMobilePlatform {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
  }

  static Future<String> saveBytesToAppDirectory({
    required Uint8List bytes,
    required String fileName,
    required String subdirectory,
  }) async {
    final directory = await _ensureSubdirectory(subdirectory);
    final normalized = _normalizeFileName(fileName);
    final filePath = await _buildUniquePath(directory.path, normalized);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<String> copyFileToAppDirectory({
    required String sourcePath,
    required String fallbackFileName,
    required String subdirectory,
  }) async {
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    return saveBytesToAppDirectory(
      bytes: bytes,
      fileName: p.basename(sourcePath).isEmpty
          ? fallbackFileName
          : p.basename(sourcePath),
      subdirectory: subdirectory,
    );
  }

  static Future<Directory> _ensureSubdirectory(String subdirectory) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, subdirectory));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _normalizeFileName(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) {
      return 'file';
    }
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static Future<String> _buildUniquePath(
    String dirPath,
    String fileName,
  ) async {
    final extension = p.extension(fileName);
    final base = p.basenameWithoutExtension(fileName);

    var candidate = p.join(dirPath, fileName);
    var index = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(dirPath, '$base-$index$extension');
      index++;
    }
    return candidate;
  }
}
