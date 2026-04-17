import 'package:equatable/equatable.dart';

import 'vault_entry.dart';

class DuplicateGroup extends Equatable {
  const DuplicateGroup({
    required this.sharedUrl,
    required this.sharedUsername,
    required this.entries,
  });

  /// Human-readable normalized URL shared by all entries in this group.
  final String sharedUrl;

  /// Normalized (lowercased, trimmed) username shared by all entries.
  final String sharedUsername;

  /// 2+ entries with the same sharedUrl + sharedUsername, newest first.
  final List<VaultEntry> entries;

  @override
  List<Object?> get props => [sharedUrl, sharedUsername, entries];
}
