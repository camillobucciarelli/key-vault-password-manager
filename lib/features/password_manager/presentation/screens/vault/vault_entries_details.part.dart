part of '../vault_screen.dart';

// spec-004: the entry-detail screen/pane itself moved to
// vault_entry_detail.part.dart (_EntryDetailsPage, _EntryDetailPanel and
// their supporting widgets). This file keeps the list-row ↔ detail "glue":
// folder/record list rows, the empty states, and the background lock
// overlays — none of which are in spec-004's scope.

class _FolderListItem extends StatelessWidget {
  const _FolderListItem({
    required this.group,
    required this.isExpanded,
    required this.isCurrent,
    required this.isRoot,
    required this.childGroupsCount,
    required this.recordsCount,
    required this.onOpen,
    required this.onToggleExpand,
    required this.onSelectedAction,
  });

  final VaultGroup group;
  final bool isExpanded;
  final bool isCurrent;
  final bool isRoot;
  final int childGroupsCount;
  final int recordsCount;
  final VoidCallback onOpen;
  final VoidCallback onToggleExpand;
  final ValueChanged<_FolderAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final itemAnimationDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : _VaultUiTokens.itemTransitionDuration;
    final hasChildren = childGroupsCount > 0;
    final caretIcon = isExpanded ? AppIcons.chevronDown : AppIcons.chevronRight;

