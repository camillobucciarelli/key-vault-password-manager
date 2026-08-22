import 'dart:async';

import 'database_path_identity_resolver.dart';

/// Process-wide database write lock — spec 008 Gate 1 T104.
///
/// One DI singleton shared by every database writer (vault mutations, import/
/// commit/rollback, sync replacement/backup, settings/credential/rename,
/// exports — the frozen T101 inventory) plus manual/auto sync and the merge.
/// T105 does the routing; this slice only defines the semantics, so the API
/// is a single wrap: `withDatabaseLock(paths, action)`.
///
/// Semantics:
/// - every path is canonicalized by [DatabasePathIdentityResolver]; aliases of
///   one file share one lock;
/// - multi-path acquisitions are deduplicated and sorted by lock key, and all
///   queue positions are reserved in one synchronous step — both make inverse
///   concurrent renames (A→B vs B→A) deadlock-free;
/// - existing paths are additionally coalesced pairwise via
///   `FileSystemEntity.identical` (hard links, case aliases the string form
///   cannot see);
/// - any identity that is not [DatabasePathIdentity.proven] falls back to the
///   single coarse **global** lock, which excludes every per-path holder —
///   conservative: never two independent locks on paths that might alias.
class DatabasePathMutex {
  DatabasePathMutex({
    DatabasePathIdentityResolver resolver =
        const DatabasePathIdentityResolver(),
  }) : _resolver = resolver;

  final DatabasePathIdentityResolver _resolver;

  final Map<String, _PathLock> _locks = <String, _PathLock>{};

  // Global gate: per-path acquisitions hold it shared; an unproven identity
  // holds it exclusive. FIFO, so neither side starves.
  int _sharedActive = 0;
  bool _exclusiveActive = false;
  final List<_GateWaiter> _gateQueue = <_GateWaiter>[];

  /// Runs [action] while holding the write lock for every path in [paths].
  ///
  /// [paths] may repeat or alias each other (`source == target`, symlinked
  /// spellings, hard links): they collapse onto one lock and never
  /// self-deadlock. Reentrant acquisition from inside [action] is NOT
  /// supported and will deadlock — writers compose by passing all paths of
  /// one logical operation in a single call. **T105 review obligation:** the
  /// routing of each writer must be audited for nesting — no routed writer
  /// may call another routed writer from inside its [action], and no
  /// coordinator may wrap an already-routed writer in a second
  /// [withDatabaseLock]. The pinning test is
  /// `nested acquisition on the same lock does not run while held` in
  /// `database_path_mutex_test.dart`.
  Future<T> withDatabaseLock<T>(
    Iterable<String> paths,
    Future<T> Function() action,
  ) async {
    final identities = paths.map(_resolver.resolve).toList();
    if (identities.isEmpty) {
      throw ArgumentError('withDatabaseLock requires at least one path');
    }

    if (identities.any((identity) => !identity.proven)) {
      await _acquireGate(exclusive: true);
      try {
        return await action();
      } finally {
        _releaseGate(exclusive: true);
      }
    }

    await _acquireGate(exclusive: false);
    List<_PathLock>? held;
    try {
      // Coalescing and queue reservation are one synchronous block (no await
      // between registry reads and writes), so no other acquisition can
      // interleave and no lock-order cycle can form.
      final locks = _coalesce(identities);
      final grants = <Future<void>>[for (final lock in locks) lock.reserve()];
      await Future.wait(grants);
      held = locks;
      return await action();
    } finally {
      if (held != null) {
        for (final lock in held) {
          lock.release();
          if (lock.users == 0) {
            _locks.remove(lock.key);
          }
        }
      }
      _releaseGate(exclusive: false);
    }
  }

  List<_PathLock> _coalesce(List<DatabasePathIdentity> identities) {
    final selected = <_PathLock>{};
    for (final identity in identities) {
      var lock = _locks[identity.lockKey];
      if (lock == null && identity.exists) {
        // ponytail: O(active locks) pairwise probe; active locks are a
        // handful. Catches hard links and on-disk case aliases whose
        // canonical strings differ. `isSameEntity` re-probes the disk as it
        // is now and is fail-safe on a nonexistent candidate, so the
        // candidate's recorded existence is deliberately not consulted.
        for (final candidate in _locks.values) {
          if (_resolver.isSameEntity(
            identity.canonicalPath,
            candidate.canonicalPath,
          )) {
            lock = candidate;
            break;
          }
        }
      }
      if (lock == null) {
        lock = _PathLock(identity.lockKey, identity.canonicalPath);
        _locks[identity.lockKey] = lock;
      }
      if (selected.add(lock)) {
        lock.users++;
      }
    }
    // Deterministic order is a second line of defense: the PRIMARY deadlock
    // guarantee is the atomic synchronous reservation in `withDatabaseLock`
    // (all queue positions taken in one event-loop turn, so no lock-order
    // cycle can form). The sort makes acquisition order deterministic anyway,
    // per the T104 spec, and keeps the property even if a future refactor
    // introduces an await between reservations.
    return selected.toList()..sort((a, b) => a.key.compareTo(b.key));
  }

  Future<void> _acquireGate({required bool exclusive}) {
    final free = !_exclusiveActive && (!exclusive || _sharedActive == 0);
    if (_gateQueue.isEmpty && free) {
      if (exclusive) {
        _exclusiveActive = true;
      } else {
        _sharedActive++;
      }
      return Future<void>.value();
    }
    final waiter = _GateWaiter(exclusive);
    _gateQueue.add(waiter);
    return waiter.completer.future;
  }

  void _releaseGate({required bool exclusive}) {
    if (exclusive) {
      _exclusiveActive = false;
    } else {
      _sharedActive--;
    }
    _pumpGate();
  }

  void _pumpGate() {
    while (_gateQueue.isNotEmpty) {
      final next = _gateQueue.first;
      if (next.exclusive) {
        if (_exclusiveActive || _sharedActive > 0) {
          return;
        }
        _exclusiveActive = true;
        _gateQueue.removeAt(0);
        next.completer.complete();
        return;
      }
      if (_exclusiveActive) {
        return;
      }
      _sharedActive++;
      _gateQueue.removeAt(0);
      next.completer.complete();
    }
  }
}

class _GateWaiter {
  _GateWaiter(this.exclusive);

  final bool exclusive;
  final Completer<void> completer = Completer<void>();
}

class _PathLock {
  _PathLock(this.key, this.canonicalPath);

  final String key;
  final String canonicalPath;

  /// Holders plus queued reservations; the mutex drops the registry entry
  /// only at zero, so a queued waiter can never lose its lock object.
  int users = 0;

  Future<void> _tail = Future<void>.value();
  final List<Completer<void>> _releases = <Completer<void>>[];

  /// Synchronously appends this caller to the FIFO queue and returns a future
  /// that completes when the lock is granted.
  Future<void> reserve() {
    final previous = _tail;
    final release = Completer<void>();
    _releases.add(release);
    _tail = release.future;
    return previous;
  }

  void release() {
    users--;
    _releases.removeAt(0).complete();
  }
}
