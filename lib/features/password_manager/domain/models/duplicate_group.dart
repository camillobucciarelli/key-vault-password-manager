import 'package:equatable/equatable.dart';

import 'vault_entry.dart';

class DuplicateGroup extends Equatable {
  const DuplicateGroup({
    this.sharedUrl,
    required this.sharedUsername,
    this.urls = const [],
    required this.entries,
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

  @override
  List<Object?> get props => [sharedUrl, sharedUsername, urls, entries];
}
