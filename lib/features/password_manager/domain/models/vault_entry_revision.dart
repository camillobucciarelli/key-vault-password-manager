import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

import 'vault_custom_field.dart';
import 'vault_entry.dart';

/// spec 017 T101 — one previous version of an entry, as the KDBX writer
/// recorded it. Read-side projection: nothing here is persisted by us.
///
/// Redaction mirrors [VaultEntry] exactly (Constitution I): a revision is not
/// less sensitive than the entry it came from.
class VaultEntryRevision extends Equatable {
  const VaultEntryRevision({
    required this.entryId,
    required this.replacedAt,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    this.customFields = const [],
    this.attachmentNames = const [],
    this.otpUri,
  });

  /// The parent entry's UUID. Shared by every revision of that entry, so it
  /// does not identify the revision; `(entryId, replacedAt)` does.
  final String entryId;

  /// The revision's last-modification time, in UTC.
  final DateTime replacedAt;

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final List<VaultCustomField> customFields;

  /// Names only. Attachment bytes are never read for a revision, and a restore
  /// does not move them (FR-006a).
  final List<String> attachmentNames;

  /// Derived from [customFields], exactly as [VaultEntry.otpUri] is.
  final String? otpUri;

  @override
  List<Object?> get props => [
    entryId,
    replacedAt,
    title,
    username,
    RedactedValue(password),
    url,
    RedactedValue(notes, redaction: '<redacted notes>'),
    customFields,
    attachmentNames,
    otpUri == null
        ? null
        : RedactedValue(otpUri, redaction: '<redacted otpUri>'),
  ];

  @override
  String toString() {
    final otpSummary = otpUri == null ? 'null' : '<redacted>';
    return 'VaultEntryRevision('
        'entryId: $entryId, '
        'replacedAt: $replacedAt, '
        'title: $title, '
        'username: $username, '
        'password: <redacted>, '
        'url: $url, '
        'notes: <redacted>, '
        'customFields: ${customFields.length}, '
        'attachmentNames: ${attachmentNames.length}, '
        'otpUri: $otpSummary)';
  }
}

/// The fields a revision is compared on. Names only ever leave the comparison.
enum VaultEntryField {
  title,
  username,
  password,
  url,
  notes,
  customFields,
  attachments,
  otpUri,
}

/// What the revision list shows without revealing anything.
class VaultEntryRevisionSummary extends Equatable {
  const VaultEntryRevisionSummary({
    required this.replacedAt,
    required this.changedFields,
  });

  final DateTime replacedAt;

  /// Which fields differ from the revision that replaced this one.
  final Set<VaultEntryField> changedFields;

  /// Lets the UI say "password changed" without touching the value.
  bool get hasSecretChange =>
      changedFields.contains(VaultEntryField.password) ||
      changedFields.contains(VaultEntryField.otpUri);

  @override
  List<Object?> get props => [replacedAt, changedFields];

  @override
  String toString() =>
      'VaultEntryRevisionSummary(replacedAt: $replacedAt, '
      'changedFields: $changedFields)';
}

/// The vault-level ceiling on retained revisions. Read and reported, never set
/// by this feature (D7).
class VaultHistoryRetention extends Equatable {
  const VaultHistoryRetention({this.maxItems, this.maxSizeBytes});

  /// `null` when the file states none; negative means unlimited, per KDBX.
  final int? maxItems;
  final int? maxSizeBytes;

  @override
  List<Object?> get props => [maxItems, maxSizeBytes];

  @override
  String toString() =>
      'VaultHistoryRetention(maxItems: $maxItems, '
      'maxSizeBytes: $maxSizeBytes)';
}

/// Revisions and retention limits read together, from one open of the file
/// under one lock — two separate reads could observe two states of it.
class VaultEntryHistory extends Equatable {
  const VaultEntryHistory({required this.revisions, required this.retention});

  /// Newest first (FR-001).
  final List<VaultEntryRevision> revisions;
  final VaultHistoryRetention retention;

  @override
  List<Object?> get props => [revisions, retention];

  @override
  String toString() =>
      'VaultEntryHistory(revisions: ${revisions.length}, '
      'retention: $retention)';
}

/// spec 017 T102 — which fields of [revision] differ from the version that
/// replaced it: [replacedBy], the next newer revision, or [currentEntry] when
/// [revision] is the newest one.
///
/// Compares secret values in memory and emits only field names (FR-004).
Set<VaultEntryField> changedFieldsForRevision({
  required VaultEntryRevision revision,
  required VaultEntry currentEntry,
  VaultEntryRevision? replacedBy,
}) {
  final successor = replacedBy == null
      ? _fieldsOfEntry(currentEntry)
      : _fieldsOfRevision(replacedBy);
  final before = _fieldsOfRevision(revision);

  return {
    for (final field in VaultEntryField.values)
      if (before[field] != successor[field]) field,
  };
}

// ponytail: comparison keys are canonical strings, not deep collection
// equality, so the model keeps its two-import surface (`collection` is not a
// declared dependency). They never leave this file.
Map<VaultEntryField, String?> _fieldsOfRevision(VaultEntryRevision revision) {
  return {
    VaultEntryField.title: revision.title,
    VaultEntryField.username: revision.username,
    VaultEntryField.password: revision.password,
    VaultEntryField.url: revision.url,
    VaultEntryField.notes: revision.notes,
    VaultEntryField.customFields: _customFieldsKey(revision.customFields),
    VaultEntryField.attachments: _namesKey(revision.attachmentNames),
    VaultEntryField.otpUri: revision.otpUri,
  };
}

Map<VaultEntryField, String?> _fieldsOfEntry(VaultEntry entry) {
  return {
    VaultEntryField.title: entry.title,
    VaultEntryField.username: entry.username,
    VaultEntryField.password: entry.password,
    VaultEntryField.url: entry.url,
    VaultEntryField.notes: entry.notes,
    VaultEntryField.customFields: _customFieldsKey(entry.customFields),
    VaultEntryField.attachments: _namesKey(
      entry.attachments.map((attachment) => attachment.name),
    ),
    VaultEntryField.otpUri: entry.otpUri,
  };
}

String _customFieldsKey(List<VaultCustomField> fields) {
  final pairs =
      fields
          .map((field) => '${field.key}\u0000${field.value}')
          .toList(growable: false)
        ..sort();
  return pairs.join('\u0001');
}

String _namesKey(Iterable<String> names) {
  final sorted = names.toList(growable: false)..sort();
  return sorted.join('\u0001');
}
