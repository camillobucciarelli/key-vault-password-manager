part of '../vault_screen.dart';

class _SectionTitleWithCount extends StatelessWidget {
  const _SectionTitleWithCount({
    required this.title,
    required this.count,
    this.onAddPressed,
    this.addLabel,
    this.addTooltip,
    this.addIcon,
  });

  final String title;
  final int count;
  final Future<void> Function()? onAddPressed;
  final String? addLabel;
  final String? addTooltip;
  final IconData? addIcon;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedLabel = constraints.maxWidth < 320
            ? 'Add'
            : (addLabel ?? 'Add');

        final addButton = FilledButton.tonalIcon(
          onPressed: onAddPressed,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            animationDuration: _VaultUiTokens.buttonTransitionDuration,
          ),
          icon: Icon(addIcon ?? AppIcons.add, size: 18),
          label: Text(resolvedLabel),
        );

        if (constraints.maxWidth < 220) {
          return Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (onAddPressed != null)
                Tooltip(message: addTooltip, child: addButton),
              badge,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
            if (onAddPressed != null)
              Tooltip(message: addTooltip, child: addButton),
            const SizedBox(width: 8),
            badge,
          ],
        );
      },
    );
  }
}

class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip({required this.state});

  final VaultState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _syncStatusColor(state.syncStatus, colorScheme);
    final statusIcon = switch (state.syncStatus) {
      DatabaseSyncStatus.syncing => AppIcons.sync,
      DatabaseSyncStatus.success => AppIcons.cloudDone,
      DatabaseSyncStatus.error => AppIcons.cloudOff,
      DatabaseSyncStatus.conflict => AppIcons.warning,
      DatabaseSyncStatus.disconnected => AppIcons.cloudOff,
      DatabaseSyncStatus.idle => AppIcons.cloud,
    };
    final label = state.lastSyncAt == null
        ? _syncStatusLabel(state.syncStatus)
        : '${_syncStatusLabel(state.syncStatus)} • ${_formatSyncDateTime(state.lastSyncAt!)}';
    final details = !state.isDriveConnected
        ? 'Step 1/2: connect Google Drive'
        : !state.isDriveLinked
        ? 'Step 2/2: link this database to a Drive .kdbx file'
        : state.linkedDriveFileName == null
        ? label
        : '$label • ${state.linkedDriveFileName}';
    final canSyncNow = state.isDriveConnected && state.isDriveLinked;

    return SizedBox(
      height: _VaultLayoutBreakpoints.syncStripHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactAction = constraints.maxWidth < 560;

              final syncAction = !state.isDriveConnected
                  ? FilledButton.tonalIcon(
                      onPressed: () {
                        context.read<VaultBloc>().add(
                          const ConnectGoogleDrive(),
                        );
                      },
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        animationDuration:
                            _VaultUiTokens.buttonTransitionDuration,
                      ),
                      icon: const Icon(AppIcons.cloud, size: 17),
                      label: const Text('Connect'),
                    )
                  : !state.isDriveLinked
                  ? FilledButton.tonalIcon(
                      onPressed: () async {
                        await _startDriveLinkFlow(context);
                      },
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        animationDuration:
                            _VaultUiTokens.buttonTransitionDuration,
                      ),
                      icon: const Icon(AppIcons.fileKey, size: 17),
                      label: const Text('Link DB'),
                    )
                  : compactAction
                  ? FilledButton.tonal(
                      onPressed: canSyncNow
                          ? () {
                              context.read<VaultBloc>().add(
                                const SyncCurrentDatabaseNow(),
                              );
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(40, 34),
                        padding: EdgeInsets.zero,
                        animationDuration:
                            _VaultUiTokens.buttonTransitionDuration,
                      ),
                      child: const Tooltip(
                        message: 'Sync now',
                        child: Icon(AppIcons.sync, size: 17),
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: canSyncNow
                          ? () {
                              context.read<VaultBloc>().add(
                                const SyncCurrentDatabaseNow(),
                              );
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        animationDuration:
                            _VaultUiTokens.buttonTransitionDuration,
                      ),
                      icon: const Icon(AppIcons.sync, size: 17),
                      label: const Text('Sync now'),
                    );

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _DriveSetupProgressIndicator(
                      connected: state.isDriveConnected,
                      linked: state.isDriveLinked,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(statusIcon, size: 13, color: statusColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    syncAction,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DriveSetupProgressIndicator extends StatelessWidget {
  const _DriveSetupProgressIndicator({
    required this.connected,
    required this.linked,
  });

  final bool connected;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget step({required int number, required bool done}) {
      final activeColor = colorScheme.primary;
      final idleColor = colorScheme.outline.withValues(alpha: 0.7);
      final bg = done
          ? activeColor.withValues(alpha: 0.18)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.8);
      final fg = done ? activeColor : idleColor;

      return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: fg.withValues(alpha: 0.7)),
        ),
        child: done
            ? Icon(AppIcons.check, size: 11, color: fg)
            : Text(
                '$number',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
      );
    }

    return Tooltip(
      message: linked
          ? 'Drive setup complete'
          : connected
          ? 'Setup step 2/2: link this database'
          : 'Setup step 1/2: connect Google Drive',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          step(number: 1, done: connected),
          Container(
            width: 10,
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: (connected ? colorScheme.primary : colorScheme.outline)
                .withValues(alpha: 0.45),
          ),
          step(number: 2, done: linked),
        ],
      ),
    );
  }
}

class _BreadcrumbsBar extends StatelessWidget {
  const _BreadcrumbsBar({
    required this.groups,
    required this.rootGroupId,
    required this.childGroups,
    required this.allGroups,
  });

