part of '../vault_screen.dart';

// spec-019 T019/T020 — `Manage folders`: one surface, one recipe, every width.
//
// Before this file the folder actions lived on the rows of the records list,
// which is what made the list a folder browser instead of a list of records
// (C-03-03). They move here whole — same actions, same confirmations, same
// strings (FR-006d, Constitution VI). Only the container differs: a centred
// dialog where the folder column lives, a pushed screen on the phone
// (`decisions-folder-management.md`).

/// Flattens the group tree into the rows [KvFolderTree] renders.
///
/// Shared by the desktop folder column, the phone `Folders` sheet and this
/// surface, so the three cannot disagree about order, depth or counts. The
/// recycle bin is never a row here: it is one of the hygiene shortcuts at the
/// foot of the column, not a folder you file things in.
///
/// [forceExpanded] is what `Manage folders` sets: management shows the whole
/// tree, because you cannot move what you cannot see (FR-006b).
List<KvFolderNode> _flattenFolderNodes({
  required List<VaultGroup> groups,
  required String rootGroupId,
  required Map<String, int> counts,
  required Set<String> expandedIds,
  bool forceExpanded = false,
  bool includeRoot = false,
}) {
  final bin = <String>{};
  for (final group in groups) {
    if (group.isRecycleBin) {
      bin.add(group.id);
    }
  }
  // Descendants of the bin are in the bin.
  var grew = true;
  while (grew) {
    grew = false;
    for (final group in groups) {
      final parentId = group.parentId;
      if (parentId != null && bin.contains(parentId) && bin.add(group.id)) {
        grew = true;
      }
    }
  }

  final children = <String, List<VaultGroup>>{};
  for (final group in groups) {
    if (bin.contains(group.id) || group.parentId == null) {
      continue;
    }
    (children[group.parentId!] ??= <VaultGroup>[]).add(group);
  }
  for (final siblings in children.values) {
    siblings.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  final nodes = <KvFolderNode>[];
  void walk(String parentId, int depth) {
    for (final group in children[parentId] ?? const <VaultGroup>[]) {
      final hasChildren = (children[group.id] ?? const []).isNotEmpty;
      final isExpanded = forceExpanded || expandedIds.contains(group.id);
      nodes.add(
        KvFolderNode(
          id: group.id,
          name: group.name,
          count: counts[group.id] ?? 0,
          depth: depth,
          hasChildren: hasChildren,
          isExpanded: isExpanded,
        ),
      );
      // A collapsed node's children are not rows at all, which is what keeps
      // the chevron meaningful rather than decorative.
      if (hasChildren && isExpanded) {
        walk(group.id, depth + 1);
      }
    }
  }

  if (includeRoot) {
    final root = groups.where((group) => group.id == rootGroupId);
    if (root.isNotEmpty) {
      nodes.add(
        KvFolderNode(
          id: rootGroupId,
          name: root.first.name,
          count: counts[rootGroupId] ?? 0,
          depth: 0,
          hasChildren: (children[rootGroupId] ?? const []).isNotEmpty,
          isExpanded: true,
          // The vault's own root: renamable, but there is nowhere to move it
          // to and deleting it would delete the vault's contents.
          canReparent: false,
        ),
      );
    }
  }
  walk(rootGroupId, includeRoot ? 1 : 0);
  return nodes;
}

/// The single entry point (FR-006a). Opened from the folder column's header on
/// desktop and from the head of the phone's `Folders` sheet; the router decides
/// dialog or pushed screen from the same 704 every other surface uses.
// The call site is the folder column's `Manage` button (T023); this file lands
// first so the destination exists before the entry point does.
// ignore: unused_element
Future<void> _showManageFolders(BuildContext context) async {
  // The bloc is captured here and re-provided inside the surface: a dialog and
  // a pushed route both live on the root Navigator, which is a sibling of the
  // vault shell rather than a descendant, so a `read` from inside the surface
  // finds nothing. Every other surface in this feature does the same.
  final bloc = context.read<VaultBloc>();
  await VaultShellRouterScope.of(context).open<VaultDone>(
    context: context,
    surface: ManageFoldersSurface<VaultDone>(
      builder: (surfaceContext) => BlocProvider<VaultBloc>.value(
        value: bloc,
        child: const _ManageFoldersPanel(),
      ),
    ),
  );
}

class _ManageFoldersPanel extends StatelessWidget {
  const _ManageFoldersPanel();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return BlocBuilder<VaultBloc, VaultState>(
      builder: (context, state) {
        final rootGroupId = state.rootGroupId;
        final nodes = rootGroupId == null
            ? const <KvFolderNode>[]
            : _flattenFolderNodes(
                groups: state.groups,
                rootGroupId: rootGroupId,
                counts: state.folderCounts,
                expandedIds: const {},
                forceExpanded: true,
                // The root is a row here so it stays renamable — the records
                // list used to carry that action on its root folder row.
                includeRoot: true,
              );

        return Container(
          color: colors.ground,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Manage folders',
                        style: AppTextStyles.panelTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    KvPillButton(
                      label: 'New folder',
                      icon: AppIcons.folderAdd,
                      expand: false,
                      compact: true,
                      onPressed: () => _createFolderFromManager(context),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () =>
                          VaultOperationScope.of(context).complete(VaultDone()),
                      icon: const KvIcon(glyph: AppGlyph.close, size: 18),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                  child: nodes.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No folders yet.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.secondary.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        )
                      : KvFolderTree(
                          nodes: nodes,
                          selectedId: state.currentGroupId,
                          mode: KvFolderTreeMode.manage,
                          onSelect: (id) =>
                              context.read<VaultBloc>().add(
                                SelectVaultFolder(id),
                              ),
                          onToggleExpanded: (_, _) {},
                          onRowAction: (id, action) => _handleManageFolderAction(
                            context,
                            groups: state.groups,
                            groupId: id,
                            action: action,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _createFolderFromManager(BuildContext context) async {
  final name = await _showGroupDialog(context);
  if (name == null || name.name.trim().isEmpty || !context.mounted) {
    return;
  }
  context.read<VaultBloc>().add(CreateVaultGroup(name.name.trim()));
}

/// Routes the tree's three row actions to the handlers the vault already has,
/// so `Rename`, `Move` and `Delete` keep their existing dialogs, their existing
/// confirmations and their existing strings (FR-006d, Constitution VI and VII).
Future<void> _handleManageFolderAction(
  BuildContext context, {
  required List<VaultGroup> groups,
  required String groupId,
  required KvFolderAction action,
}) async {
  final group = groups.where((candidate) => candidate.id == groupId);
  if (group.isEmpty) {
    return;
  }

  await _handleChildGroupAction(
    context,
    group: group.first,
    action: switch (action) {
      KvFolderAction.rename => _ChildGroupAction.rename,
      KvFolderAction.move => _ChildGroupAction.move,
      KvFolderAction.delete => _ChildGroupAction.delete,
    },
    allGroups: groups,
  );
}
