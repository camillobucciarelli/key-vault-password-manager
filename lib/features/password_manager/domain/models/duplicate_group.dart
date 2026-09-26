import 'package:equatable/equatable.dart';

import 'vault_entry.dart';

/// Why [VaultDuplicateService] considers a group's entries the same account.
///
/// The kind decides what Vault health may offer: [credentials] and [site] are
/// copies of one login, while [passkeyPassword] is the spec 023 FR-011a case
/// where one entry holds the passkey and another holds the password for the
/// same account, and merging them makes one complete record.
enum DuplicateGroupKind {
  /// Same username and password, whatever the site (pass 1).
  credentials,

  /// Same normalized site and username (pass 2).
  site,

  /// Same normalized site and username, where exactly one entry holds a
  /// passkey and carries no password (pass 3, spec 023 D10).
  passkeyPassword,
}

class DuplicateGroup extends Equatable {
  const DuplicateGroup({
    this.sharedUrl,
    required this.sharedUsername,
    this.urls = const [],
    required this.entries,
    required this.kind,
  });

  /// Human-readable normalized URL shared by all entries in this group, or
  /// null for a credentials group (same username + password across sites).
  final String? sharedUrl;

  /// Normalized (lowercased, trimmed) username shared by all entries.
  final String sharedUsername;

  /// Distinct normalized URLs across the group's entries (display order).
  final List<String> urls;

  /// 2+ duplicate entries, newest first.
  final List<VaultEntry> entries;

  /// What makes these entries the same account.
  final DuplicateGroupKind kind;

  /// The entry holding the passkey in a [DuplicateGroupKind.passkeyPassword]
  /// group — by construction there is exactly one. `null` for every other
  /// kind, even when a member happens to hold a passkey.
  VaultEntry? get passkeyHolder => kind == DuplicateGroupKind.passkeyPassword
      ? entries.firstWhere((entry) => entry.hasPasskey)
      : null;

  @override
  List<Object?> get props => [sharedUrl, sharedUsername, urls, entries, kind];
}
