import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Serialization boundary helper that keeps persisted file paths portable
/// across app container relocations.
///
/// On iOS the application documents directory lives under
/// `/var/mobile/Containers/Data/Application/<UUID>/Documents`, and `<UUID>`
/// changes on every reinstall/upgrade. Absolute paths frozen into JSON survive
/// the relocation but no longer resolve.
///
/// Wire format: a path inside the current documents root is stored as
/// `appdocs:<relative/posix/path>`; anything else is stored verbatim as an
/// absolute path. A single opaque string was chosen (over a companion
/// `...Base` field) because some persisted paths are map keys or bare entity
/// fields, so there is no room for a sidecar key at those call sites.
///
/// Reading is tolerant: values without the sentinel are returned unchanged,
/// which is what keeps legacy absolute records loadable (they simply stay
/// absolute — there is deliberately no migration).
class PortablePath {
  const PortablePath._();

  static const _prefix = 'appdocs:';

  /// Resolves the current application documents root.
  ///
  /// Deliberately returns the path *as path_provider spells it*, without
  /// symlink resolution: this value is the join base for [decode], so
  /// resolving it here would silently rewrite every path the app hands out
  /// (`/var/...` -> `/private/var/...`). Symlink differences are absorbed by
  /// the containment check in [encode] instead, which is the only place that
  /// actually compares two spellings of the same location.
  static Future<String> documentsRoot() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// Best-effort symlink resolution used only for comparing two paths.
  ///
  /// On iOS and macOS `/var` is a symlink to `/private/var`, and the two APIs
  /// that produce vault paths disagree on the spelling:
  /// `getApplicationDocumentsDirectory()` yields `/var/mobile/Containers/...`
  /// while `UIDocumentPickerViewController` yields
  /// `/private/var/mobile/Containers/...` for the very same file. Comparing
  /// them as strings reports "outside the app directory" and silently defeats
  /// portability.
  ///
  /// `resolveSymbolicLinksSync` throws when the path does not exist, and both
  /// the documents subdirectory and the target file legitimately may not exist
  /// yet. So we walk up to the deepest existing ancestor, resolve that, and
  /// re-append the untouched tail. If nothing resolves we fall back to the
  /// normalized input rather than throwing.
  ///
  /// Note this does not normalize case: `resolveSymbolicLinksSync` preserves
  /// it, and the tail we re-append never touches the filesystem at all.
  static String resolveForComparison(String path) {
    final normalized = p.normalize(path);
    final tail = <String>[];
    var probe = normalized;

    while (true) {
      try {
        final resolved = Directory(probe).resolveSymbolicLinksSync();
        return tail.isEmpty
            ? resolved
            : p.joinAll([resolved, ...tail.reversed]);
      } on FileSystemException {
        final parent = p.dirname(probe);
        if (parent == probe) {
          // Reached the filesystem root without finding anything that exists.
          return normalized;
        }
        tail.add(p.basename(probe));
        probe = parent;
      }
    }
  }

  /// Resolves symlinks on the *parent* of [path] only, leaving the final
  /// segment untouched.
  ///
  /// This is the spelling-normalization half of [resolveForComparison] without
  /// the identity-changing half: intermediate directories still collapse
  /// `/var` onto `/private/var`, but a symlinked leaf is not rewritten into
  /// its target. Use this when the question is "where does this entry live",
  /// and [resolveForComparison] when it is "what does this entry point at".
  static String resolveParentForComparison(String path) {
    final normalized = p.normalize(path);
    final parent = p.dirname(normalized);
    if (parent == normalized) {
      return normalized;
    }
    return p.join(resolveForComparison(parent), p.basename(normalized));
  }

  /// Converts an absolute [absolutePath] into its persisted representation.
  ///
  /// Prefer [encodeWithResolvedRoot] when encoding many paths against one
  /// root; this overload re-resolves the root on every call.
  static String encode(String? absolutePath, String documentsRoot) {
    return encodeWithResolvedRoot(
      absolutePath,
      resolveForComparison(documentsRoot),
    );
  }

  /// [encode] against an already symlink-resolved documents root.
  ///
  /// [resolvedRoot] must come from `resolveForComparison(documentsRoot)`;
  /// passing a raw root defeats the `/var` vs `/private/var` handling.
  static String encodeWithResolvedRoot(
    String? absolutePath,
    String resolvedRoot,
  ) {
    if (absolutePath == null || absolutePath.trim().isEmpty) {
      return absolutePath ?? '';
    }
    if (absolutePath.startsWith(_prefix)) {
      // Already portable; do not double-encode.
      return absolutePath;
    }

    // Parent-only resolution: intermediate directories collapse `/var` onto
    // `/private/var` so a picker-supplied path is still recognized, but the
    // final segment is left alone. Resolving the leaf too would silently
    // rewrite a symlinked `canonicalPath` into its target on the next save,
    // changing the record identity that lookups key on.
    final resolvedPath = resolveParentForComparison(absolutePath);
    if (!p.isWithin(resolvedRoot, resolvedPath)) {
      return absolutePath;
    }

    final relative = p.relative(resolvedPath, from: resolvedRoot);
    // Store with POSIX separators so the value survives a platform change.
    return '$_prefix${p.split(relative).join('/')}';
  }

  /// Restores a persisted value to an absolute path against [documentsRoot].
  static String decode(String? stored, String documentsRoot) {
    if (stored == null || !stored.startsWith(_prefix)) {
      return stored ?? '';
    }

    final relative = stored.substring(_prefix.length);
    if (relative.isEmpty) {
      return documentsRoot;
    }
    return p.joinAll([documentsRoot, ...relative.split('/')]);
  }

  /// Nullable variant used by optional fields such as `keyFilePath`.
  static String? encodeNullable(String? absolutePath, String documentsRoot) {
    if (absolutePath == null) {
      return null;
    }
    return encode(absolutePath, documentsRoot);
  }

  /// Nullable variant used by optional fields such as `keyFilePath`.
  static String? decodeNullable(String? stored, String documentsRoot) {
    if (stored == null) {
      return null;
    }
    return decode(stored, documentsRoot);
  }
}