    return _InteractiveItemSurface(
      radius: _VaultUiTokens.recordItemRadius,
      minHeight: _VaultUiTokens.recordItemHeight,
      onTap: onOpen,
      baseColor: isCurrent
          ? colorScheme.primaryContainer.withValues(alpha: 0.62)
          : colorScheme.surface.withValues(alpha: 0.74),
      hoveredColor: isCurrent
          ? colorScheme.primaryContainer.withValues(alpha: 0.72)
          : colorScheme.surface.withValues(alpha: 0.85),
      baseBorderColor: isCurrent
          ? colorScheme.primary.withValues(alpha: 0.62)
          : colorScheme.outlineVariant.withValues(alpha: 0.7),
      hoveredBorderColor: colorScheme.primary.withValues(alpha: 0.42),
      child: Padding(
        padding: const EdgeInsets.only(left: 6, right: 6, top: 8, bottom: 8),
        child: Row(
          children: [
            AnimatedContainer(
              duration: itemAnimationDuration,
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                color: isCurrent
                    ? colorScheme.primary.withValues(alpha: 0.92)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: isExpanded ? 'Collapse folder' : 'Expand folder',
              ignorePointer: true,
              child: IconButton(
                onPressed: hasChildren ? onToggleExpand : null,
                icon: Icon(caretIcon, size: 16),
              ),
            ),
            Container(
              width: _VaultUiTokens.folderIconContainerSize,
              height: _VaultUiTokens.folderIconContainerSize,
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.54),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isExpanded ? AppIcons.folderOpen : AppIcons.folder,
                size: 18,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isCurrent
                                    ? colorScheme.onPrimaryContainer
                                    : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$childGroupsCount folders • $recordsCount records',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isCurrent
                          ? colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            if (isRoot) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.36),
                  ),
                ),
                child: Text(
                  'ROOT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
            PopupMenuButton<_FolderAction>(
              // Native `tooltip` param instead of an outer Tooltip wrapper:
              // double-nesting Tooltip widgets around the same hit-test
              // region triggers a Flutter framework ticker-reuse crash
              // under widget-test pointer synthesis (observed while adding
              // spec-004's entry-detail golden tests).
              tooltip: 'Folder actions',
              onSelected: onSelectedAction,
              itemBuilder: (context) => [
                const _RoundedPopupItem(
                  value: _FolderAction.addRecord,
                  child: _MenuItemContent(
                    icon: AppIcons.cardAdd,
                    label: 'Add record',
                  ),
                ),
                const _RoundedPopupItem(
                  value: _FolderAction.addSubfolder,
                  child: _MenuItemContent(
                    icon: AppIcons.folderAdd,
                    label: 'Add subfolder',
                  ),
                ),
                const PopupMenuDivider(),
                const _RoundedPopupItem(
                  value: _FolderAction.rename,
                  child: _MenuItemContent(icon: AppIcons.edit, label: 'Rename'),
                ),
                if (!isRoot) ...[
                  const _RoundedPopupItem(
                    value: _FolderAction.move,
                    child: _MenuItemContent(icon: AppIcons.move, label: 'Move'),
                  ),
                  const _RoundedPopupItem(
                    value: _FolderAction.delete,
                    child: _MenuItemContent(
                      icon: AppIcons.delete,
                      label: 'Delete',
                      isDestructive: true,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordListItem extends StatelessWidget {
  const _RecordListItem({
    required this.entry,
    required this.onOpen,
    required this.onSelectedAction,
    this.isSelected = false,
  });

  final VaultEntry entry;
  final VoidCallback onOpen;
  final ValueChanged<_EntryAction> onSelectedAction;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final isPasswordWarning = _isPasswordUpdateOverdue(entry, DateTime.now());

    // spec-018 FR-004/FR-016: the accent-200 fill and accent-400 border below
    // already carried the design's selected treatment — the defect was that
    // `isSelected` was only ever true inside the records card's own inline
    // split, so in the real three-column layout no row was ever marked (D3).
    // Colour alone is not a signal (Constitution V), so the selected state is
    // also published to semantics: a screen reader announces the row as
    // selected, and it is what the a11y test asserts rather than a pixel.
    return Semantics(
      selected: isSelected,
      child: _InteractiveItemSurface(
        radius: AppRadii.row,
        minHeight: 62,
        onTap: onOpen,
        baseColor: isSelected ? AppColors.accent200 : colors.surface,
        hoveredColor: isSelected ? AppColors.accent200 : colors.surface,
        baseBorderColor: isSelected ? AppColors.accent400 : Colors.transparent,
        hoveredBorderColor: colors.selectionBorder.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              KvLetterAvatar(
                letter: entry.title,
                size: 38,
                selected: isSelected,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title.isEmpty ? '(Untitled)' : entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.rowTitle.copyWith(
                        color: isSelected
                            ? AppColors.accent900
                            : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.username.isEmpty
                          ? (entry.url.isEmpty ? 'No username' : entry.url)
                          : entry.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.secondary.copyWith(
                        color: isSelected
                            ? AppColors.accent900
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              KvHealthDot(
                state: isPasswordWarning
                    ? KvHealthState.warning
                    : KvHealthState.good,
                semanticsLabel: isPasswordWarning
                    ? 'Password needs attention'
                    : 'Password healthy',
              ),
              const SizedBox(width: 6),
              PopupMenuButton<_EntryAction>(
                tooltip: 'Record actions',
                onSelected: onSelectedAction,
                itemBuilder: (context) => const [
                  _RoundedPopupItem(
                    value: _EntryAction.edit,
                    child: _MenuItemContent(icon: AppIcons.edit, label: 'Edit'),
                  ),
                  _RoundedPopupItem(
                    value: _EntryAction.move,
                    child: _MenuItemContent(icon: AppIcons.move, label: 'Move'),
                  ),
                  _RoundedPopupItem(
                    value: _EntryAction.attachments,
                    child: _MenuItemContent(
                      icon: AppIcons.attachment,
                      label: 'Attachments',
                    ),
                  ),
                  _RoundedPopupItem(
                    value: _EntryAction.delete,
                    child: _MenuItemContent(
                      icon: AppIcons.delete,
                      label: 'Delete',
                      isDestructive: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isPasswordUpdateOverdue(VaultEntry entry, DateTime now) {
  final reference = entry.lastPasswordChangedAt ?? entry.updatedAt;
  if (reference == null) {
    return false;
  }

  final cutoff = DateTime(
    now.year,
    now.month - 3,
    now.day,
    now.hour,
    now.minute,
    now.second,
    now.millisecond,
    now.microsecond,
  );

  return reference.isBefore(cutoff);
}

// spec-006 T4/T5: `_LockOverlay` / `_PrivacyOverlay` moved to
// `vault_lock_overlay.part.dart` (their own file per plan.md), restyled to
// FR-3 — dark ground, app mark, "locked for <duration>" copy, and a
// zero-`Text`-widget privacy overlay (AC3).

class _MenuItemContent extends StatelessWidget {
  const _MenuItemContent({
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isDestructive ? colorScheme.error : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Text(label, style: color != null ? TextStyle(color: color) : null),
      ],
    );
  }
}

/// [PopupMenuItem] with rounded hover/splash ink instead of a full-width
/// rectangle. Replaces the default [InkWell] with one that has [borderRadius].
class _RoundedPopupItem<T> extends PopupMenuItem<T> {
  const _RoundedPopupItem({
    super.key,
    super.value,
    super.enabled,
    required super.child,
  }) : super(padding: EdgeInsets.zero);

  @override
  PopupMenuItemState<T, PopupMenuItem<T>> createState() =>
      _RoundedPopupItemState<T>();
}

class _RoundedPopupItemState<T>
    extends PopupMenuItemState<T, _RoundedPopupItem<T>> {
  static const _kRadius = 10.0;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        enabled: widget.enabled,
        button: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(_kRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(_kRadius),
              onTap: widget.enabled ? handleTap : null,
              canRequestFocus: widget.enabled,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: buildChild(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordsEmptyState extends StatelessWidget {
  const _RecordsEmptyState({required this.searchQuery, this.onClearSearch});

  final String searchQuery;
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSearchActive = searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSearchActive ? AppIcons.searchOff : AppIcons.key,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isSearchActive ? 'No records or folders found' : 'No records yet',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            isSearchActive
                ? 'Try a different keyword or clear the search.'
                : 'Use the folder menu to add records or subfolders.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (isSearchActive && onClearSearch != null)
            OutlinedButton.icon(
              onPressed: onClearSearch,
              style: OutlinedButton.styleFrom(
                animationDuration: _VaultUiTokens.buttonTransitionDuration,
              ),
              icon: const Icon(AppIcons.close),
              label: const Text('Clear search'),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Fallback shown in the tablet detail pane when no entry is selected yet.
class _EntryDetailEmptyState extends StatelessWidget {
  const _EntryDetailEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KvIcon(glyph: AppGlyph.key, size: 46, color: colors.iconNeutral),
          const SizedBox(height: 12),
          Text(
            'No item selected',
            style: AppTextStyles.panelTitleLarge.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a record from the list to view all details and copy fields.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
