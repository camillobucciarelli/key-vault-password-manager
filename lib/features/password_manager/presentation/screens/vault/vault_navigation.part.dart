part of '../vault_screen.dart';

class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip({
    required this.state,
    required this.onRefresh,
    required this.onOpenRecycleBin,
    required this.onOpenDuplicates,
    required this.onChangeDatabase,
  });

  final VaultState state;
  final VoidCallback onRefresh;
  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenDuplicates;
  final Future<void> Function() onChangeDatabase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final compactActions = MediaQuery.sizeOf(context).width < 390;
    final canConfigureAndroidAutofill = false;
    final canConfigureBrowserAutofill = BrowserSetupScreen.shouldShow;
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
    final isSyncInProgress =
        state.syncStatus == DatabaseSyncStatus.syncing || state.isSyncing;
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
        ? 'Connect Google Drive'
        : !state.isDriveLinked
        ? 'Link this database to a Drive .kdbx file'
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
                            ignorePointer: true,
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
                  Tooltip(
                    message: effectivePrimaryTooltip,
                    ignorePointer: true,
                    child: IconButton(
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
                  ),
                  const SizedBox(width: 2),
                  _SyncStripMenuButton(
                    state: state,
                    canConfigureAndroidAutofill: canConfigureAndroidAutofill,
                    canConfigureBrowserAutofill: canConfigureBrowserAutofill,
                    onOpenRecycleBin: onOpenRecycleBin,
                    onOpenDuplicates: onOpenDuplicates,
                    onChangeDatabase: onChangeDatabase,
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
                          ignorePointer: true,
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
                      Tooltip(
                        message: effectivePrimaryTooltip,
                        ignorePointer: true,
                        child: IconButton(
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
                      ),
                      const SizedBox(width: 2),
                      _SyncStripMenuButton(
                        state: state,
                        canConfigureAndroidAutofill:
                            canConfigureAndroidAutofill,
                        canConfigureBrowserAutofill:
                            canConfigureBrowserAutofill,
                        onOpenRecycleBin: onOpenRecycleBin,
                        onOpenDuplicates: onOpenDuplicates,
                        onChangeDatabase: onChangeDatabase,
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
    required this.canConfigureBrowserAutofill,
    required this.onOpenRecycleBin,
    required this.onOpenDuplicates,
    required this.onChangeDatabase,
  });

  final VaultState state;
  final bool canConfigureAndroidAutofill;
  final bool canConfigureBrowserAutofill;
  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenDuplicates;
  final Future<void> Function() onChangeDatabase;

  // spec-005: bodies moved to top-level `_exportDatabaseBackup` /
  // `_exportKeyFileBackup` in vault_shared.part.dart so the new Backups
  // destination (T17) can call the same code — behaviour unchanged (FR-8:
  // "the three existing export actions, unchanged in behaviour").
  Future<void> _exportCurrentDatabaseBackup(BuildContext context) =>
      _exportDatabaseBackup(context, state.databasePath);

  Future<void> _exportCurrentKeyFile(BuildContext context) =>
      _exportKeyFileBackup(context);

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
        case 'manageDuplicates':
          onOpenDuplicates();
          break;
        case 'changeDatabase':
          await onChangeDatabase();
          break;
        case 'importCsv':
          await _startCsvImportFlow(context);
          break;
        case 'lockVault':
          final databasePath = state.databasePath;
          if (databasePath.trim().isNotEmpty) {
            await di.sl<VaultSessionCoordinator>().lockVault(
              currentDatabasePath: databasePath,
            );
            if (!context.mounted) {
              return;
            }
            await AppNavigation.pushFadeReplacement(
              context,
              DatabaseUnlockScreen(databasePath: databasePath),
            );
          }
          break;
        case 'exportDatabaseBackup':
          await _exportCurrentDatabaseBackup(context);
          break;
        case 'exportKeyFile':
          await _exportCurrentKeyFile(context);
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
        case 'browserSetup':
          await _openBrowserAutofillSettings(context);
          break;
        case 'databaseSettings':
          await _showDatabaseSettings(context, state);
          break;
        case 'passwordGenerator':
          await _showPasswordGeneratorSheet(context, standalone: true);
          break;
      }
    }

    return Tooltip(
      message: 'Settings',
      ignorePointer: true,
      child: IconButton(
        style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheetContext) {
              Future<void> closeAndSelect(String value) async {
                Navigator.of(sheetContext).pop();
                await handleSelection(value);
              }

              return _VaultSettingsSheet(
                state: state,
                themeMode: themeMode,
                canConfigureAndroidAutofill: canConfigureAndroidAutofill,
                canConfigureBrowserAutofill: canConfigureBrowserAutofill,
                onSelect: closeAndSelect,
              );
            },
          );
        },
        icon: _DuplicateBadge(
          count: state.duplicateGroupCount,
          child: const _SyncStripActionIcon(icon: AppIcons.more),
        ),
      ),
    );
  }
}
