import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// 009 / B003 — lifecycle states of a pending generated entry.
enum PendingGeneratedEntryState { pending, consumed, rejected, expired }

/// Non-secret view of a pending generated entry. Deliberately has no
/// password accessor: the secret leaves the service exactly once, through
/// [DesktopBrowserPendingGenerationService.consume].
class PendingGeneratedEntrySnapshot {
  const PendingGeneratedEntrySnapshot({
    required this.id,
    required this.databaseId,
    required this.cacheGeneration,
    required this.bridgeGeneration,
    required this.settingsRevision,
    required this.origin,
    required this.createdAtEpochMs,
    required this.expiresAtEpochMs,
    required this.state,
  });

  final String id;
  final String databaseId;
  final String cacheGeneration;
  final String bridgeGeneration;
  final int settingsRevision;
  final String origin;
  final int createdAtEpochMs;
  final int expiresAtEpochMs;
  final PendingGeneratedEntryState state;
}

/// The secret+metadata handed to the app-owned new-entry flow on consume
/// (B005). The app is the only consumer; page/extension never receive it and
/// cannot auto-save — the vault mutation happens through the app's normal
/// new-entry/save path.
class PendingGeneratedNewEntryDraft {
  const PendingGeneratedNewEntryDraft({
    required this.origin,
    required this.password,
    required this.settingsRevision,
  });

  final String origin;
  final String password;
  final int settingsRevision;
}

/// 009 / B003–B004 — in-memory holder for generated-but-not-yet-saved
/// secrets.
///
/// Strictly in-memory and app-owned: nothing here touches disk, the autofill
/// metadata cache, the bridge descriptor, or `pending_associations.json`
/// (the disk-backed `DesktopBrowserAutofillPendingAssociation` is a separate,
/// metadata-only model and is deliberately not reused). Lock, database
/// switch, vault close, reveal-bridge stop, and app exit all clear every
/// record via [clearAll] (process exit clears trivially — the state has no
/// persistence).
///
/// Clearing removes records and the service's reachable references
/// best-effort; Dart strings are immutable, so no claim is made about
/// deterministic memory zeroization or GC timing.
class DesktopBrowserPendingGenerationService {
  DesktopBrowserPendingGenerationService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Bounded collection (B003): oldest record is evicted when full.
  static const maxRecords = 8;

  /// Hard ceiling from the spec: `expiresAt <= created + 5 minutes`.
  static const maxTtl = Duration(minutes: 5);

  final DateTime Function() _clock;
  final _records = <String, _PendingRecord>{};
  final _random = Random.secure();
  final _pendingListenable = ValueNotifier<List<PendingGeneratedEntrySnapshot>>(
    const <PendingGeneratedEntrySnapshot>[],
  );
  Timer? _expiryTimer;

  /// 009 / B005 — non-secret view of the currently *pending* records,
  /// oldest first, for the app UI (vault banner). Snapshots deliberately
  /// carry no password; the secret still leaves the service only through
  /// [consume]. Emits on create/consume/reject/clearAll and when a lazy
  /// expiry is materialized (an internal timer fires at the earliest
  /// pending `expiresAt`, so expired records disappear without a caller
  /// poking the service).
  ValueListenable<List<PendingGeneratedEntrySnapshot>> get pendingListenable =>
      _pendingListenable;

  /// Creates a pending record and returns its opaque id.
  ///
  /// [ttl] is clamped to [maxTtl]. The caller (app bridge endpoint, B006)
  /// provides the current session binding; the settings revision is metadata
  /// only — this service accepts no generator settings and cannot override
  /// them (B002).
  PendingGeneratedEntrySnapshot create({
    required String databaseId,
    required String cacheGeneration,
    required String bridgeGeneration,
    required int settingsRevision,
    required String origin,
    required String password,
    Duration ttl = maxTtl,
  }) {
    _expireStale();
    while (_records.length >= maxRecords) {
      final oldestId = _records.keys.first;
      _records.remove(oldestId);
    }

    final now = _clock().millisecondsSinceEpoch;
    final effectiveTtl = ttl > maxTtl ? maxTtl : ttl;
    final record = _PendingRecord(
      id: _opaqueId(),
      databaseId: databaseId,
      cacheGeneration: cacheGeneration,
      bridgeGeneration: bridgeGeneration,
      settingsRevision: settingsRevision,
      origin: origin,
      password: password,
      createdAtEpochMs: now,
      expiresAtEpochMs: now + effectiveTtl.inMilliseconds,
    );
    _records[record.id] = record;
    _publishPending();
    return record.snapshot();
  }

