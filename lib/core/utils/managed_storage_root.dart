import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// The single resolver for the root of app-managed storage (spec 014 FR-2).
///
/// Desktop (macOS, Windows, Linux) resolves to the application *data*
/// directory — Application Support, `%APPDATA%`, `~/.local/share` — never
/// `~/Documents`, which iCloud Drive, OneDrive and Dropbox routinely
/// synchronise without the user asking.
///
/// Android and iOS keep the app documents directory, which is already the
/// app-private container.
///
/// Every data source and utility that stores managed files resolves through
/// this helper; none may call `path_provider` root getters directly. A guard
/// test pins `getApplicationDocumentsDirectory` to this one production file.
class ManagedStorageRoot {
  const ManagedStorageRoot._();

  /// Overrides platform detection in tests; `null` restores it.
  @visibleForTesting
  static bool? debugIsDesktopOverride;

  static bool get _isDesktop =>
      debugIsDesktopOverride ??
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Resolves the managed storage root directory.
  static Future<Directory> resolveDirectory() => _isDesktop
      ? getApplicationSupportDirectory()
      : getApplicationDocumentsDirectory();

  /// Resolves the managed storage root as a path string.
  static Future<String> resolvePath() async => (await resolveDirectory()).path;
}
