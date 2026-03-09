part of '../vault_screen.dart';

Future<void> _showRecycleBinDialog(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  bloc.add(const LoadRecycleBinEntries());

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return BlocProvider.value(value: bloc, child: const _RecycleBinDialog());
    },
  );
}

class _RecycleBinDialog extends StatelessWidget {
  const _RecycleBinDialog();

  Future<void> _handleRecycleEntryAction(
    BuildContext context,
    VaultEntry entry,
    _RecycleBinEntryAction action,
  ) async {
    switch (action) {
      case _RecycleBinEntryAction.restore:
        context.read<VaultBloc>().add(RestoreVaultEntry(entry.id));
        break;
      case _RecycleBinEntryAction.deletePermanently:
        final confirmed = await _showDeleteConfirm(
          context,
          label:
              'Permanently delete this record? This action cannot be undone.',
          actionLabel: 'Delete forever',
        );
        if (confirmed && context.mounted) {
          context.read<VaultBloc>().add(DeleteVaultEntryPermanently(entry.id));
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Recycle bin')),
          IconButton(
            tooltip: 'Refresh recycle bin',
            onPressed: () {
              context.read<VaultBloc>().add(const LoadRecycleBinEntries());
            },
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      content: SizedBox(
        width: _dialogContentWidth(context, 620),
        height: _dialogContentHeight(context, 420),
        child: BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            if (state.isRecycleBinLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.recycleBinEntries.isEmpty) {
              return const _RecycleBinEmptyState();
            }

            return ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: state.recycleBinEntries.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: _VaultUiTokens.recordListSpacing),
              itemBuilder: (context, index) {
                final entry = state.recycleBinEntries[index];
                return _RecycleBinEntryListItem(
                  entry: entry,
                  onSelectedAction: (action) {
                    _handleRecycleEntryAction(context, entry, action);
                  },
                );
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
        BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            final isDisabled =
                state.isSaving ||
                state.isRecycleBinLoading ||
                state.recycleBinEntries.isEmpty;

            return FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                animationDuration: _VaultUiTokens.buttonTransitionDuration,
              ),
              onPressed: isDisabled
                  ? null
                  : () async {
                      final confirmed = await _showDeleteConfirm(
                        context,
                        label:
                            'This will permanently remove all items from recycle bin. This action cannot be undone.',
                        actionLabel: 'Empty bin',
                      );
                      if (confirmed && context.mounted) {
                        context.read<VaultBloc>().add(const EmptyRecycleBin());
                      }
                    },
              icon: state.isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    )
                  : const Icon(AppIcons.deleteSweep),
              label: Text(
                state.recycleBinEntries.isEmpty
                    ? 'Empty bin'
                    : 'Empty bin (${state.recycleBinEntries.length})',
              ),
            );
          },
        ),
      ],
    );
  }
}

enum _RecycleBinEntryAction { restore, deletePermanently }

class _InteractiveItemSurface extends StatefulWidget {
  const _InteractiveItemSurface({
    required this.radius,
    required this.child,
    this.minHeight,
    this.onTap,
    this.baseColor,
    this.hoveredColor,
    this.baseBorderColor,
    this.hoveredBorderColor,
  });

  final double radius;
  final double? minHeight;
  final VoidCallback? onTap;
  final Color? baseColor;
  final Color? hoveredColor;
  final Color? baseBorderColor;
  final Color? hoveredBorderColor;
  final Widget child;

  @override
  State<_InteractiveItemSurface> createState() =>
      _InteractiveItemSurfaceState();
}

class _InteractiveItemSurfaceState extends State<_InteractiveItemSurface> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlight = _isHovered || _isFocused;
    final backgroundColor = highlight
        ? (widget.hoveredColor ?? colorScheme.surface.withValues(alpha: 0.82))
        : (widget.baseColor ?? colorScheme.surface.withValues(alpha: 0.74));
    final borderColor = highlight
        ? (widget.hoveredBorderColor ??
              colorScheme.primary.withValues(alpha: 0.32))
        : (widget.baseBorderColor ??
              colorScheme.outlineVariant.withValues(alpha: 0.7));

    final body = AnimatedContainer(
      duration: _VaultUiTokens.itemTransitionDuration,
      curve: Curves.easeOutCubic,
      constraints: widget.minHeight == null
          ? null
          : BoxConstraints(minHeight: widget.minHeight!),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: borderColor),
      ),
      child: widget.child,
    );

    return FocusableActionDetector(
      onShowFocusHighlight: (value) {
        if (_isFocused != value) {
          setState(() {
            _isFocused = value;
          });
        }
      },
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) {
          setState(() {
            _isHovered = true;
          });
        },
        onExit: (_) {
          setState(() {
            _isHovered = false;
          });
        },
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(widget.radius),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _RecycleBinEntryListItem extends StatelessWidget {
  const _RecycleBinEntryListItem({
    required this.entry,
    required this.onSelectedAction,
  });

  final VaultEntry entry;
  final ValueChanged<_RecycleBinEntryAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _InteractiveItemSurface(
      radius: _VaultUiTokens.recordItemRadius,
      minHeight: _VaultUiTokens.recordItemHeight,
      baseColor: colorScheme.surface.withValues(alpha: 0.72),
      hoveredColor: colorScheme.surface.withValues(alpha: 0.84),
      baseBorderColor: colorScheme.outlineVariant.withValues(alpha: 0.7),
      hoveredBorderColor: colorScheme.error.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 8, bottom: 8),
        child: Row(
          children: [
            Container(
              width: _VaultUiTokens.folderIconContainerSize,
              height: _VaultUiTokens.folderIconContainerSize,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                AppIcons.delete,
                size: 18,
                color: colorScheme.onErrorContainer,
              ),
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
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.username.isNotEmpty
                        ? entry.username
                        : (entry.url.isNotEmpty ? entry.url : 'No username'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<_RecycleBinEntryAction>(
              tooltip: 'Recycle bin actions',
              onSelected: onSelectedAction,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _RecycleBinEntryAction.restore,
                  child: Text('Restore'),
                ),
                PopupMenuItem(
                  value: _RecycleBinEntryAction.deletePermanently,
                  child: Text('Delete permanently'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecycleBinEmptyState extends StatelessWidget {
  const _RecycleBinEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                color: colorScheme.errorContainer.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                AppIcons.deleteSweep,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Recycle bin is empty',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Deleted records will appear here until they are restored or removed.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
