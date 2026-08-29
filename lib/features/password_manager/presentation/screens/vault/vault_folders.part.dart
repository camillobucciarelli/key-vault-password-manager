part of '../vault_screen.dart';

// spec-019 T022-T024 — the desktop folder column, the phone chip row and the
// phone `Folders` sheet: the three hosts of one tree.
//
// What used to stand here was a `ListView` of raw `ListTile`s under a literal
// `Folders` title, flat, uncounted and unstyled (C-03-07, C-03-11), while the
// real folder navigation was mixed into the records list. The column is now
// the folder surface, and the list is a list of records.

/// The vault's own root, shown first and selected by default.
///
/// It is not a pseudo-folder with a null id: it IS the root group, so
/// `CreateVaultEntry` has a group to file into and the count it shows is the
/// root's own inclusive count (FR-002a, FR-002).
const _kAllItemsLabel = 'All items';

/// spec-019 FR-001/FR-002/FR-003/FR-004/FR-006a — the folder column.
class _VaultFolderColumn extends StatelessWidget {
  const _VaultFolderColumn({
    required this.onOpenRecycleBin,
    required this.onOpenDuplicates,
    required this.onChangeDatabase,
  });

  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenDuplicates;
  final Future<void> Function() onChangeDatabase;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: (previous, current) =>
          _folderSurfaceBuildWhen(previous, current) ||
          _databaseActionsBuildWhen(previous, current),
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // FR-001: the column is titled with the database the
                      // user opened, not with the word "Folders" — which told
                      // them something they could already see.
                      path.basename(state.databasePath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.panelTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  // FR-015: the database-level actions live beside the
                  // database's own name. Below 941 this column is gone and the
                  // list header carries them instead — never both.
                  _VaultDatabaseActions(
                    state: state,
                    onOpenRecycleBin: onOpenRecycleBin,
                    onOpenDuplicates: onOpenDuplicates,
                    onChangeDatabase: onChangeDatabase,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // FR-006a: exactly one entry point to folder management per
                  // width, and it lives in the folder surface's header.
                  TextButton(
                    onPressed: () => _showManageFolders(context),
                    child: const Text('Manage'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _VaultFolderTreeSection(state: state),
              ),
            ),
            const _VaultVerticalSpacer(),
            _VaultHygieneShortcuts(state: state),
          ],
        );
      },
    );
  }
}

class _VaultVerticalSpacer extends StatelessWidget {
  const _VaultVerticalSpacer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Divider(
      height: 17,
      thickness: 1,
      color: Theme.of(context).extension<KeyVaultColors>()!.divider,
    ),
  );
}

/// `All items` plus the tree, in one [KvFolderTree] so the first row obeys the
/// same selected-row recipe as every other (FR-006k).
class _VaultFolderTreeSection extends StatelessWidget {
  const _VaultFolderTreeSection({required this.state, this.forSheet = false});

  final VaultState state;

  /// The phone sheet closes itself once a folder is chosen (FR-005a); the
  /// column stays put.
  final bool forSheet;

  @override
  Widget build(BuildContext context) {
    final rootGroupId = state.rootGroupId;
    if (rootGroupId == null) {
      return const SizedBox.shrink();
    }

    final nodes = <KvFolderNode>[
      KvFolderNode(
        id: rootGroupId,
        name: _kAllItemsLabel,
        count: state.totalCount,
        depth: 0,
      ),
      ..._flattenFolderNodes(
        groups: state.groups,
        rootGroupId: rootGroupId,
        counts: state.folderCounts,
        expandedIds: state.expandedGroupIds.toSet(),
      ),
    ];

    return KvFolderTree(
      nodes: nodes,
      // FR-002a: never null. An unknown or deleted folder falls back to the
      // root, which is `All items`.
      selectedId: state.currentGroupId ?? rootGroupId,
      onSelect: (id) {
        context.read<VaultBloc>().add(SelectVaultFolder(id));
        if (forSheet) {
          Navigator.of(context).maybePop();
        }
      },
      onToggleExpanded: (id, expanded) => context.read<VaultBloc>().add(
        SetVaultFolderExpanded(id, expanded: expanded),
      ),
    );
  }
}

/// FR-004 — the two hygiene shortcuts, at the foot of the column where the
/// design puts them, carrying the counts the state already holds.
class _VaultHygieneShortcuts extends StatelessWidget {
  const _VaultHygieneShortcuts({required this.state});

  final VaultState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    Widget shortcut({
      required String label,
      required AppGlyph glyph,
      required int count,
      required VoidCallback onTap,
    }) {
      return Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.rowCompact),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  KvIcon(glyph: glyph, size: 17, color: colors.iconNeutral),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.rowTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: AppTextStyles.meta.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          shortcut(
            label: 'Recycle bin',
            glyph: AppGlyph.delete,
            count: state.recycleBinEntries.length,
            onTap: () => unawaited(_showRecycleBinDialog(context)),
          ),
          shortcut(
            label: 'Duplicates',
            glyph: AppGlyph.duplicates,
            count: state.duplicateGroups.length,
            onTap: () => unawaited(_showDuplicatesDialog(context)),
          ),
        ],
      ),
    );
  }
}

