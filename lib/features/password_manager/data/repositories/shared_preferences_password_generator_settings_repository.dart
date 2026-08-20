import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:loggy/loggy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/password_generator_settings_repository.dart';

/// 009 / B001–B002 — `SharedPreferences`-backed generator settings.
///
/// One JSON object under [storageKey], written atomically at key level.
/// Corruption is reported only as a redacted error code — the corrupt
/// content itself is never logged.
class SharedPreferencesPasswordGeneratorSettingsRepository
    implements PasswordGeneratorSettingsRepository {
  SharedPreferencesPasswordGeneratorSettingsRepository({
    required this.sharedPreferences,
    @visibleForTesting
    Future<bool> Function(String key, String value)? debugWriteOverride,
  }) : _debugWriteOverride = debugWriteOverride;

  static const storageKey = 'password_generator_settings_v1';

  final SharedPreferences sharedPreferences;
  final Future<bool> Function(String key, String value)? _debugWriteOverride;

  final _updates = StreamController<GeneratorSettingsSnapshot>.broadcast();

  /// Last valid snapshot; survives failed writes (B002).
  GeneratorSettingsSnapshot? _lastSnapshot;

  @override
  Future<GeneratorSettingsSnapshot> read() async {
    final loaded = _loadStored();
    switch (loaded) {
      case _StoredSnapshot(:final snapshot):
        _lastSnapshot = snapshot;
        return snapshot;
      case _StoredMissing():
        // First install: persist defaults once.
        const defaults = GeneratorSettingsSnapshot.defaults();
        try {
          await _persist(defaults);
        } on GeneratorSettingsWriteException {
          logWarning('Generator settings error: first_install_write_failed');
        }
        _lastSnapshot = defaults;
        return defaults;
      case _StoredCorrupt(:final code):
        // Fallback to persisted defaults; log the redacted code only.
        logWarning('Generator settings error: $code');
        const defaults = GeneratorSettingsSnapshot.defaults();
        try {
          await _persist(defaults);
        } on GeneratorSettingsWriteException {
          logWarning('Generator settings error: fallback_write_failed');
        }
        _lastSnapshot = defaults;
        return defaults;
      case _StoredFutureVersion():
        // Unknown future schema during downgrade: defaults in memory only.
        // Do not overwrite; explicit reset() replaces it.
        logWarning('Generator settings error: unknown_future_version');
        const defaults = GeneratorSettingsSnapshot.defaults();
        _lastSnapshot = defaults;
        return defaults;
    }
  }

  @override
  Future<GeneratorSettingsSnapshot> save(
    GeneratorSettingsSnapshot draft, {
    required int expectedRevision,
  }) async {
    if (draft.length < GeneratorSettingsSnapshot.minLength ||
        draft.length > GeneratorSettingsSnapshot.maxLength ||
        draft.enabledSetsCount < 1) {
      throw const GeneratorSettingsValidationException();
    }

    final loaded = _loadStored();
    if (loaded is _StoredFutureVersion) {
      throw const GeneratorSettingsUnsupportedVersionException();
    }
    final currentRevision = switch (loaded) {
      _StoredSnapshot(:final snapshot) => snapshot.revision,
      _ => GeneratorSettingsSnapshot.defaults().revision,
    };
    if (expectedRevision != currentRevision) {
      throw const GeneratorSettingsStaleRevisionException();
    }

    final next = draft.copyWith(revision: currentRevision + 1);
    await _persist(next);
    _lastSnapshot = next;
    _updates.add(next);
    return next;
  }

  @override
  Future<GeneratorSettingsSnapshot> reset() async {
    final next = GeneratorSettingsSnapshot.defaults().copyWith(
      revision: _storedRevisionBestEffort() + 1,
    );
    await _persist(next);
    _lastSnapshot = next;
    _updates.add(next);
    return next;
  }

  @override
  Stream<GeneratorSettingsSnapshot> watch() => _updates.stream;

  // --- storage ---

  Future<void> _persist(GeneratorSettingsSnapshot snapshot) async {
    final encoded = jsonEncode({
      'schemaVersion': GeneratorSettingsSnapshot.schemaVersion,
      'revision': snapshot.revision,
      'length': snapshot.length,
      'includeLowercase': snapshot.includeLowercase,
      'includeUppercase': snapshot.includeUppercase,
      'includeDigits': snapshot.includeDigits,
      'includeSymbols': snapshot.includeSymbols,
    });
    final bool committed;
    try {
      committed = await (_debugWriteOverride ?? sharedPreferences.setString)(
        storageKey,
        encoded,
      );
    } catch (_) {
      throw const GeneratorSettingsWriteException();
    }
    if (!committed) {
      throw const GeneratorSettingsWriteException();
    }
  }

  _StoredState _loadStored() {
    final raw = sharedPreferences.getString(storageKey);
    if (raw == null) {
      return const _StoredMissing();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const _StoredCorrupt('malformed_json');
    }
    if (decoded is! Map) {
      return const _StoredCorrupt('invalid_shape');
    }

    final version = decoded['schemaVersion'];
    if (version is! int || version < 1) {
      return const _StoredCorrupt('invalid_version');
    }
    if (version > GeneratorSettingsSnapshot.schemaVersion) {
      return const _StoredFutureVersion();
    }
    // schemaVersion == 1 is the only known version; older versions do not
    // exist, so no version-by-version migration steps are needed yet. Add
    // pure migration steps here when schema v2 lands.

    // Strict shape: exactly the known keys. Unknown keys are treated as
    // corruption so that nothing outside the app (native host, extension)
    // can smuggle state through this value (B002).
    const knownKeys = {
      'schemaVersion',
      'revision',
      'length',
      'includeLowercase',
      'includeUppercase',
      'includeDigits',
      'includeSymbols',
    };
    if (decoded.keys.any((key) => key is! String || !knownKeys.contains(key))) {
      return const _StoredCorrupt('invalid_shape');
    }

    final revision = decoded['revision'];
    final length = decoded['length'];
    final includeLowercase = decoded['includeLowercase'];
    final includeUppercase = decoded['includeUppercase'];
    final includeDigits = decoded['includeDigits'];
    final includeSymbols = decoded['includeSymbols'];
    if (revision is! int ||
        length is! int ||
        includeLowercase is! bool ||
        includeUppercase is! bool ||
        includeDigits is! bool ||
        includeSymbols is! bool) {
      return const _StoredCorrupt('invalid_types');
    }

    final snapshot = GeneratorSettingsSnapshot(
      revision: revision,
      length: length,
      includeLowercase: includeLowercase,
      includeUppercase: includeUppercase,
      includeDigits: includeDigits,
      includeSymbols: includeSymbols,
    );
    if (!snapshot.isValid) {
      return const _StoredCorrupt('invalid_values');
    }
    return _StoredSnapshot(snapshot);
  }

  /// Revision to reset from — best effort even when the stored value is a
  /// future version or corrupt, so reset never re-issues a stale revision.
  int _storedRevisionBestEffort() {
    final loaded = _loadStored();
    if (loaded is _StoredSnapshot) {
      return loaded.snapshot.revision;
    }
    final raw = sharedPreferences.getString(storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['revision'] is int) {
          final revision = decoded['revision'] as int;
          if (revision >= 1) {
            return revision;
          }
        }
      } catch (_) {}
    }
    return _lastSnapshot?.revision ?? 0;
  }
}

sealed class _StoredState {
  const _StoredState();
}

class _StoredSnapshot extends _StoredState {
  const _StoredSnapshot(this.snapshot);

  final GeneratorSettingsSnapshot snapshot;
}

class _StoredMissing extends _StoredState {
  const _StoredMissing();
}

class _StoredCorrupt extends _StoredState {
  const _StoredCorrupt(this.code);

  /// Redacted, non-sensitive error code — never the corrupt content.
  final String code;
}

class _StoredFutureVersion extends _StoredState {
  const _StoredFutureVersion();
}
