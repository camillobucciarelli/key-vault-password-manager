import '../services/password_generator_service.dart';

/// 009 / B001 — global, non-secret generator settings snapshot (schema v1).
///
/// The value is app-owned: it is persisted only by the app through
/// [PasswordGeneratorSettingsRepository], never received from or persisted by
/// the browser extension or the native host. It contains no password, seed,
/// entropy, history, vault id, or site data.
class GeneratorSettingsSnapshot {
  const GeneratorSettingsSnapshot({
    required this.revision,
    required this.length,
    required this.includeLowercase,
    required this.includeUppercase,
    required this.includeDigits,
    required this.includeSymbols,
  });

  /// First-install defaults. The values mirror the previous dialog-local
  /// `PasswordGeneratorOptions.defaults()` — that constructor is the
  /// migration baseline only, not a settings contract (B001).
  const GeneratorSettingsSnapshot.defaults()
    : revision = 1,
      length = 16,
      includeLowercase = true,
      includeUppercase = true,
      includeDigits = true,
      includeSymbols = true;

  static const int schemaVersion = 1;
  static const int minLength = 8;
  static const int maxLength = 64;

  final int revision;
  final int length;
  final bool includeLowercase;
  final bool includeUppercase;
  final bool includeDigits;
  final bool includeSymbols;

  int get enabledSetsCount {
    var count = 0;
    if (includeLowercase) count++;
    if (includeUppercase) count++;
    if (includeDigits) count++;
    if (includeSymbols) count++;
    return count;
  }

  bool get isValid =>
      revision >= 1 &&
      length >= minLength &&
      length <= maxLength &&
      enabledSetsCount >= 1;

  /// Bridge to the existing generation code path — the service is reused,
  /// not reimplemented (B001).
  PasswordGeneratorOptions toOptions() {
    return PasswordGeneratorOptions(
      length: length,
      includeLowercase: includeLowercase,
      includeUppercase: includeUppercase,
      includeDigits: includeDigits,
      includeSymbols: includeSymbols,
    );
  }

  GeneratorSettingsSnapshot copyWith({
    int? revision,
    int? length,
    bool? includeLowercase,
    bool? includeUppercase,
    bool? includeDigits,
    bool? includeSymbols,
  }) {
    return GeneratorSettingsSnapshot(
      revision: revision ?? this.revision,
      length: length ?? this.length,
      includeLowercase: includeLowercase ?? this.includeLowercase,
      includeUppercase: includeUppercase ?? this.includeUppercase,
      includeDigits: includeDigits ?? this.includeDigits,
      includeSymbols: includeSymbols ?? this.includeSymbols,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GeneratorSettingsSnapshot &&
        other.revision == revision &&
        other.length == length &&
        other.includeLowercase == includeLowercase &&
        other.includeUppercase == includeUppercase &&
        other.includeDigits == includeDigits &&
        other.includeSymbols == includeSymbols;
  }

  @override
  int get hashCode => Object.hash(
    revision,
    length,
    includeLowercase,
    includeUppercase,
    includeDigits,
    includeSymbols,
  );
}

/// Thrown when a draft fails validation (length range, no enabled set).
class GeneratorSettingsValidationException implements Exception {
  const GeneratorSettingsValidationException();

  @override
  String toString() => 'GeneratorSettingsValidationException';
}

/// Thrown when Apply carries a revision older than the committed one —
/// a dirty draft raced a concurrent commit and must reload/reapply (B002).
class GeneratorSettingsStaleRevisionException implements Exception {
  const GeneratorSettingsStaleRevisionException();

  @override
  String toString() => 'GeneratorSettingsStaleRevisionException';
}

/// Thrown when the persisted value carries an unknown future schema version.
/// Save must not overwrite it; only an explicit [reset] may replace it (B002).
class GeneratorSettingsUnsupportedVersionException implements Exception {
  const GeneratorSettingsUnsupportedVersionException();

  @override
  String toString() => 'GeneratorSettingsUnsupportedVersionException';
}

/// Thrown when persisting fails; the last valid snapshot stays active and no
/// watch event is published (B002).
class GeneratorSettingsWriteException implements Exception {
  const GeneratorSettingsWriteException();

  @override
  String toString() => 'GeneratorSettingsWriteException';
}

/// 009 / B001 — app-owned source of truth for global generator settings.
abstract class PasswordGeneratorSettingsRepository {
  /// Validates and returns the committed snapshot. Missing state persists
  /// first-install defaults once; corrupt state falls back to persisted
  /// defaults; an unknown future schema returns defaults in memory without
  /// overwriting the stored value.
  Future<GeneratorSettingsSnapshot> read();

  /// Validates [draft], rejects a stale [expectedRevision], increments the
  /// revision, persists atomically, then publishes exactly one update.
  Future<GeneratorSettingsSnapshot> save(
    GeneratorSettingsSnapshot draft, {
    required int expectedRevision,
  });

  /// Explicit reset: atomically persists defaults with the next revision and
  /// publishes once. This is the only operation allowed to replace an
  /// unknown-future-version value.
  Future<GeneratorSettingsSnapshot> reset();

  /// One global source of truth for app UI and generation consumers.
  Stream<GeneratorSettingsSnapshot> watch();
}