bool _folderSurfaceBuildWhen(VaultState previous, VaultState current) {
  return previous.groups != current.groups ||
      previous.currentGroupId != current.currentGroupId ||
      previous.expandedGroupIds != current.expandedGroupIds ||
      previous.folderCounts != current.folderCounts ||
      previous.databasePath != current.databasePath ||
      previous.recycleBinEntries != current.recycleBinEntries ||
      previous.duplicateGroups != current.duplicateGroups;
}

/// spec-019 T036 / FR-005 — the phone's folder chips.
///
/// First level only. A vault three folders deep must not produce a chip row
/// three folders long: the deep ones are reached through the `Folders` sheet,
/// which is what the first chip opens. Chips filter and nothing else — no chip
/// carries an action (FR-006c).
class _VaultFolderChipRow extends StatelessWidget {
  const _VaultFolderChipRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: _folderSurfaceBuildWhen,
      builder: (context, state) {
        final rootGroupId = state.rootGroupId;
        if (rootGroupId == null) {
          return const SizedBox.shrink();
        }

        final firstLevel =
            state.groups
                .where(
                  (group) =>
                      group.parentId == rootGroupId && !group.isRecycleBin,
                )
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

        final selectedId = state.currentGroupId ?? rootGroupId;
        // A folder selected from the sheet may be nested; the chip row then
        // shows no chip as active, and the `Folders` chip carries the name so
        // the filter is never invisible (FR-005a).
        final isDeepSelection =
            selectedId != rootGroupId &&
            !firstLevel.any((group) => group.id == selectedId);
        final deepName = isDeepSelection
            ? state.groups
                  .where((group) => group.id == selectedId)
                  .map((group) => group.name)
                  .firstOrNull
            : null;

        return SizedBox(
          key: const ValueKey('vault-folder-chips'),
          height: KvFilterChip.minTarget,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              KvFilterChip(
                label: deepName == null ? 'Folders' : 'Folders · $deepName',
                selected: isDeepSelection,
                onPressed: () => unawaited(_showFoldersSheet(context)),
              ),
              const SizedBox(width: 8),
              KvFilterChip(
                label: 'All',
                count: state.totalCount,
                selected: selectedId == rootGroupId,
                onPressed: () =>
                    context.read<VaultBloc>().add(
                      SelectVaultFolder(rootGroupId),
                    ),
              ),
              for (final group in firstLevel) ...[
                const SizedBox(width: 8),
                KvFilterChip(
                  label: group.name,
                  count: state.folderCounts[group.id] ?? 0,
                  selected: selectedId == group.id,
                  onPressed: () => context.read<VaultBloc>().add(
                    SelectVaultFolder(group.id),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// spec-019 T037 / FR-005a — the phone's `Folders` sheet.
///
/// The same tree as the desktop column, reading and writing the same expansion
/// state, with the same single entry point to folder management at its head
/// (FR-006a). Choosing a folder filters, closes, and becomes the active chip.
Future<void> _showFoldersSheet(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  final openManage = await KvBottomSheet.show<bool>(
    context: context,
    builder: (sheetContext) => BlocProvider<VaultBloc>.value(
      value: bloc,
      child: const _VaultFoldersSheet(),
    ),
  );
  // `Manage` is opened from HERE, after the sheet has closed, and not from
  // inside it: the sheet's own context is being unmounted at that moment, and
  // the router scope it would need is above this one, not above the sheet.
  if (openManage == true && context.mounted) {
    await _showManageFolders(context);
  }
}

class _VaultFoldersSheet extends StatelessWidget {
  const _VaultFoldersSheet();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: _folderSurfaceBuildWhen,
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Folders',
                        style: AppTextStyles.sheetTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Manage'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: _VaultFolderTreeSection(state: state, forSheet: true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// spec-019 T038 / FR-009a, FR-014a, FR-014b — the phone `Sort` sheet.
///
/// One radio group over the three orders the vault already has, dispatching
/// the same `SetVaultSort` as the desktop control. Applying is immediate and
/// dismisses. Nothing else belongs here: the folder filter is the chip row,
/// there is one search and it already covers every field, and a health filter
/// would be a new capability (FR-020).
Future<void> _showSortSheet(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  await KvBottomSheet.show<void>(
    context: context,
    builder: (sheetContext) => BlocProvider<VaultBloc>.value(
      value: bloc,
      child: const _VaultSortSheet(),
    ),
  );
}

class _VaultSortSheet extends StatelessWidget {
  const _VaultSortSheet();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return BlocSelector<VaultBloc, VaultState, VaultEntrySort>(
      selector: (state) => state.sortBy,
      builder: (context, sortBy) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text(
                  'Sort',
                  style: AppTextStyles.sheetTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              RadioGroup<VaultEntrySort>(
                groupValue: sortBy,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  context.read<VaultBloc>().add(SetVaultSort(value));
                  Navigator.of(context).pop();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in VaultEntrySort.values)
                      RadioListTile<VaultEntrySort>(
                        value: option,
                        title: Text(vaultSortLabel(option)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
