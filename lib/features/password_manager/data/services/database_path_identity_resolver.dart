import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/utils/portable_path.dart';

/// Resolved identity of a database path — spec 008 Gate 1 T103.
///
/// Two spellings of the same on-disk file (relative vs absolute, `.`/`..`,
/// redundant separators, symlinked path or parent, case aliases on a folding
/// volume) must produce the same [lockKey], so `DatabasePathMutex` never takes
/// two independent locks on one file.
class DatabasePathIdentity {
  const DatabasePathIdentity({
    required this.lockKey,
    required this.canonicalPath,
    required this.proven,
    required this.exists,
  });

  /// Canonical string used to deduplicate/sort/register locks. Case-folded
  /// when the containing volume was proven case-insensitive at runtime.
  final String lockKey;

  /// Absolute, normalized, symlink-resolved path (original case preserved).
  final String canonicalPath;

  /// Whether alias identity is provable well enough for per-path locking.
  ///
  /// `false` — per the feasibility-report design — means the mutex must fall
  /// back to the single coarse global database lock: never two independent
  /// locks on paths that might be the same file. Today the unproven cases are
  /// a target whose parent directory does not exist yet (its future case
  /// semantics cannot be probed) and a path whose case sensitivity could not
  /// be determined at runtime.
  final bool proven;

  /// Whether the canonical path currently exists on disk. When it does,
  /// pairwise [DatabasePathIdentityResolver.isSameEntity] is authoritative
  /// (it sees hard links and case aliases the string never can).
  final bool exists;
}

/// Canonicalizes database paths for lock-identity purposes.
///
/// Pipeline (feasibility report, "Path identity design"):
/// 1. absolute against the working directory, normalize separators/`.`/`..`;
/// 2. chase a dangling-symlink leaf onto its target (writing "through" the
///    link creates the target, so the target is the identity);
/// 3. resolve symlinks via the nearest existing ancestor
///    ([PortablePath.resolveForComparison] — reused, it already implements
///    exactly this, including the `/var` vs `/private/var` divergence);
/// 4. case rules probed **at runtime** per volume, not assumed per platform;
/// 5. hard-link/file identity via [isSameEntity]
///    (`FileSystemEntity.identicalSync`), pairwise, for existing paths.
class DatabasePathIdentityResolver {
  const DatabasePathIdentityResolver();

  DatabasePathIdentity resolve(String path) {
    var absolute = p.normalize(p.absolute(path));

    // A symlink whose target does not exist yet: a write through the link
    // creates the target file, so the identity is the target's, not the
    // link's. Bounded hop count guards against link cycles.
    var hops = 0;
    while (hops < 8 &&
        FileSystemEntity.typeSync(absolute, followLinks: false) ==
            FileSystemEntityType.link &&
        FileSystemEntity.typeSync(absolute) == FileSystemEntityType.notFound) {
      final target = Link(absolute).targetSync();
      absolute = p.normalize(
        p.isAbsolute(target) ? target : p.join(p.dirname(absolute), target),
      );
      hops++;
    }

    final canonical = PortablePath.resolveForComparison(absolute);
    final exists =
        FileSystemEntity.typeSync(canonical) != FileSystemEntityType.notFound;
    final parent = p.dirname(canonical);
    final parentExists =
        exists ||
        FileSystemEntity.typeSync(parent) != FileSystemEntityType.notFound;

    // Runtime case-sensitivity probe on the deepest existing prefix. The
    // platform default (fold on iOS/macOS/Windows) is only a tie-breaker for
    // the lock-key spelling when the probe is inconclusive — an inconclusive
    // probe already forces the global-lock fallback via `proven: false`.
    final String? probeTarget = exists
        ? canonical
        : (parentExists ? parent : null);
    final bool? caseInsensitive = probeTarget == null
        ? null
        : _provenCaseInsensitive(probeTarget);

    final folds =
        caseInsensitive ??
        (Platform.isIOS || Platform.isMacOS || Platform.isWindows);
    return DatabasePathIdentity(
      lockKey: folds ? canonical.toLowerCase() : canonical,
      canonicalPath: canonical,
      proven: parentExists && caseInsensitive != null,
      exists: exists,
    );
  }

  /// Whether [a] and [b] name the same filesystem object (hard links, case
  /// aliases and symlinks included). `false` when either does not exist: a
  /// nonexistent path is not an on-disk object, so it cannot be
  /// hard-link-identical to anything.
  bool isSameEntity(String a, String b) {
    try {
      return FileSystemEntity.identicalSync(a, b);
    } on FileSystemException {
      return false;
    }
  }

  /// Probes whether the volume holding [existingPath] folds case, by statting
  /// the case-flipped spelling of the whole path and asking the OS whether it
  /// is the same object. Decisive both ways for existing paths; `null` when
  /// the path contains no letters to flip.
  ///
  /// ponytail: flipping the whole path makes a "case-insensitive" verdict
  /// hold for every component; a mixed-volume path (insensitive leaf below a
  /// sensitive ancestor) reads as sensitive, which only matters for
  /// not-yet-created files — existing ones are caught pairwise by
  /// [isSameEntity]. Upgrade path: per-directory probes, if such mounts ever
  /// hold vaults.
  bool? _provenCaseInsensitive(String existingPath) {
    final flipped = _flipCase(existingPath);
    if (flipped == existingPath) {
      return null;
    }
    try {
      return FileSystemEntity.identicalSync(existingPath, flipped);
    } on FileSystemException {
      // The flipped spelling does not resolve: the volume distinguishes case.
      return false;
    }
  }

  static String _flipCase(String value) => String.fromCharCodes(
    value.codeUnits.map((unit) {
      final char = String.fromCharCode(unit);
      final upper = char.toUpperCase();
      return char == upper
          ? char.toLowerCase().codeUnitAt(0)
          : upper.codeUnitAt(0);
    }),
  );
}
