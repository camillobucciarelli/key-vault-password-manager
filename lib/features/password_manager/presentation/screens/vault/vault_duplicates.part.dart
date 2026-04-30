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
              if (state.duplicateGroupCount == 0) {
                return const SizedBox.shrink();
              }
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
        width: _dialogContentWidth(context, 720),
        height: _dialogContentHeight(context, 520),
        child: BlocBuilder<VaultBloc, VaultState>(
          buildWhen: (p, n) =>
              p.isDuplicatesLoading != n.isDuplicatesLoading ||
              p.isSaving != n.isSaving ||
              p.duplicateGroups != n.duplicateGroups,
          builder: (context, state) {
            if (state.isDuplicatesLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.duplicateGroups.isEmpty) {
              return const _DuplicatesEmptyState();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: _VaultUiTokens.itemTransitionDuration,
                  child: state.isSaving
                      ? const LinearProgressIndicator(minHeight: 2)
                      : const SizedBox(height: 2),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: state.duplicateGroups.length,
                    separatorBuilder: (_, _) => const SizedBox(
                      height: _VaultUiTokens.recordListSpacing,
                    ),
                    itemBuilder: (context, index) {
                      return _DuplicateGroupCard(
                        group: state.duplicateGroups[index],
                        isBusy: state.isSaving,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        BlocBuilder<VaultBloc, VaultState>(
          buildWhen: (p, n) => p.isSaving != n.isSaving,
          builder: (context, state) {
            return TextButton(
              onPressed: state.isSaving
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Text(state.isSaving ? 'Updating...' : 'Close'),
            );
          },
        ),
      ],
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({required this.group, required this.isBusy});

  final DuplicateGroup group;
  final bool isBusy;

  Future<void> _handleMerge(
    BuildContext context,
    VaultEntry primary,
    VaultEntry secondary,
  ) async {
    final service = di.sl<VaultDuplicateService>();
    final preview = service.previewMerge(primary, secondary);
    final confirmed = await _showMergeReviewDialog(context, preview);
    if (confirmed && context.mounted) {
      context.read<VaultBloc>().add(
        MergeDuplicateEntries(primaryId: primary.id, secondaryId: secondary.id),
      );
    }
  }

  Future<void> _handleCompare(
    BuildContext context,
    VaultEntry primary,
    VaultEntry secondary,
  ) async {
    final service = di.sl<VaultDuplicateService>();
    final preview = service.previewMerge(primary, secondary);
    await _showMergeReviewDialog(context, preview, allowMerge: false);
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
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
                        : () =>
                              _handleMerge(context, primary, group.entries[i]),
                    onCompare: i == 0
                        ? null
                        : () => _handleCompare(
                            context,
                            primary,
                            group.entries[i],
                          ),
                    onDelete: () => _handleDelete(context, group.entries[i]),
                    isBusy: isBusy,
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
    required this.isBusy,
    this.onMergeIntoPrimary,
    this.onCompare,
  });

  final VaultEntry entry;
  final bool isPrimary;
  final VoidCallback? onMergeIntoPrimary;
  final VoidCallback? onCompare;
  final VoidCallback onDelete;
  final bool isBusy;

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
                    message: 'Review and merge into newest',
                    ignorePointer: true,
                    child: IconButton(
                      onPressed: isBusy ? null : onMergeIntoPrimary,
                      icon: const Icon(AppIcons.move),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (onCompare != null)
                  Tooltip(
                    message: 'Compare with newest',
                    ignorePointer: true,
                    child: IconButton(
                      onPressed: isBusy ? null : onCompare,
                      icon: const Icon(AppIcons.info),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                Tooltip(
                  message: 'Move to recycle bin',
                  ignorePointer: true,
                  child: IconButton(
                    onPressed: isBusy ? null : onDelete,
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

Future<bool> _showMergeReviewDialog(
  BuildContext context,
  MergePreview preview, {
  bool allowMerge = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      final textTheme = Theme.of(dialogContext).textTheme;
      final primaryLabel = preview.primary.title.isEmpty
          ? 'Untitled'
          : preview.primary.title;
      final secondaryLabel = preview.secondary.title.isEmpty
          ? 'Untitled'
          : preview.secondary.title;
      final comparisonRows = _buildMergeComparisonRows(preview);
      final differentCount = comparisonRows
          .where((row) => row.isDifferent)
          .length;

      return AlertDialog(
        title: Text(allowMerge ? 'Review merge' : 'Compare duplicates'),
        insetPadding: _dialogInsetPadding(dialogContext),
        contentPadding: _dialogContentPadding(dialogContext),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        content: SizedBox(
          width: _dialogContentWidth(dialogContext, 680),
          height: _dialogContentHeight(dialogContext, 520),
          child: ListView(
            children: [
              _MergeSummaryBanner(
                primaryLabel: primaryLabel,
                secondaryLabel: secondaryLabel,
                differentCount: differentCount,
                hasAnythingToCopy: preview.hasAnythingToCopy,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MergeEntryHeader(
                      label: 'Kept record',
                      title: primaryLabel,
                      entry: preview.primary,
                      icon: AppIcons.check,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MergeEntryHeader(
                      label: 'Moved to bin',
                      title: secondaryLabel,
                      entry: preview.secondary,
                      icon: AppIcons.delete,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Field comparison',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < comparisonRows.length; i++) ...[
                _MergeComparisonRow(row: comparisonRows[i]),
                if (i < comparisonRows.length - 1) const SizedBox(height: 6),
              ],
              if (!preview.hasAnythingToCopy) ...[
                const SizedBox(height: 12),
                Text(
                  'The kept record already has the mergeable data. Merging will only move the duplicate to the recycle bin.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: _adaptiveDialogActions(dialogContext, [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(allowMerge ? 'Cancel' : 'Close'),
          ),
          if (allowMerge)
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(AppIcons.move, size: 16),
              label: const Text('Merge and move duplicate'),
            ),
        ]),
      );
    },
  );
  return result ?? false;
}

class _MergeSummaryBanner extends StatelessWidget {
  const _MergeSummaryBanner({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.differentCount,
    required this.hasAnythingToCopy,
  });

  final String primaryLabel;
  final String secondaryLabel;
  final int differentCount;
  final bool hasAnythingToCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StyledInfoContainer(
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.42),
      borderColor: colorScheme.primary.withValues(alpha: 0.26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"$primaryLabel" stays in the vault.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '"$secondaryLabel" will be moved to the recycle bin after the merge.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MergeStatusChip(
                label: '$differentCount different fields',
                color: colorScheme.tertiary,
              ),
              _MergeStatusChip(
                label: hasAnythingToCopy
                    ? 'Some data will be copied'
                    : 'No extra data to copy',
                color: hasAnythingToCopy
                    ? colorScheme.primary
                    : colorScheme.outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MergeEntryHeader extends StatelessWidget {
  const _MergeEntryHeader({
    required this.label,
    required this.title,
    required this.entry,
    required this.icon,
  });

  final String label;
  final String title;
  final VaultEntry entry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modifiedAt = entry.updatedAt ?? entry.createdAt;

    return StyledInfoContainer(
      padding: const EdgeInsets.all(10),
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.38,
      ),
      borderColor: colorScheme.outlineVariant.withValues(alpha: 0.72),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (modifiedAt != null)
                  Text(
                    _formatEntryDateTime(modifiedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MergeComparisonRowData {
  const _MergeComparisonRowData({
    required this.label,
    required this.primaryValue,
    required this.secondaryValue,
    required this.statusLabel,
    required this.statusColor,
    required this.isDifferent,
  });

  final String label;
  final String primaryValue;
  final String secondaryValue;
  final String statusLabel;
  final Color Function(ColorScheme) statusColor;
  final bool isDifferent;
}

class _MergeComparisonRow extends StatelessWidget {
  const _MergeComparisonRow({required this.row});

  final _MergeComparisonRowData row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StyledInfoContainer(
      padding: const EdgeInsets.all(10),
      backgroundColor: row.isDifferent
          ? colorScheme.tertiaryContainer.withValues(alpha: 0.24)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
      borderColor: row.isDifferent
          ? colorScheme.tertiary.withValues(alpha: 0.32)
          : colorScheme.outlineVariant.withValues(alpha: 0.58),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _MergeStatusChip(
                label: row.statusLabel,
                color: row.statusColor(colorScheme),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MergeValueColumn(
                  label: 'Kept',
                  value: row.primaryValue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MergeValueColumn(
                  label: 'Duplicate',
                  value: row.secondaryValue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MergeValueColumn extends StatelessWidget {
  const _MergeValueColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? 'Not set' : value,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: value.isEmpty
                ? colorScheme.onSurface.withValues(alpha: 0.56)
                : colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _MergeStatusChip extends StatelessWidget {
  const _MergeStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

List<_MergeComparisonRowData> _buildMergeComparisonRows(MergePreview preview) {
  final rows = <_MergeComparisonRowData>[
    _mergeRow('Title', preview.primary.title, preview.secondary.title),
    _mergeRow('Username', preview.primary.username, preview.secondary.username),
    _mergeRow(
      'Password',
      _passwordMergeValue(preview.primary.password),
      _passwordMergeValue(preview.secondary.password),
      comparePrimary: preview.primary.password,
      compareSecondary: preview.secondary.password,
    ),
    _mergeRow('URL', preview.primary.url, preview.secondary.url),
    _mergeRow(
      'Notes',
      preview.primary.notes,
      preview.secondary.notes,
      statusOverride: preview.willCopyNotes ? 'Will copy' : null,
      statusColorOverride: preview.willCopyNotes
          ? (scheme) => scheme.primary
          : null,
    ),
    _mergeRow(
      'OTP / TOTP',
      preview.primary.otpUri ?? '',
      preview.secondary.otpUri ?? '',
      statusOverride: preview.willCopyOtp ? 'Will copy' : null,
      statusColorOverride: preview.willCopyOtp
          ? (scheme) => scheme.primary
          : null,
    ),
    _mergeRow(
      'Attachments',
      _attachmentsMergeValue(preview.primary.attachments),
      _attachmentsMergeValue(preview.secondary.attachments),
      statusOverride: preview.willCopyAttachments ? 'Will copy missing' : null,
      statusColorOverride: preview.willCopyAttachments
          ? (scheme) => scheme.primary
          : null,
    ),
  ];

  final fieldKeys =
      <String>{
        for (final field in preview.primary.customFields)
          if (!_isOtpFieldKey(field.key)) field.key,
        for (final field in preview.secondary.customFields)
          if (!_isOtpFieldKey(field.key)) field.key,
      }.toList()..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );

  for (final key in fieldKeys) {
    final primaryValue = _customFieldValue(preview.primary, key);
    final secondaryValue = _customFieldValue(preview.secondary, key);
    final willCopy = preview.customFieldKeysToCopy.any(
      (copyKey) => copyKey.toLowerCase() == key.toLowerCase(),
    );
    rows.add(
      _mergeRow(
        'Custom: $key',
        primaryValue,
        secondaryValue,
        statusOverride: willCopy ? 'Will copy' : null,
        statusColorOverride: willCopy ? (scheme) => scheme.primary : null,
      ),
    );
  }

  return rows;
}

_MergeComparisonRowData _mergeRow(
  String label,
  String primaryValue,
  String secondaryValue, {
  String? comparePrimary,
  String? compareSecondary,
  String? statusOverride,
  Color Function(ColorScheme)? statusColorOverride,
}) {
  final left = (comparePrimary ?? primaryValue).trim();
  final right = (compareSecondary ?? secondaryValue).trim();
  final isDifferent = left != right;
  return _MergeComparisonRowData(
    label: label,
    primaryValue: primaryValue,
    secondaryValue: secondaryValue,
    isDifferent: isDifferent,
    statusLabel: statusOverride ?? (isDifferent ? 'Different' : 'Same'),
    statusColor:
        statusColorOverride ??
        (isDifferent
            ? (scheme) => scheme.tertiary
            : (scheme) => scheme.outline),
  );
}

String _passwordMergeValue(String password) {
  if (password.isEmpty) return '';
  return '${password.length} characters';
}

String _attachmentsMergeValue(List<VaultAttachment> attachments) {
  if (attachments.isEmpty) return '';
  return attachments.map((attachment) => attachment.name).join(', ');
}

String _customFieldValue(VaultEntry entry, String key) {
  for (final field in entry.customFields) {
    if (field.key.toLowerCase() == key.toLowerCase()) {
      return field.value;
    }
  }
  return '';
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
              child: Icon(
                AppIcons.check,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No duplicates found',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
