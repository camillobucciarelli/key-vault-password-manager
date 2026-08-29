import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_glyph.dart';
import '../theme/app_radii.dart';
import '../theme/app_text_styles.dart';
import '../theme/keyvault_colors.dart';
import 'kv_icon.dart';

/// spec-019 T014 — the folder tree, in one widget, for all three of its hosts.
///
/// The desktop folder column, the phone `Folders` sheet and `Manage folders`
/// render the same tree; before this widget they were three separate builders
/// that agreed by hand, and the audit found them disagreeing (C-03-07,
/// C-03-11). Everything host-specific is a flag here, so "one selected-row
/// style, one `•••` recipe" (FR-006k) holds by construction.
///
/// The widget renders [nodes] and reports. It does not fetch, does not know
/// about the BLoC, and does not decide what selection means for the records
/// list (contract `folder-tree.md`, Non-goals).
enum KvFolderTreeMode {
  /// The desktop column and the phone sheet: pick a folder to filter by.
  /// Rows carry no actions at all (G1 / FR-006c).
  filter,

  /// `Manage folders`: every row carries the `•••`, and the tree ignores each
  /// node's `isExpanded` and renders fully expanded — you cannot rearrange
  /// what you cannot see (G2 / FR-006b).
  manage,
}

/// The row actions offered in [KvFolderTreeMode.manage].
///
/// Order is part of the contract (G2) and the labels are the ones the vault
/// already uses (Constitution VI).
enum KvFolderAction { rename, move, delete }

/// One row of the tree: a folder flattened out of the group graph.
@immutable
class KvFolderNode {
  const KvFolderNode({
    required this.id,
    required this.name,
    required this.count,
    required this.depth,
    this.hasChildren = false,
    this.isExpanded = false,
    this.canReparent = true,
  });

  final String id;
  final String name;

  /// Records in this folder **and all its descendants** (FR-006i).
  final int count;

  /// 0 for a top-level folder; drives indentation and nothing else (G5).
  final int depth;

  final bool hasChildren;

  /// Ignored in [KvFolderTreeMode.manage] (G2). The caller flattens only the
  /// rows it wants visible; this flag is what the chevron points at.
  final bool isExpanded;

  /// False for the vault's root group, which has no parent to move to and
  /// cannot be deleted. Its row keeps `Rename` and drops the other two —
  /// offering a user an action that cannot succeed is worse than not offering
  /// it (G2, amended).
  final bool canReparent;
}

class KvFolderTree extends StatelessWidget {
  const KvFolderTree({
    super.key,
    required this.nodes,
    required this.selectedId,
    required this.onSelect,
    required this.onToggleExpanded,
    this.mode = KvFolderTreeMode.filter,
    this.onRowAction,
  }) : assert(
         mode == KvFolderTreeMode.manage || onRowAction == null,
         'onRowAction belongs to manage mode; filter rows carry no actions '
         '(G1)',
       );

  final List<KvFolderNode> nodes;

  /// The selected group id. `All items` is the root group's id, never null
  /// (FR-002a) — see `VaultBloc._onSelectVaultFolder`.
  final String? selectedId;

  final ValueChanged<String> onSelect;

  /// Called by the chevron only, never by the row (G3).
  final void Function(String id, bool expanded) onToggleExpanded;

  final KvFolderTreeMode mode;

  final void Function(String id, KvFolderAction action)? onRowAction;

  /// One level of indentation per depth (G5). Wide enough that the chevron of
  /// a child clears the label of its parent.
  static const double indentPerDepth = 18;

  /// Constitution V: both the chevron and the row are ≥ 44 × 44, and they do
  /// not overlap (G7) — the chevron is laid out beside the row's tap target,
  /// not on top of it.
  static const double minTarget = 44;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final node in nodes)
          _KvFolderRow(
            node: node,
            isSelected: node.id == selectedId,
            mode: mode,
            onSelect: () => onSelect(node.id),
            onToggleExpanded: () =>
                onToggleExpanded(node.id, !node.isExpanded),
            onAction: onRowAction == null
                ? null
                : (action) => onRowAction!(node.id, action),
          ),
      ],
    );
  }
}

class _KvFolderRow extends StatelessWidget {
  const _KvFolderRow({
    required this.node,
    required this.isSelected,
    required this.mode,
    required this.onSelect,
    required this.onToggleExpanded,
    required this.onAction,
  });

  final KvFolderNode node;
  final bool isSelected;
  final KvFolderTreeMode mode;
  final VoidCallback onSelect;
  final VoidCallback onToggleExpanded;
  final ValueChanged<KvFolderAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    // G2: management shows the whole tree, so a chevron there would offer to
    // collapse something the mode has already decided stays open.
    final isManaging = mode == KvFolderTreeMode.manage;
    final showsChevron = node.hasChildren && !isManaging;

    final label = Text(
      node.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.rowTitle.copyWith(
        // G6: one selected style at every host — accent-200 fill, accent-800
        // semibold text, an inline folder glyph, no square icon tile.
        color: isSelected ? AppColors.accent800 : colors.textPrimary,
        fontWeight: isSelected ? FontWeight.w600 : null,
      ),
    );

    final row = Container(
      constraints: const BoxConstraints(minHeight: KvFolderTree.minTarget),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.accent200 : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.rowCompact),
      ),
      child: Row(
        children: [
          KvIcon(
            glyph: AppGlyph.folder,
            size: 17,
            color: isSelected ? AppColors.accent800 : colors.iconNeutral,
          ),
          const SizedBox(width: 8),
          Expanded(child: label),
          const SizedBox(width: 8),
          Text(
            '${node.count}',
            style: AppTextStyles.meta.copyWith(
              color: isSelected ? AppColors.accent800 : colors.textTertiary,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: node.depth * KvFolderTree.indentPerDepth,
        bottom: 2,
      ),
      child: Row(
        children: [
          // The chevron sits beside the row, never over it: two targets that
          // overlap are one target that sometimes does the wrong thing (R5).
          SizedBox(
            width: KvFolderTree.minTarget,
            height: KvFolderTree.minTarget,
            child: showsChevron
                ? IconButton(
                    onPressed: onToggleExpanded,
                    padding: EdgeInsets.zero,
                    tooltip: node.isExpanded
                        ? 'Collapse ${node.name}'
                        : 'Expand ${node.name}',
                    icon: KvIcon(
                      glyph: node.isExpanded
                          ? AppGlyph.chevronDown
                          : AppGlyph.chevronRight,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Semantics(
              // G8: the selection is announced, not only painted. Colour alone
              // is not a signal (Constitution V).
              selected: isSelected,
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSelect,
                  borderRadius: BorderRadius.circular(AppRadii.rowCompact),
                  child: row,
                ),
              ),
            ),
          ),
          if (isManaging && onAction != null)
            SizedBox(
              width: KvFolderTree.minTarget,
              height: KvFolderTree.minTarget,
              child: PopupMenuButton<KvFolderAction>(
                tooltip: 'Folder actions',
                onSelected: onAction,
                icon: KvIcon(
                  glyph: AppGlyph.more,
                  size: 17,
                  color: colors.iconNeutral,
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: KvFolderAction.rename,
                    child: Text('Rename'),
                  ),
                  if (node.canReparent) ...[
                    const PopupMenuItem(
                      value: KvFolderAction.move,
                      child: Text('Move'),
                    ),
                    PopupMenuItem(
                      value: KvFolderAction.delete,
                      child: Text(
                        'Delete',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
