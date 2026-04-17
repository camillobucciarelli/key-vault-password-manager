import '../../domain/models/duplicate_group.dart';
import '../../domain/models/merge_preview.dart';
import '../../domain/models/vault_entry.dart';

class VaultDuplicateService {
  /// Groups [allEntries] by normalized URL + username.
  /// Returns only groups with 2+ entries, sorted by size desc then URL asc.
  /// Entries inside each group are sorted newest first (updatedAt, then createdAt).
  /// Entries with an empty URL are excluded.
  List<DuplicateGroup> findDuplicates(List<VaultEntry> allEntries) {
    final accumulator = <String, List<VaultEntry>>{};

    for (final entry in allEntries) {
      if (entry.url.trim().isEmpty) continue;
      final key =
          '${_normalizeUrl(entry.url)}\x00${_normalizeUsername(entry.username)}';
      accumulator.putIfAbsent(key, () => []).add(entry);
    }

    final result = <DuplicateGroup>[];
    for (final mapEntry in accumulator.entries) {
      if (mapEntry.value.length < 2) continue;

      final sorted = List<VaultEntry>.from(mapEntry.value)
        ..sort((a, b) {
          final aTime =
              a.updatedAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime =
              b.updatedAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime); // newest first
        });

      final parts = mapEntry.key.split('\x00');
      result.add(
        DuplicateGroup(
          sharedUrl: parts[0],
          sharedUsername: parts.length > 1 ? parts[1] : '',
          entries: sorted,
        ),
      );
    }

    result.sort((a, b) {
      final bySize = b.entries.length.compareTo(a.entries.length);
      if (bySize != 0) return bySize;
      return a.sharedUrl.compareTo(b.sharedUrl);
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
        .where((f) => !primaryKeys.contains(f.key.toLowerCase()))
        .map((f) => f.key)
        .toList(growable: false);

    final primaryAttachmentNames =
        primary.attachments.map((a) => a.name).toSet();
    final willCopyAttachments =
        secondary.attachments.any((a) => !primaryAttachmentNames.contains(a.name));

    return MergePreview(
      primary: primary,
      secondary: secondary,
      willCopyNotes: willCopyNotes,
      willCopyOtp: willCopyOtp,
      customFieldKeysToCopy: customFieldKeysToCopy,
      willCopyAttachments: willCopyAttachments,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _normalizeUrl(String url) {
    var result = url.toLowerCase();
    result = result.replaceFirst(RegExp(r'^https?://'), '');
    result = result.replaceFirst(RegExp(r'^ftp://'), '');
    result = result.replaceFirst(RegExp(r'^www\.'), '');
    if (result.endsWith('/')) result = result.substring(0, result.length - 1);
    final queryIdx = result.indexOf('?');
    if (queryIdx >= 0) result = result.substring(0, queryIdx);
    final fragmentIdx = result.indexOf('#');
    if (fragmentIdx >= 0) result = result.substring(0, fragmentIdx);
    return result;
  }

  String _normalizeUsername(String username) => username.trim().toLowerCase();

  bool _isOtpKey(String key) {
    final k = key.toLowerCase().trim();
    return k == 'otp' || k == 'totp' || k == 'otpauth' || k.contains('otp');
  }
}
