part of '../vault_screen.dart';

class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip({
    required this.state,
    required this.onRefresh,
    required this.onOpenRecycleBin,
    required this.onSwitchDatabase,
  });

  final VaultState state;
  final VoidCallback onRefresh;
  final VoidCallback onOpenRecycleBin;
  final Future<void> Function() onSwitchDatabase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final compactActions = MediaQuery.sizeOf(context).width < 390;
    final canConfigureAndroidAutofill =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final databaseName = state.databasePath.trim().isEmpty
        ? 'Database'
        : path.basenameWithoutExtension(state.databasePath);
    final databaseCaption = state.databasePath.trim().isEmpty
        ? 'Active vault'
        : path.basename(state.databasePath);
    final showSetupProgress = !(state.isDriveConnected && state.isDriveLinked);
    final isDriveSyncReady = state.isDriveConnected && state.isDriveLinked;
    final primaryActionTooltip = isDriveSyncReady
        ? 'Sync database'
        : 'Refresh vault';
    final primaryActionIcon = isDriveSyncReady
        ? AppIcons.sync
        : AppIcons.refresh;
    final isSyncInProgress = state.syncStatus == DatabaseSyncStatus.syncing;
    final isPrimaryActionBusy = isDriveSyncReady && isSyncInProgress;
    final effectivePrimaryTooltip = isPrimaryActionBusy
        ? 'Sync in progress'
        : primaryActionTooltip;
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

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_VaultUiTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_VaultUiTokens.cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compactActions)
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(
                            AppIcons.fileKey,
                            size: 13,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Tooltip(
                            message: state.databasePath,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  databaseName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  databaseCaption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.68,
                                    ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: effectivePrimaryTooltip,
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: isPrimaryActionBusy
                        ? null
                        : () {
                            if (isDriveSyncReady) {
                              context.read<VaultBloc>().add(
                                const SyncCurrentDatabaseNow(),
                              );
                              return;
                            }
                            onRefresh();
                          },
                    icon: _SyncStripActionIcon(
                      icon: primaryActionIcon,
                      highlighted: isDriveSyncReady,
                      spinning: isSyncInProgress,
                    ),
                  ),
                  const SizedBox(width: 2),
                  _SyncStripMenuButton(
                    state: state,
                    canConfigureAndroidAutofill: canConfigureAndroidAutofill,
                    onOpenRecycleBin: onOpenRecycleBin,
                    onSwitchDatabase: onSwitchDatabase,
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          AppIcons.fileKey,
                          size: 13,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Tooltip(
                          message: state.databasePath,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                databaseName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                databaseCaption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.68,
                                  ),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: effectivePrimaryTooltip,
                        style: IconButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: isPrimaryActionBusy
                            ? null
                            : () {
                                if (isDriveSyncReady) {
                                  context.read<VaultBloc>().add(
                                    const SyncCurrentDatabaseNow(),
                                  );
                                  return;
                                }
                                onRefresh();
                              },
                        icon: _SyncStripActionIcon(
                          icon: primaryActionIcon,
                          highlighted: isDriveSyncReady,
                          spinning: isSyncInProgress,
                        ),
                      ),
                      const SizedBox(width: 2),
                      _SyncStripMenuButton(
                        state: state,
                        canConfigureAndroidAutofill:
                            canConfigureAndroidAutofill,
                        onOpenRecycleBin: onOpenRecycleBin,
                        onSwitchDatabase: onSwitchDatabase,
                      ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 10),
            if (showSetupProgress && compactActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    _DriveSetupProgressIndicator(
                      connected: state.isDriveConnected,
                      linked: state.isDriveLinked,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                if (showSetupProgress && !compactActions) ...[
                  _DriveSetupProgressIndicator(
                    connected: state.isDriveConnected,
                    linked: state.isDriveLinked,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(statusIcon, size: 12, color: statusColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    details,
                    maxLines: compactActions ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w500,
                    ),
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

class _SyncStripMenuButton extends StatelessWidget {
  const _SyncStripMenuButton({
    required this.state,
    required this.canConfigureAndroidAutofill,
    required this.onOpenRecycleBin,
    required this.onSwitchDatabase,
  });

  final VaultState state;
  final bool canConfigureAndroidAutofill;
  final VoidCallback onOpenRecycleBin;
  final Future<void> Function() onSwitchDatabase;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select((ThemeCubit cubit) => cubit.state);

    Future<void> handleSelection(String value) async {
      switch (value) {
        case 'connect':
          context.read<VaultBloc>().add(const ConnectGoogleDrive());
          break;
        case 'disconnect':
          context.read<VaultBloc>().add(const DisconnectGoogleDrive());
          break;
        case 'link':
          await _startDriveLinkFlow(context);
          break;
        case 'toggleAutoSync':
          context.read<VaultBloc>().add(
            ToggleCurrentDatabaseAutoSync(!state.autoSyncEnabled),
          );
          break;
        case 'recycleBin':
          onOpenRecycleBin();
          break;
        case 'switchDatabase':
          await onSwitchDatabase();
          break;
        case 'importCsv':
          await _startCsvImportFlow(context);
          break;
        case 'androidAutofill':
          await _openAndroidAutofillSettings(context);
          break;
        case 'themeSystem':
          context.read<ThemeCubit>().setTheme(ThemeMode.system);
          break;
        case 'themeLight':
          context.read<ThemeCubit>().setTheme(ThemeMode.light);
          break;
        case 'themeDark':
          context.read<ThemeCubit>().setTheme(ThemeMode.dark);
          break;
      }
    }

    return IconButton(
      tooltip: 'Settings',
      style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) {
            final currentDriveStepAction = !state.isDriveConnected
                ? 'connect'
                : !state.isDriveLinked
                ? 'link'
                : null;
            final currentDriveStepLabel = !state.isDriveConnected
                ? 'Connect Google Drive'
                : !state.isDriveLinked
                ? 'Link this database'
                : null;

            Future<void> closeAndSelect(String value) async {
              Navigator.of(sheetContext).pop();
              await handleSelection(value);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExpansionTile(
                        title: const Text('Google Drive'),
                        initiallyExpanded: true,
                        children: [
                          if (currentDriveStepAction != null &&
                              currentDriveStepLabel != null)
                            ListTile(
                              onTap: () =>
                                  closeAndSelect(currentDriveStepAction),
                              title: Text(currentDriveStepLabel),
                            ),
                          ListTile(
                            enabled: state.isDriveConnected,
                            onTap: state.isDriveConnected
                                ? () => closeAndSelect('disconnect')
                                : null,
                            title: const Text('Disconnect Google Drive'),
                          ),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text('Vault'),
                        initiallyExpanded: true,
                        children: [
                          ListTile(
                            onTap: () => closeAndSelect('toggleAutoSync'),
                            title: Text(
                              state.autoSyncEnabled
                                  ? 'Disable auto-sync'
                                  : 'Enable auto-sync',
                            ),
                          ),
                          ListTile(
                            onTap: () => closeAndSelect('switchDatabase'),
                            title: const Text('Switch database'),
                          ),
                          ListTile(
                            onTap: () => closeAndSelect('importCsv'),
                            title: const Text('Import from CSV'),
                          ),
                          if (canConfigureAndroidAutofill)
                            ListTile(
                              onTap: () => closeAndSelect('androidAutofill'),
                              title: const Text('Autofill Android'),
                            ),
                          ListTile(
                            onTap: () => closeAndSelect('recycleBin'),
                            title: const Text('Open recycle bin'),
                          ),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text('Theme'),
                        children: [
                          ListTile(
                            onTap: () => closeAndSelect('themeSystem'),
                            title: const Text('System'),
                            trailing: themeMode == ThemeMode.system
                                ? const Icon(AppIcons.check, size: 16)
                                : null,
                          ),
                          ListTile(
                            onTap: () => closeAndSelect('themeLight'),
                            title: const Text('Light'),
                            trailing: themeMode == ThemeMode.light
                                ? const Icon(AppIcons.check, size: 16)
                                : null,
                          ),
                          ListTile(
                            onTap: () => closeAndSelect('themeDark'),
                            title: const Text('Dark'),
                            trailing: themeMode == ThemeMode.dark
                                ? const Icon(AppIcons.check, size: 16)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      icon: const _SyncStripActionIcon(icon: AppIcons.more),
    );
  }
}

class _SyncStripActionIcon extends StatelessWidget {
  const _SyncStripActionIcon({
    required this.icon,
    this.highlighted = false,
    this.spinning = false,
  });

  final IconData icon;
  final bool highlighted;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = highlighted
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final background = highlighted
        ? colorScheme.primaryContainer.withValues(alpha: 0.9)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.84);
    final borderColor = highlighted
        ? colorScheme.primary.withValues(alpha: 0.28)
        : colorScheme.outlineVariant.withValues(alpha: 0.55);

    final iconWidget = Icon(icon, size: 16, color: foreground);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: borderColor),
      ),
      child: spinning
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            )
          : iconWidget,
    );
  }
}

Future<void> _openAndroidAutofillSettings(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = AutofillService();
  final status = await service.status;

  if (status == AutofillServiceStatus.unsupported) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Android Autofill is not supported on this device.'),
      ),
    );
    return;
  }

  if (status == AutofillServiceStatus.enabled) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Autofill service is already active.')),
    );
    return;
  }

  await service.requestSetAutofillService();
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Select this app as your Android Autofill service.'),
    ),
  );
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

enum _ChildGroupAction { rename, move, delete }

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
