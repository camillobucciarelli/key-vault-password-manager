import '../../domain/models/duplicate_group.dart';
import '../../domain/models/merge_preview.dart';
import '../../domain/models/vault_entry.dart';
import '../../domain/services/url_field_keys.dart';

class VaultDuplicateService {
  /// Finds duplicate entries in two passes:
  ///
  /// 1. **Credentials groups** — same username + password (both non-empty),
  ///    regardless of URL. These merge into one record carrying all URLs.
  /// 2. **Site groups** — remaining entries with the same normalized URL +
  ///    username (the pre-multi-URL behavior; catches stale-password copies).
  ///
  /// Returns only groups with 2+ entries, sorted by size desc then label asc.
  /// Entries inside each group are sorted newest first (updatedAt, then
  /// createdAt).
  List<DuplicateGroup> findDuplicates(List<VaultEntry> allEntries) {
    final result = <DuplicateGroup>[];
    final consumed = <String>{};

    // Pass 1 — same username + password.
    final byCredentials = <String, List<VaultEntry>>{};
    for (final entry in allEntries) {
      final username = _normalizeUsername(entry.username);
      if (username.isEmpty || entry.password.isEmpty) continue;
      final key = '$username\x00${entry.password}';
      byCredentials.putIfAbsent(key, () => []).add(entry);
    }
    for (final mapEntry in byCredentials.entries) {
      if (mapEntry.value.length < 2) continue;
      final sorted = _sortNewestFirst(mapEntry.value);
      for (final entry in sorted) {
        consumed.add(entry.id);
      }
      result.add(
        DuplicateGroup(
          sharedUsername: _normalizeUsername(sorted.first.username),
          urls: _distinctUrls(sorted),
          entries: sorted,
        ),
      );
    }

    // Pass 2 — same normalized URL + username among the rest.
    final bySite = <String, List<VaultEntry>>{};
    for (final entry in allEntries) {
      if (consumed.contains(entry.id)) continue;
      if (entry.url.trim().isEmpty) continue;
      final key =
          '${normalizeUrlForCompare(entry.url)}\x00${_normalizeUsername(entry.username)}';
      bySite.putIfAbsent(key, () => []).add(entry);
    }
    for (final mapEntry in bySite.entries) {
      if (mapEntry.value.length < 2) continue;
      final sorted = _sortNewestFirst(mapEntry.value);
      final parts = mapEntry.key.split('\x00');
      result.add(
        DuplicateGroup(
          sharedUrl: parts[0],
          sharedUsername: parts.length > 1 ? parts[1] : '',
          urls: [parts[0]],
          entries: sorted,
        ),
      );
    }

    result.sort((a, b) {
      final bySize = b.entries.length.compareTo(a.entries.length);
      if (bySize != 0) return bySize;
      return (a.sharedUrl ?? a.sharedUsername).compareTo(
        b.sharedUrl ?? b.sharedUsername,
      );
    });

    return result;
  }

  /// Computes which fields would be copied from [secondary] into [primary]
  /// without touching the kdbx file.
  MergePreview previewMerge(VaultEntry primary, VaultEntry secondary) {
    final willCopyNotes =
        primary.notes.trim().isEmpty && secondary.notes.trim().isNotEmpty;

    final willCopyOtp = primary.otpUri == null && secondary.otpUri != null;

    final primaryKeys = primary.customFields
        .map((f) => f.key.toLowerCase())
        .toSet();

    final customFieldKeysToCopy = secondary.customFields
        .where((f) => !_isOtpKey(f.key))
        .where((f) => !isUrlFieldKey(f.key))
        .where((f) => !primaryKeys.contains(f.key.toLowerCase()))
        .map((f) => f.key)
        .toList(growable: false);

    final primaryUrls = _entryUrls(primary).map(normalizeUrlForCompare).toSet();
    final urlsToCopy = <String>[];
    for (final url in _entryUrls(secondary)) {
      if (primaryUrls.add(normalizeUrlForCompare(url))) {
        urlsToCopy.add(url);
      }
    }

    final primaryAttachmentNames = primary.attachments
        .map((a) => a.name)
        .toSet();
    final willCopyAttachments = secondary.attachments.any(
      (a) => !primaryAttachmentNames.contains(a.name),
    );

    return MergePreview(
      primary: primary,
      secondary: secondary,
      willCopyNotes: willCopyNotes,
      willCopyOtp: willCopyOtp,
      customFieldKeysToCopy: customFieldKeysToCopy,
      urlsToCopy: urlsToCopy,
      willCopyAttachments: willCopyAttachments,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<VaultEntry> _sortNewestFirst(List<VaultEntry> entries) {
    return List<VaultEntry>.from(entries)..sort((a, b) {
      final aTime =
          a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime); // newest first
    });
  }

  /// All URLs an entry carries: the primary `url` plus URL-keyed custom
  /// fields, trimmed, empties dropped.
  List<String> _entryUrls(VaultEntry entry) {
    return [
      entry.url,
      for (final field in entry.customFields)
        if (isUrlFieldKey(field.key)) field.value,
    ].map((u) => u.trim()).where((u) => u.isNotEmpty).toList(growable: false);
  }

  List<String> _distinctUrls(List<VaultEntry> entries) {
    final seen = <String>{};
    final urls = <String>[];
    for (final entry in entries) {
      for (final url in _entryUrls(entry)) {
        final normalized = normalizeUrlForCompare(url);
        if (normalized.isEmpty) continue;
        if (seen.add(normalized)) urls.add(normalized);
      }
    }
    return urls;
  }

  String _normalizeUsername(String username) => username.trim().toLowerCase();

  bool _isOtpKey(String key) {
    final k = key.toLowerCase().trim();
    return k == 'otp' || k == 'totp' || k == 'otpauth' || k.contains('otp');
  }
}
