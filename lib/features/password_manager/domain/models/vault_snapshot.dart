import 'vault_entry.dart';
import 'vault_group.dart';

class VaultSnapshot {
  const VaultSnapshot({
    required this.rootGroupId,
    required this.currentGroupId,
    required this.groups,
    required this.entries,
  });

  final String rootGroupId;
  final String currentGroupId;
  final List<VaultGroup> groups;
  final List<VaultEntry> entries;
}