  /// One-shot consume, bound to the exact origin that owns the record.
  ///
  /// Returns the draft for the app's normal new-entry flow, then drops the
  /// secret reference. Wrong origin, unknown id, expired, or already-terminal
  /// records return null.
  PendingGeneratedNewEntryDraft? consume(String id, {required String origin}) {
    _expireStale();
    final record = _records[id];
    if (record == null ||
        record.state != PendingGeneratedEntryState.pending ||
        record.origin != origin) {
      return null;
    }
    final password = record.password;
    record.state = PendingGeneratedEntryState.consumed;
    record.password = null;
    _publishPending();
    if (password == null) {
      return null;
    }
    return PendingGeneratedNewEntryDraft(
      origin: record.origin,
      password: password,
      settingsRevision: record.settingsRevision,
    );
  }

  /// Explicit rejection: clears the secret, keeps the terminal state.
  bool reject(String id) {
    _expireStale();
    final record = _records[id];
    if (record == null || record.state != PendingGeneratedEntryState.pending) {
      return false;
    }
    record.state = PendingGeneratedEntryState.rejected;
    record.password = null;
    _publishPending();
    return true;
  }

  /// Non-secret view of a record, or null if unknown/evicted.
  PendingGeneratedEntrySnapshot? find(String id) {
    _expireStale();
    return _records[id]?.snapshot();
  }

  int get pendingCount {
    _expireStale();
    return _records.values
        .where((record) => record.state == PendingGeneratedEntryState.pending)
        .length;
  }

  /// Clears all records and secret references. Called on lock, database
  /// switch, vault close, and reveal-bridge stop (B004) via
  /// `DesktopBrowserAutofillCoordinator`.
  void clearAll() {
    for (final record in _records.values) {
      record.password = null;
    }
    _records.clear();
    _publishPending();
  }

  void _expireStale() {
    final now = _clock().millisecondsSinceEpoch;
    var changed = false;
    for (final record in _records.values) {
      if (record.state == PendingGeneratedEntryState.pending &&
          now >= record.expiresAtEpochMs) {
        record.state = PendingGeneratedEntryState.expired;
        record.password = null;
        changed = true;
      }
    }
    if (changed) {
      _publishPending();
    }
  }

  /// Republishes the pending-only snapshot list and (re)arms a one-shot
  /// timer at the earliest pending expiry so the lazy `_expireStale` gets
  /// materialized for listeners even when nobody calls into the service.
  void _publishPending() {
    final pending = _records.values
        .where((record) => record.state == PendingGeneratedEntryState.pending)
        .map((record) => record.snapshot())
        .toList(growable: false);
    _pendingListenable.value = pending;

    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (pending.isEmpty) {
      return;
    }
    final now = _clock().millisecondsSinceEpoch;
    final earliest = pending
        .map((snapshot) => snapshot.expiresAtEpochMs)
        .reduce(min);
    final delay = Duration(milliseconds: max(0, earliest - now) + 1);
    _expiryTimer = Timer(delay, () {
      _expiryTimer = null;
      _expireStale();
      // _expireStale only republishes when something changed; if the
      // injected clock lags wall time (tests), re-arm for the remainder.
      if (_pendingListenable.value.isNotEmpty && _expiryTimer == null) {
        _publishPending();
      }
    });
  }

  String _opaqueId() {
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class _PendingRecord {
  _PendingRecord({
    required this.id,
    required this.databaseId,
    required this.cacheGeneration,
    required this.bridgeGeneration,
    required this.settingsRevision,
    required this.origin,
    required this.password,
    required this.createdAtEpochMs,
    required this.expiresAtEpochMs,
  }) : state = PendingGeneratedEntryState.pending;

  final String id;
  final String databaseId;
  final String cacheGeneration;
  final String bridgeGeneration;
  final int settingsRevision;
  final String origin;
  String? password;
  final int createdAtEpochMs;
  final int expiresAtEpochMs;
  PendingGeneratedEntryState state;

  PendingGeneratedEntrySnapshot snapshot() {
    return PendingGeneratedEntrySnapshot(
      id: id,
      databaseId: databaseId,
      cacheGeneration: cacheGeneration,
      bridgeGeneration: bridgeGeneration,
      settingsRevision: settingsRevision,
      origin: origin,
      createdAtEpochMs: createdAtEpochMs,
      expiresAtEpochMs: expiresAtEpochMs,
      state: state,
    );
  }
}
