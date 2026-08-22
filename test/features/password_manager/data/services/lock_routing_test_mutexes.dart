import 'dart:async';

import 'package:password_manager/features/password_manager/data/services/database_path_mutex.dart';

/// Thrown by [RefusingDatabasePathMutex] instead of running the action.
class LockRefused implements Exception {
  const LockRefused();

  @override
  String toString() => 'LockRefused: withDatabaseLock was not granted';
}

/// Kill-check mutex — spec 008 T105 no-bypass guard.
///
/// Never grants the lock. A correctly routed writer therefore performs ZERO
/// filesystem mutation when driven through this mutex; if a mutation still
/// lands on disk, the writer wrote outside its lock (or lost its routing) and
/// the calling test fails on the untouched-bytes assertion.
class RefusingDatabasePathMutex extends DatabasePathMutex {
  @override
  Future<T> withDatabaseLock<T>(
    Iterable<String> paths,
    Future<T> Function() action,
  ) {
    throw const LockRefused();
  }
}

/// Pass-through mutex that records every acquisition and the maximum nesting
/// depth. `maxDepth > 1` means a routed writer called another routed writer
/// from inside its action — the exact deadlock the T104 doc comment forbids
/// (the real mutex is not reentrant).
class RecordingDatabasePathMutex extends DatabasePathMutex {
  final List<List<String>> acquisitions = <List<String>>[];
  int _depth = 0;
  int maxDepth = 0;

  /// Live nesting depth. Collaborators invoked from inside a routed action
  /// can assert `currentDepth >= 1` to prove they run WHILE the lock is held
  /// — not merely after an acquisition happened (tester finding K3: a
  /// mapping move re-ordered outside the lock still left one recorded
  /// acquisition, so acquisition-count assertions alone cannot kill it).
  int get currentDepth => _depth;

  @override
  Future<T> withDatabaseLock<T>(
    Iterable<String> paths,
    Future<T> Function() action,
  ) async {
    acquisitions.add(List.of(paths));
    _depth++;
    if (_depth > maxDepth) {
      maxDepth = _depth;
    }
    try {
      return await action();
    } finally {
      _depth--;
    }
  }
}