  final List<VaultGroup> groups;
  final String? rootGroupId;
  final List<VaultGroup> childGroups;
  final List<VaultGroup> allGroups;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rootLabelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.9),
      fontWeight: FontWeight.w600,
    );
    final crumbStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.8),
      fontWeight: FontWeight.w500,
    );
    final currentStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );

    final path = groups.length > 1 ? groups.sublist(1) : const <VaultGroup>[];
    final children = <Widget>[
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: rootGroupId == null
            ? null
            : () {
                context.read<VaultBloc>().add(OpenGroup(rootGroupId!));
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.home, size: 16),
              const SizedBox(width: 4),
              Text('Vault', style: rootLabelStyle),
            ],
          ),
        ),
      ),
    ];

    for (var i = 0; i < path.length; i++) {
      final group = path[i];
      final isLast = i == path.length - 1;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            AppIcons.chevronRight,
            size: 16,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
      children.add(
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isLast
              ? null
              : () {
                  context.read<VaultBloc>().add(OpenGroup(group.id));
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              group.name,
              style: isLast ? currentStyle : crumbStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    final foldersButton = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        _showChildGroupsPicker(
          context,
          childGroups: childGroups,
          allGroups: allGroups,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.68),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.folderOpen, size: 16),
            const SizedBox(width: 4),
            Text('${childGroups.length}'),
            const SizedBox(width: 2),
            const Icon(AppIcons.chevronDown, size: 15),
          ],
        ),
      ),
    );

    return SizedBox(
      height: _VaultLayoutBreakpoints.breadcrumbBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: children),
              ),
            ),
            const SizedBox(width: 8),
            foldersButton,
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              onPressed: () async {
                final name = await _showGroupDialog(context);
                if (name != null && name.trim().isNotEmpty && context.mounted) {
                  context.read<VaultBloc>().add(CreateVaultGroup(name.trim()));
                }
              },
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                animationDuration: _VaultUiTokens.buttonTransitionDuration,
              ),
              icon: const Icon(AppIcons.folderAdd, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showChildGroupsPicker(
  BuildContext rootContext, {
  required List<VaultGroup> childGroups,
  required List<VaultGroup> allGroups,
}) async {
  String query = _childGroupsPickerLastQuery;

  await showModalBottomSheet<void>(
    context: rootContext,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final colorScheme = Theme.of(sheetContext).colorScheme;

      return StatefulBuilder(
        builder: (context, setState) {
          final filtered = childGroups
              .where(
                (group) =>
                    query.trim().isEmpty ||
                    group.name.toLowerCase().contains(
                      query.trim().toLowerCase(),
                    ),
              )
              .toList(growable: false);

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SizedBox(
                height: _dialogContentHeight(sheetContext, 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Subfolders',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Search folders',
                        prefixIcon: Icon(AppIcons.search),
                      ),
                      initialValue: query,
                      onChanged: (value) {
                        setState(() {
                          query = value;
                          _childGroupsPickerLastQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: childGroups.isEmpty
                          ? Center(
                              child: Text(
                                'No subfolders yet',
                                style: Theme.of(
                                  sheetContext,
                                ).textTheme.bodyMedium,
                              ),
                            )
                          : filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No folders found',
                                style: Theme.of(
                                  sheetContext,
                                ).textTheme.bodyMedium,
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              itemBuilder: (context, index) {
                                final group = filtered[index];
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    AppIcons.folder,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.78,
                                    ),
                                  ),
                                  title: Text(
                                    group.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    rootContext.read<VaultBloc>().add(
                                      OpenGroup(group.id),
                                    );
                                  },
                                  trailing: PopupMenuButton<_ChildGroupAction>(
                                    tooltip: 'Folder actions',
                                    onSelected: (action) async {
                                      Navigator.of(sheetContext).pop();
                                      await _handleChildGroupAction(
                                        rootContext,
                                        group: group,
                                        action: action,
                                        allGroups: allGroups,
                                      );
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: _ChildGroupAction.rename,
                                        child: Text('Rename'),
                                      ),
                                      PopupMenuItem(
                                        value: _ChildGroupAction.move,
                                        child: Text('Move'),
                                      ),
                                      PopupMenuItem(
                                        value: _ChildGroupAction.delete,
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

enum _ChildGroupAction { rename, move, delete }

String _childGroupsPickerLastQuery = '';

Future<void> _handleChildGroupAction(
  BuildContext context, {
  required VaultGroup group,
  required _ChildGroupAction action,
  required List<VaultGroup> allGroups,
}) async {
  switch (action) {
    case _ChildGroupAction.rename:
      final name = await _showGroupDialog(
        context,
        initialName: group.name,
        title: 'Rename folder',
        actionLabel: 'Save',
      );
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        context.read<VaultBloc>().add(
          RenameVaultGroup(groupId: group.id, newName: name.trim()),
        );
      }
      break;
    case _ChildGroupAction.move:
      final target = await _showMoveTargetDialog(
        context,
        allGroups,
        currentGroupId: group.id,
      );
      if (target != null && context.mounted) {
        context.read<VaultBloc>().add(
          MoveVaultGroup(groupId: group.id, targetGroupId: target),
        );
      }
      break;
    case _ChildGroupAction.delete:
      final confirmed = await _showDeleteConfirm(
        context,
        label: 'Permanently delete this empty folder?',
        actionLabel: 'Delete forever',
      );
      if (confirmed && context.mounted) {
        context.read<VaultBloc>().add(DeleteVaultGroup(group.id));
      }
      break;
  }
}
