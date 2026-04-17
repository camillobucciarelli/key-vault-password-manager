part of '../vault_screen.dart';

Future<void> _showDuplicatesDialog(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  bloc.add(const LoadDuplicates());

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return BlocProvider.value(value: bloc, child: const _DuplicatesDialog());
    },
  );
}

class _DuplicatesDialog extends StatelessWidget {
  const _DuplicatesDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Manage duplicates')),
          BlocBuilder<VaultBloc, VaultState>(
            buildWhen: (p, n) => p.duplicateGroupCount != n.duplicateGroupCount,
            builder: (context, state) {
              if (state.duplicateGroupCount == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Chip(
                  label: Text('${state.duplicateGroupCount}'),
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ],
      ),
      insetPadding: _dialogInsetPadding(context),
      contentPadding: _dialogContentPadding(context),
      content: SizedBox(
        width: _dialogContentWidth(context, 640),
        height: _dialogContentHeight(context, 480),
        child: BlocBuilder<VaultBloc, VaultState>(
          buildWhen: (p, n) =>
              p.isDuplicatesLoading != n.isDuplicatesLoading ||
              p.duplicateGroups != n.duplicateGroups,
          builder: (context, state) {
            if (state.isDuplicatesLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.duplicateGroups.isEmpty) {
              return const _DuplicatesEmptyState();
            }
            return ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: state.duplicateGroups.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: _VaultUiTokens.recordListSpacing),
              itemBuilder: (context, index) {
                return _DuplicateGroupCard(group: state.duplicateGroups[index]);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({required this.group});

  final DuplicateGroup group;

  Future<void> _handleMerge(
    BuildContext context,
    VaultEntry primary,
    VaultEntry secondary,
  ) async {
    final service = di.sl<VaultDuplicateService>();
    final preview = service.previewMerge(primary, secondary);
    final confirmed = await _showMergeConfirmDialog(context, preview);
    if (confirmed && context.mounted) {
      context.read<VaultBloc>().add(
        MergeDuplicateEntries(primaryId: primary.id, secondaryId: secondary.id),
      );
    }
  }

  Future<void> _handleDelete(BuildContext context, VaultEntry entry) async {
    final label = entry.title.isEmpty ? 'Untitled' : entry.title;
    final confirmed = await _showDeleteConfirm(
      context,
      label: 'Move "$label" to the recycle bin?',
      actionLabel: 'Move to bin',
    );
    if (confirmed && context.mounted) {
      context.read<VaultBloc>().add(DeleteDuplicateEntry(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = group.entries.first;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(
          alpha: isDark ? 0.6 : 0.8,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.6 : 0.75,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  width: _VaultUiTokens.folderIconContainerSize,
                  height: _VaultUiTokens.folderIconContainerSize,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(
                      alpha: isDark ? 0.45 : 0.6,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    AppIcons.copy,
                    size: 16,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.sharedUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (group.sharedUsername.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          group.sharedUsername,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(
                      alpha: isDark ? 0.5 : 0.65,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${group.entries.length} copies',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < group.entries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _DuplicateEntrySubCard(
                    entry: group.entries[i],
                    isPrimary: i == 0,
                    onMergeIntoPrimary: i == 0
                        ? null
                        : () => _handleMerge(context, primary, group.entries[i]),
                    onDelete: () => _handleDelete(context, group.entries[i]),
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

class _DuplicateEntrySubCard extends StatelessWidget {
  const _DuplicateEntrySubCard({
    required this.entry,
    required this.isPrimary,
    required this.onDelete,
    this.onMergeIntoPrimary,
  });

  final VaultEntry entry;
  final bool isPrimary;
  final VoidCallback? onMergeIntoPrimary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
    final modifiedAt = entry.updatedAt ?? entry.createdAt;

    return _InteractiveItemSurface(
      radius: _VaultUiTokens.recordItemRadius,
      baseColor: colorScheme.surface.withValues(alpha: isDark ? 0.72 : 0.9),
      hoveredColor: colorScheme.surface.withValues(alpha: isDark ? 0.84 : 0.97),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 8, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title.isEmpty ? '(Untitled)' : entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer.withValues(
                              alpha: isDark ? 0.55 : 0.7,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Newest',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (modifiedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Modified ${_formatEntryDateTime(modifiedAt)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onMergeIntoPrimary != null)
                  Tooltip(
                    message: 'Merge into newest',
                    ignorePointer: true,
                    child: IconButton(
                      onPressed: onMergeIntoPrimary,
                      icon: const Icon(AppIcons.move),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                Tooltip(
                  message: 'Move to recycle bin',
                  ignorePointer: true,
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(AppIcons.delete),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _showMergeConfirmDialog(
  BuildContext context,
  MergePreview preview,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
      final textTheme = Theme.of(dialogContext).textTheme;

      final primaryLabel =
          preview.primary.title.isEmpty ? 'Untitled' : preview.primary.title;
      final secondaryLabel =
          preview.secondary.title.isEmpty
              ? 'Untitled'
              : preview.secondary.title;

      final copyItems = [
        if (preview.willCopyNotes) 'Notes',
        if (preview.willCopyOtp) 'OTP / TOTP',
        ...preview.customFieldKeysToCopy.map((k) => 'Custom field "$k"'),
        if (preview.willCopyAttachments) 'Attachments',
      ];

      return AlertDialog(
        title: const Text('Merge duplicates'),
        insetPadding: _dialogInsetPadding(dialogContext),
        contentPadding: _dialogContentPadding(dialogContext),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        content: SizedBox(
          width: _dialogContentWidth(dialogContext, 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"$primaryLabel" will be kept.'),
              const SizedBox(height: 4),
              Text(
                '"$secondaryLabel" will be moved to the recycle bin.',
              ),
              const SizedBox(height: 12),
              if (copyItems.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow.withValues(
                      alpha: isDark ? 0.65 : 0.85,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(
                        alpha: isDark ? 0.6 : 0.75,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Will copy to kept entry:',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final item in copyItems)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                AppIcons.check,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item,
                                  style: textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              else
                Text(
                  'No additional data to copy from the older entry.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        actions: _adaptiveDialogActions(dialogContext, [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Merge'),
          ),
        ]),
      );
    },
  );
  return result ?? false;
}

class _DuplicatesEmptyState extends StatelessWidget {
  const _DuplicatesEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: isDark ? 0.68 : 0.9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.65 : 0.86,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(
                  alpha: isDark ? 0.45 : 0.58,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(AppIcons.check, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text(
              'No duplicates found',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'All vault entries have unique URL and username combinations.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
