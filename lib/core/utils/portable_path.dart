import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// Overrides [_foldsCase] in tests; `null` restores platform detection.
  ///
  /// Both branches have to be exercised from one host, and the real answer is
  /// baked into the platform the suite happens to run on (case-insensitive on
  /// a macOS dev machine, case-sensitive on Linux CI).
  @visibleForTesting
  static bool? debugFoldsCaseOverride;

  /// Whether the host filesystem treats two spellings of a name as one file.
  ///
  /// True on iOS, Windows, and macOS (whose default APFS volume is
  /// case-insensitive); false on Linux and Android, where `Documents` and
  /// `documents` are genuinely different directories and folding case would
  /// invent containment that does not exist.
  ///
  /// Derived from the platform rather than probed: this only guards a string
  /// comparison, and probing would mean a write to the filesystem on a path
  /// that is often the very thing being encoded.
  ///
  /// Known limitation: the answer is per-platform, but case sensitivity is
  /// really per-*volume*. macOS can format an APFS volume case-sensitive, and
  /// NTFS has a per-directory case-sensitivity flag. On such a volume
  /// `Documents` and `documents` are two distinct directories, and folding
  /// case would claim a containment that does not exist: [encode] would emit
  /// an `appdocs:` value that [decode] rebuilds against the *other* directory,
  /// pointing at a file that is not there — the mirror image of the #43 bug
  /// this fold exists to close.
  ///
  /// Accepted because the fold only ever runs on a root/path pair that already
  /// diverges in case, and no source in this app produces one: the documents
  /// root comes from `path_provider`, and on iOS/macOS that is the app
  /// container on the default (case-insensitive) system volume. The fold is
  /// therefore inert in practice and only fires for the divergence it was
  /// written for.
  ///
  /// Upgrade path if a case-sensitive volume ever becomes reachable: probe the
  /// real volume once per documents root — create a temp file in the root,
  /// stat it through a case-flipped spelling, cache the result — and feed that
  /// into this getter. Deliberately not done here: it costs filesystem I/O in
  /// a pure string helper, and the root is the one path guaranteed to exist,
  /// so the probe belongs next to [documentsRoot], not inside [encode].
  static bool get _foldsCase =>
      debugFoldsCaseOverride ??
      (Platform.isIOS || Platform.isMacOS || Platform.isWindows);

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
  /// Note this does not normalize case by itself. `resolveSymbolicLinksSync`
  /// canonicalizes an existing segment to its on-disk spelling, but the tail we
  /// re-append never touches the filesystem, so a not-yet-existing segment
  /// keeps the caller's case. `_relativeWithin` absorbs that remainder.
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
    final relative = _relativeWithin(resolvedPath, resolvedRoot);
    if (relative == null) {
      return absolutePath;
    }

    // Store with POSIX separators so the value survives a platform change.
    return '$_prefix${p.split(relative).join('/')}';
  }

  /// [path] expressed relative to [root], or `null` when it is not inside it.
  ///
  /// Case is the subtle part (#43). `resolveForComparison` canonicalizes the
  /// spelling of segments that exist on disk, so on a case-insensitive volume
  /// a divergent root normally collapses for free. It does *not* for segments
  /// that do not exist yet: those are re-appended verbatim, keeping the
  /// caller's spelling, so `Documents` vs `documents` still reaches here and
  /// defeats [p.isWithin]. The file genuinely is inside the documents root,
  /// and storing it absolute reintroduces the #41 bug silently.
  ///
  /// Only the *comparison* folds case. The returned segments are sliced off
  /// the original [path], never off the lowercased copy, so the persisted
  /// `appdocs:` value keeps the real filesystem spelling and [decode] rebuilds
  /// a path that actually resolves.
  static String? _relativeWithin(String path, String root) {
    if (p.isWithin(root, path)) {
      return p.relative(path, from: root);
    }
    if (!_foldsCase) {
      return null;
    }

    final lowerRoot = root.toLowerCase();
    final lowerPath = path.toLowerCase();
    if (!p.isWithin(lowerRoot, lowerPath)) {
      return null;
    }

    // Containment holds, so the relative part is a suffix of `path`'s
    // segments. Take it by count rather than by string offset, which keeps
    // this correct when `root` is the filesystem root and has no trailing
    // separator to account for.
    final depth = p.split(p.relative(lowerPath, from: lowerRoot)).length;
    final segments = p.split(path);
    return p.joinAll(segments.sublist(segments.length - depth));
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
