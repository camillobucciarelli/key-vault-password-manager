import '../../domain/models/duplicate_group.dart';
import '../../domain/models/merge_preview.dart';
import '../../domain/models/vault_entry.dart';
import '../../domain/models/vault_passkey.dart';
import '../../domain/services/url_field_keys.dart';

class VaultDuplicateService {
  /// Finds duplicate entries in two passes:
  ///
  /// 1. **Credentials groups** — same username + password (both non-empty),
  ///    regardless of URL. These merge into one record carrying all URLs.
  /// 2. **Site groups** — remaining entries with the same normalized URL +
  ///    username (the pre-multi-URL behavior; catches stale-password copies).
  ///    A bucket holding exactly one passkey, on an entry with no password,
  ///    becomes a `passkeyPassword` group instead (spec 023 D10 / FR-011a);
  ///    a bucket holding two or more passkeys drops them, because two
  ///    credentials for one site are not copies of each other.
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
          kind: DuplicateGroupKind.credentials,
        ),
      );
    }

    // Pass 2 — same normalized URL + username among the rest. One bucket,
    // three outcomes, because a passkey is an identity rather than a copy of a
    // password (spec 023 D10):
    //
    //  * no passkey in the bucket, or the passkey holder also holds a
    //    password — an ordinary site group, exactly as before;
    //  * two or more passkeys — the holders are dropped from the group. Two
    //    entries that each hold a credential for one site are not copies of
    //    each other, and merging them would have to pick one (FR-008). What
    //    is left may still be a site group on its own;
    //  * exactly one passkey, on an entry with no password — the FR-011a
    //    pairing: that entry plus every entry here that does hold a password.
    final bySite = <String, List<VaultEntry>>{};
    for (final entry in allEntries) {
      if (consumed.contains(entry.id)) continue;
      if (entry.url.trim().isEmpty) continue;
      bySite.putIfAbsent(_siteKey(entry), () => []).add(entry);
    }
    for (final mapEntry in bySite.entries) {
      final bucket = mapEntry.value;
      if (bucket.length < 2) continue;
      final holders = bucket
          .where((entry) => entry.hasPasskey)
          .toList(growable: false);
      final withoutPasskeys = bucket
          .where((entry) => !entry.hasPasskey)
          .toList(growable: false);

      List<VaultEntry> members;
      DuplicateGroupKind kind;
      var passkeyHolderLast = false;
      if (holders.length == 1 && holders.single.password.trim().isEmpty) {
        final partners = withoutPasskeys
            .where((entry) => entry.password.trim().isNotEmpty)
            .toList(growable: false);
        if (partners.isNotEmpty) {
          members = [holders.single, ...partners];
          kind = DuplicateGroupKind.passkeyPassword;
          // The kept entry is the first one, and a merge never copies a
          // password (the kept record keeps its own). Keeping the passkey-only
          // entry would therefore produce a record with a passkey and no
          // password — the opposite of FR-011a's "one entry holding both". So
          // the passkey holder is placed last, whatever its timestamps say,
          // and the passkey moves into the entry that holds the password.
          passkeyHolderLast = true;
        } else {
          // Nothing to pair the passkey with: fall back to whatever ordinary
          // duplicates are left here.
          members = withoutPasskeys;
          kind = DuplicateGroupKind.site;
        }
      } else if (holders.length > 1) {
        members = withoutPasskeys;
        kind = DuplicateGroupKind.site;
      } else {
        members = bucket;
        kind = DuplicateGroupKind.site;
      }
      if (members.length < 2) continue;

      final sorted = passkeyHolderLast
          ? [
              ..._sortNewestFirst(
                members.where((entry) => !entry.hasPasskey).toList(),
              ),
              ...members.where((entry) => entry.hasPasskey),
            ]
          : _sortNewestFirst(members);
      for (final entry in sorted) {
        consumed.add(entry.id);
      }
      final parts = mapEntry.key.split('\x00');
      result.add(
        DuplicateGroup(
          sharedUrl: parts[0],
          sharedUsername: parts.length > 1 ? parts[1] : '',
          urls: [parts[0]],
          entries: sorted,
          kind: kind,
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

    // spec 023 D10 — a passkey moves as one credential. An identity the
    // primary already holds is never overwritten: that is the FR-011a
    // conflict, and it makes the merge refuse instead of choosing.
    final primaryPasskeyIdentities = primary.passkeys
        .map(_passkeyIdentity)
        .toSet();
    final passkeysToCopy = <VaultPasskey>[];
    var passkeyConflict = false;
    for (final passkey in secondary.passkeys) {
      if (primaryPasskeyIdentities.contains(_passkeyIdentity(passkey))) {
        passkeyConflict = true;
        continue;
      }
      passkeysToCopy.add(passkey);
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
      passkeysToCopy: passkeysToCopy,
      passkeyConflict: passkeyConflict,
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

  /// What makes two passkeys the same credential slot for merge purposes:
  /// the relying party plus the user handle it was issued for. The credential
  /// id is deliberately not part of it — a site that re-registers the same
  /// account issues a new credential id, and holding both would leave the
  /// entry advertising a credential the site has already replaced.
  String _passkeyIdentity(VaultPasskey passkey) {
    final handle = passkey.userHandle;
    final handleKey = handle == null || handle.isEmpty ? '' : handle.join(',');
    return '${passkey.relyingPartyId.trim().toLowerCase()}\x00$handleKey';
  }

  String _siteKey(VaultEntry entry) =>
      '${normalizeUrlForCompare(entry.url)}\x00'
      '${_normalizeUsername(entry.username)}';

  String _normalizeUsername(String username) => username.trim().toLowerCase();

  bool _isOtpKey(String key) {
    final k = key.toLowerCase().trim();
    return k == 'otp' || k == 'totp' || k == 'otpauth' || k.contains('otp');
  }
}
