// spec-008 T203 — the ONE transient plaintext response in the merge feature.
//
// This type is deliberately isolated in its own library and is NOT exported by
// `sync_merge_models.dart`. Dart imports are not transitive, so a coordinator or
// a BLoC that imports the models, the port or the command use cases cannot name
// `MergeFieldDisplay` at all: to hold one it would have to add an import of this
// file, which
// `test/features/password_manager/domain/sync_merge_domain_architecture_test.dart`
// rejects for every file outside the field-widget allowlist.
//
// It is also, by construction:
//   - not `Equatable` and declares no `props`, so it cannot be a member of a
//     BLoC state's props;
//   - not serializable — no `toJson`, `toMap` or `copyWith`;
//   - redacted in `toString`, so an interpolation into a log line or an error
//     message yields nothing;
//   - disposable, so the widget drops its references on unmount/lock and a read
//     after that throws instead of returning stale plaintext.

/// One side of a field conflict, as shown in the field card.
///
/// `isPresent == false` is a *display* state (FR-4 renders "missing" so the
/// user can see what is being preserved). It is never selectable: the redacted
/// [RedactedMergeDecision] invariants, not this class, are what a choice is
/// validated against.
final class MergeDisplaySide {
  MergeDisplaySide.present(
    String value, {
    DateTime? changedAt,
    int? sizeBytes,
    String? fingerprint,
  }) : isPresent = true,
       _value = value,
       _changedAt = changedAt,
       _sizeBytes = sizeBytes,
       _fingerprint = fingerprint;

  MergeDisplaySide.missing()
    : isPresent = false,
      _value = null,
      _changedAt = null,
      _sizeBytes = null,
      _fingerprint = null;

  final bool isPresent;

  String? _value;
  DateTime? _changedAt;
  int? _sizeBytes;
  String? _fingerprint;

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// The plaintext value. Widget-local and ephemeral: read it into the frame
  /// being built, never into a field of a state object.
  String? get value => _readGuarded(_value);

  DateTime? get changedAt => _readGuarded(_changedAt);

  /// Attachment size in bytes. Attachment *bytes* never leave the data layer.
  int? get sizeBytes => _readGuarded(_sizeBytes);

  /// Short content fingerprint for an attachment, for "same name, different
  /// content" disambiguation. Never the bytes and never a full checksum.
  String? get fingerprint => _readGuarded(_fingerprint);

  T? _readGuarded<T>(T? field) {
    if (_disposed) {
      throw StateError(
        'MergeDisplaySide was disposed; plaintext is no longer available.',
      );
    }
    return field;
  }

  void dispose() {
    _value = null;
    _changedAt = null;
    _sizeBytes = null;
    _fingerprint = null;
    _disposed = true;
  }

  @override
  String toString() => 'MergeDisplaySide(<redacted>)';
}

/// The transient plaintext presentation response for exactly one visible
/// decision, obtained by the field widget directly from
/// `LoadSyncMergeFieldDisplayUseCase` and discarded on dispose or lock.
final class MergeFieldDisplay {
  MergeFieldDisplay({
    required String label,
    required this.local,
    required this.remote,
    required this.protected,
  }) : _label = label;

  /// The field's human label — a custom field name or an attachment name, which
  /// FR-4 keeps data-private until this single transient response is requested.
  String? _label;

  final MergeDisplaySide local;
  final MergeDisplaySide remote;

  /// True for a KDBX protected string; the widget masks it until revealed.
  final bool protected;

  bool _disposed = false;

  bool get isDisposed => _disposed;

  String get label {
    if (_disposed) {
      throw StateError(
        'MergeFieldDisplay was disposed; plaintext is no longer available.',
      );
    }
    return _label!;
  }

  /// Called from the field widget's `dispose()` and on vault lock. Dart cannot
  /// guarantee zeroization, so this minimizes the number of live references
  /// rather than claiming to erase the value.
  void dispose() {
    _label = null;
    local.dispose();
    remote.dispose();
    _disposed = true;
  }

  @override
  String toString() => 'MergeFieldDisplay(<redacted>)';
}
