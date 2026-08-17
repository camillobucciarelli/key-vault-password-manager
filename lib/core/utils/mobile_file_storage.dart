import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'portable_path.dart';

class AppStorageFileEntry {
  const AppStorageFileEntry({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
}

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
    bool overwriteIfExists = false,
  }) async {
    final directory = await _ensureSubdirectory(subdirectory);
    final normalized = _normalizeFileName(fileName);
    final filePath = overwriteIfExists
        ? p.join(directory.path, normalized)
        : await _buildUniquePath(directory.path, normalized);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<String> copyFileToAppDirectory({
    required String sourcePath,
    required String fallbackFileName,
    required String subdirectory,
    bool overwriteIfExists = false,
  }) async {
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    return saveBytesToAppDirectory(
      bytes: bytes,
      fileName: p.basename(sourcePath).isEmpty
          ? fallbackFileName
          : p.basename(sourcePath),
      subdirectory: subdirectory,
      overwriteIfExists: overwriteIfExists,
    );
  }

  static Future<String> getPathInAppDirectory({
    required String fileName,
    required String subdirectory,
  }) async {
    final directory = await _ensureSubdirectory(subdirectory);
    final normalized = _normalizeFileName(fileName);
    return p.join(directory.path, normalized);
  }

  static Future<bool> fileExistsInAppDirectory({
    required String fileName,
    required String subdirectory,
  }) async {
    final filePath = await getPathInAppDirectory(
      fileName: fileName,
      subdirectory: subdirectory,
    );
    return File(filePath).exists();
  }

  static Future<List<AppStorageFileEntry>> listFilesInAppDirectory({
    required String subdirectory,
  }) async {
    final directory = await _ensureSubdirectory(subdirectory);
    final entries = await directory.list(followLinks: false).toList();
    final files = <AppStorageFileEntry>[];

    for (final entry in entries) {
      if (entry is! File) {
        continue;
      }
      final stat = await entry.stat();
      files.add(
        AppStorageFileEntry(
          name: p.basename(entry.path),
          path: entry.path,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }

    files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return files;
  }

  static Future<bool> isPathInAppDirectory({
    required String filePath,
    required String subdirectory,
  }) async {
    // A `..` path is never treated as app-managed: `false` is the safe answer
    // in both directions, since callers use this either to skip copying a file
    // into managed storage or as the precondition for
    // deleteFileFromAppDirectory, which refuses traversal outright. The two
    // must agree or a path the guard rejects gets advertised as app-managed.
    if (_containsTraversal(filePath)) {
      return false;
    }

    final directory = await _ensureSubdirectory(subdirectory);
    // Resolved comparison: the file picker hands back `/private/var/...` for
    // files this directory spells as `/var/...`. Same two-condition rule as
    // deleteFileFromAppDirectory — a file counts as app-managed only if both
    // the entry and what it points at live inside.
    final normalizedDirectoryPath = PortablePath.resolveForComparison(
      directory.path,
    );

    bool isInside(String candidate) =>
        p.isWithin(normalizedDirectoryPath, candidate) ||
        normalizedDirectoryPath == candidate;

    return isInside(PortablePath.resolveParentForComparison(filePath)) &&
        isInside(PortablePath.resolveForComparison(filePath));
  }

  /// Whether [path] contains a `..` segment.
  ///
  /// Containment checks compare *textually normalized* paths, which collapse
  /// `<dir>/link/../x` to `<dir>/x` and report "inside". The kernel instead
  /// follows `link` first, so `..` lands wherever the link pointed — outside.
  /// Rejecting traversal outright closes that gap without trying to
  /// out-guess the resolver.
  static bool _containsTraversal(String path) => p.split(path).contains('..');

  static Future<void> deleteFileFromAppDirectory({
    required String filePath,
    required String subdirectory,
  }) async {
    final directory = await _ensureSubdirectory(subdirectory);
    final target = File(filePath);
    final normalizedDirectoryPath = PortablePath.resolveForComparison(
      directory.path,
    );

    // Two independent conditions, both required.
    //
    // 1. Where the entry itself lives, with the leaf NOT followed. `delete()`
    //    unlinks the entry at `filePath`, so a symlink sitting outside app
    //    storage must not pass the guard merely by pointing inside.
    // 2. Where the entry ultimately points. A symlink inside app storage must
    //    not be usable to reach a file outside it.
    // 3. No `..` traversal: see _containsTraversal. A textually-inside path
    //    can still land outside once the kernel follows an intermediate
    //    symlink, so traversal is refused before the containment check.
    final entryPath = PortablePath.resolveParentForComparison(target.path);
    final resolvedTargetPath = PortablePath.resolveForComparison(target.path);

    bool isInside(String candidate) =>
        p.isWithin(normalizedDirectoryPath, candidate) ||
        normalizedDirectoryPath == candidate;

    if (_containsTraversal(filePath) ||
        !isInside(entryPath) ||
        !isInside(resolvedTargetPath)) {
      throw Exception('Cannot delete file outside app storage directory.');
    }

    if (await target.exists()) {
      await target.delete();
    }
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
