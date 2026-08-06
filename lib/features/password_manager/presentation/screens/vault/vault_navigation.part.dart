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

  Future<void> _exportCurrentDatabaseBackup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final databasePath = state.databasePath;
    if (databasePath.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No active database to export.')),
      );
      return;
    }

    final source = File(databasePath);
    if (!await source.exists()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Current database file not found.')),
      );
      return;
    }

    final defaultName = path.basename(databasePath);
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Export database backup',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: const ['kdbx'],
    );
    if (savePath == null || savePath.trim().isEmpty) {
      return;
    }

    final resolvedPath = savePath.toLowerCase().endsWith('.kdbx')
        ? savePath
        : '$savePath.kdbx';
    await source.copy(resolvedPath);
    messenger.showSnackBar(
      const SnackBar(content: Text('Database backup exported.')),
    );
  }

  Future<void> _exportCurrentKeyFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final keyPath = await di
        .sl<VaultSessionCoordinator>()
        .getSelectedKeyFilePath();
    if (keyPath == null || keyPath.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No key file configured for this vault.')),
      );
      return;
    }

    final source = File(keyPath);
    if (!await source.exists()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Configured key file was not found.')),
      );
      return;
    }

    final defaultName = path.basename(keyPath);
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Export key file backup',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: const ['key'],
    );
    if (savePath == null || savePath.trim().isEmpty) {
      return;
    }

    await source.copy(savePath);
    messenger.showSnackBar(
      const SnackBar(content: Text('Key file backup exported.')),
    );
  }

  Future<void> _showDatabaseSettings(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final currentDatabasePath = state.databasePath;
    if (currentDatabasePath.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No active database selected.')),
      );
      return;
    }

    var databaseTitle = path.basenameWithoutExtension(currentDatabasePath);
    final sessionCoordinator = di.sl<VaultSessionCoordinator>();
    final persistedCurrentKeyPath = await sessionCoordinator
        .getPersistedKeyFilePath(currentDatabasePath);
    final protectedKeyFilePaths = await sessionCoordinator
        .getProtectedKeyFilePaths();
    if (!context.mounted) {
      return;
    }
    var pendingSelectedKeyPath = persistedCurrentKeyPath;
    var currentPassword = '';
    var newPassword = '';
    var confirmNewPassword = '';
    var changePassword = false;
    var biometricEnabled = await di
        .sl<VaultSessionCoordinator>()
        .getBiometricProtectionEnabledForPath(
          databasePath: currentDatabasePath,
        );
    final initialBiometricEnabled = biometricEnabled;
    var inactivityTimeout = await di
        .sl<VaultSessionCoordinator>()
        .getInactivityLockTimeoutForPath(databasePath: currentDatabasePath);
    final initialInactivityTimeout = inactivityTimeout;
    final initialFileName = path.basename(currentDatabasePath);
    final normalizedCurrentKeyPath = _normalizeKeyPathForComparison(
      persistedCurrentKeyPath,
    );
    if (!context.mounted) {
      return;
    }
    final formKey = GlobalKey<FormState>();

    final shouldApply = await VaultShellRouterScope.of(context).open<DatabaseSettingsResult>(
      context: context,
      surface: DatabaseSettingsSurface<DatabaseSettingsResult>(
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setState) {
              final normalizedSelectedKeyPath = _normalizeKeyPathForComparison(
                pendingSelectedKeyPath,
              );
              final keyFileChanged =
                  normalizedSelectedKeyPath != normalizedCurrentKeyPath;
              final fileNameChanged =
                  _normalizeDatabaseFileName(databaseTitle) != initialFileName;
              final biometricChanged =
                  biometricEnabled != initialBiometricEnabled;
              final inactivityChanged =
                  inactivityTimeout != initialInactivityTimeout;
              final hasSelectedKeyFile =
                  pendingSelectedKeyPath?.trim().isNotEmpty ?? false;
              final pendingChanges = <String>[
                if (fileNameChanged) 'Database file name',
                if (biometricChanged) 'Biometric protection',
                if (inactivityChanged) 'Inactivity lock',
                if (keyFileChanged) 'Key file',
                if (changePassword) 'Master password',
              ];

              Future<void> selectKeyFile() async {
                if (isManagedStoragePlatform) {
                  final currentSelectedPath = pendingSelectedKeyPath;
                  final result = await showInternalKeyFileManagerDialog(
                    dialogContext,
                    initiallySelectedPath: currentSelectedPath,
                    protectedPaths: {
                      ...protectedKeyFilePaths,
                      ?persistedCurrentKeyPath,
                      ?pendingSelectedKeyPath,
                    },
                  );
                  if (result == null || !dialogContext.mounted) {
                    return;
                  }
                  setState(() {
                    if (result.selectedPath != null) {
                      pendingSelectedKeyPath = result.selectedPath;
                      return;
                    }
                    if (result.currentSelectionDeleted &&
                        currentSelectedPath != null &&
                        currentSelectedPath.trim().isNotEmpty) {
                      pendingSelectedKeyPath = null;
                    }
                  });
                  return;
                }

                final picked = await FilePicker.pickFiles(
                  allowMultiple: false,
                  withData: false,
                );
                if (!dialogContext.mounted) {
                  return;
                }
                final selectedFile = picked?.files.single;
                if (selectedFile == null) {
                  return;
                }

                final selectedPath = selectedFile.path;
                if (selectedPath == null || selectedPath.isEmpty) {
                  return;
                }

                setState(() {
                  pendingSelectedKeyPath = selectedPath;
                });
              }

              return AlertDialog(
                title: const Text('Database settings'),
                insetPadding: _dialogInsetPadding(dialogContext),
                contentPadding: _dialogContentPadding(dialogContext),
                actionsOverflowDirection: VerticalDirection.down,
                actionsOverflowButtonSpacing: 8,
                content: SizedBox(
                  width: _dialogContentWidth(dialogContext, 520),
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DatabaseSettingsHeader(
                            databaseName: path.basenameWithoutExtension(
                              currentDatabasePath,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _DatabaseSettingsSectionCard(
                            icon: AppIcons.file,
                            title: 'Vault file',
                            subtitle: 'Change how this local database appears.',
                            children: [
                              TextFormField(
                                initialValue: databaseTitle,
                                decoration: const InputDecoration(
                                  labelText: 'Database file name',
                                  helperText:
                                      'The .kdbx extension is added automatically.',
                                  prefixIcon: Icon(AppIcons.file),
                                ),
                                onChanged: (value) {
                                  databaseTitle = value;
                                  setState(() {});
                                },
                                validator: (value) {
                                  final raw = value?.trim() ?? '';
                                  if (raw.isEmpty) {
                                    return 'Database file name is required.';
                                  }
                                  if (raw.contains(RegExp(r'[\\/:*?"<>|]'))) {
                                    return 'Invalid characters in file name.';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _DatabaseSettingsSectionCard(
                            icon: AppIcons.lock,
                            title: 'Security & lock',
                            subtitle:
                                'Control quick unlock and automatic locking.',
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Biometric protection'),
                                subtitle: const Text(
                                  'Allow face, fingerprint, or device biometrics to unlock this vault.',
                                ),
                                value: biometricEnabled,
                                onChanged: (value) {
                                  setState(() {
                                    biometricEnabled = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<int?>(
                                initialValue: inactivityTimeout,
                                decoration: const InputDecoration(
                                  labelText: 'Lock on inactivity',
                                  helperText:
                                      'Automatically lock this vault after no activity.',
                                  prefixIcon: Icon(AppIcons.lock),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('Never'),
                                  ),
                                  DropdownMenuItem(
                                    value: 10,
                                    child: Text('10 seconds'),
                                  ),
                                  DropdownMenuItem(
                                    value: 20,
                                    child: Text('20 seconds'),
                                  ),
                                  DropdownMenuItem(
                                    value: 30,
                                    child: Text('30 seconds'),
                                  ),
                                  DropdownMenuItem(
                                    value: 60,
                                    child: Text('1 minute'),
                                  ),
                                  DropdownMenuItem(
                                    value: 120,
                                    child: Text('2 minutes'),
                                  ),
                                  DropdownMenuItem(
                                    value: 300,
                                    child: Text('5 minutes'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    inactivityTimeout = value;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _DatabaseSettingsSectionCard(
                            icon: AppIcons.fileKey,
                            title: 'Unlock credentials',
                            subtitle:
                                'Update the key file or master password used to open this vault.',
                            children: [
                              _DatabaseSettingsKeyFilePanel(
                                selectedKeyPath: pendingSelectedKeyPath,
                                onChange: selectKeyFile,
                                onRemove: !hasSelectedKeyFile
                                    ? null
                                    : () {
                                        setState(() {
                                          pendingSelectedKeyPath = null;
                                        });
                                      },
                              ),
                              const SizedBox(height: 10),
                              const _DatabaseSettingsInfoCallout(
                                icon: AppIcons.warning,
                                text:
                                    'Key file changes affect the next unlock. Google Drive sync stores only the .kdbx database; it does not sync key files, so keep a separate backup.',
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Change master password'),
                                subtitle: const Text(
                                  'Re-encrypts this vault. Use the new password the next time you unlock.',
                                ),
                                value: changePassword,
                                onChanged: (value) {
                                  setState(() {
                                    changePassword = value;
                                  });
                                },
                              ),
                              if (changePassword) ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: currentPassword,
                                  obscureText: true,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Current master password',
                                    helperText:
                                        'Leave empty only if this vault currently uses a key file without a password.',
                                    prefixIcon: Icon(AppIcons.lock),
                                  ),
                                  onChanged: (value) {
                                    currentPassword = value;
                                  },
                                  validator: (value) {
                                    if (!changePassword) {
                                      return null;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: newPassword,
                                  obscureText: true,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'New master password',
                                    prefixIcon: Icon(AppIcons.key),
                                  ),
                                  onChanged: (value) {
                                    newPassword = value;
                                  },
                                  validator: (value) {
                                    if (!changePassword) {
                                      return null;
                                    }
                                    if ((value ?? '').isEmpty) {
                                      return 'New password is required.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: confirmNewPassword,
                                  obscureText: true,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Confirm new password',
                                    prefixIcon: Icon(AppIcons.check),
                                  ),
                                  onChanged: (value) {
                                    confirmNewPassword = value;
                                  },
                                  validator: (value) {
                                    if (!changePassword) {
                                      return null;
                                    }
                                    if ((value ?? '') != newPassword) {
                                      return 'Passwords do not match.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                const _DatabaseSettingsInfoCallout(
                                  icon: AppIcons.lock,
                                  text:
                                      'Password changes affect the next unlock. Confirm the change before saving security credentials.',
                                ),
                              ],
                            ],
                          ),
                          if (pendingChanges.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _DatabaseSettingsChangesSummary(
                              changes: pendingChanges,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                actions: _adaptiveDialogActions(dialogContext, [
                  TextButton(
                    onPressed: () =>
                        VaultOperationScope.of(dialogContext).cancel(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: pendingChanges.isEmpty
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) {
                              return;
                            }
                            if (changePassword || keyFileChanged) {
                              final securityChanges = <String>[
                                if (changePassword) 'Master password',
                                if (keyFileChanged) 'Key file',
                              ];
                              final confirmed = await _showConfirmation(
                                dialogContext,
                                title: 'Confirm security changes',
                                body:
                                    'You are about to update: ${securityChanges.join(' + ')}. '
                                    'Use the new credentials to unlock this vault after saving.',
                                confirmLabel: 'Confirm and apply',
                              );
                              if (confirmed != ConfirmDecision.confirm) {
                                return;
                              }
                            }
                            if (!dialogContext.mounted) {
                              return;
                            }
                            VaultOperationScope.of(dialogContext).complete(
                              DatabaseSettingsResult(
                                fileName: databaseTitle.trim(),
                                keyFilePath: pendingSelectedKeyPath,
                                biometricProtectionEnabled: biometricEnabled,
                                changePassword: changePassword,
                                inactivityLockTimeoutSeconds: inactivityTimeout,
                                currentPassword: currentPassword,
                                newPassword: newPassword,
                              ),
                            );
                          },
                    child: const Text('Save changes'),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (shouldApply == null) {
      return;
    }

    final keyFileChanged =
        _normalizeKeyPathForComparison(persistedCurrentKeyPath) !=
        _normalizeKeyPathForComparison(shouldApply.keyFilePath);
    final requestedPasswordChange = shouldApply.changePassword;

    try {
      final result = await di
          .sl<VaultSessionCoordinator>()
          .updateDatabaseSettings(
            DatabaseSettingsUpdateRequest(
              currentDatabasePath: currentDatabasePath,
              fileName: shouldApply.fileName,
              keyFilePath: shouldApply.keyFilePath,
              biometricProtectionEnabled:
                  shouldApply.biometricProtectionEnabled,
              changePassword: shouldApply.changePassword,
              inactivityLockTimeoutSeconds:
                  shouldApply.inactivityLockTimeoutSeconds,
              currentPassword: shouldApply.currentPassword,
              newPassword: shouldApply.newPassword,
            ),
          );

      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.passwordChanged && keyFileChanged
                ? 'Database settings updated. Master password and key file changed successfully.'
                : result.passwordChanged
                ? 'Database settings updated. Master password changed successfully.'
                : keyFileChanged
                ? 'Database settings updated. Key file updated successfully.'
                : requestedPasswordChange
                ? 'Database settings updated.'
                : 'Database settings updated.',
          ),
        ),
      );
      await AppNavigation.pushFadeReplacement(
        context,
        VaultScreen(databasePath: result.databasePath),
      );
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Unable to update database settings.')),
        );
      }
    }
  }

  String _normalizeDatabaseFileName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.toLowerCase().endsWith('.kdbx') ? trimmed : '$trimmed.kdbx';
  }

  String? _normalizeKeyPathForComparison(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

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
          await _showDatabaseSettings(context);
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

class _DatabaseSettingsHeader extends StatelessWidget {
  const _DatabaseSettingsHeader({required this.databaseName});

  final String databaseName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              AppIcons.fileKey,
              size: 20,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  databaseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage vault name, lock behavior and unlock credentials.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.82,
                    ),
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

class _DatabaseSettingsSectionCard extends StatelessWidget {
  const _DatabaseSettingsSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DatabaseSettingsKeyFilePanel extends StatelessWidget {
  const _DatabaseSettingsKeyFilePanel({
    required this.selectedKeyPath,
    required this.onChange,
    required this.onRemove,
  });

  final String? selectedKeyPath;
  final VoidCallback onChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyPath = selectedKeyPath?.trim() ?? '';
    final hasKeyFile = keyPath.isNotEmpty;
    final title = hasKeyFile ? path.basename(keyPath) : 'No key file selected';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasKeyFile ? AppIcons.fileKey : AppIcons.file,
                size: 22,
                color: hasKeyFile
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasKeyFile
                          ? 'Stored in app key storage.'
                          : 'Add a key file for two-factor unlock with password + file.',
                      maxLines: hasKeyFile ? 1 : 2,
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
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackButtons = constraints.maxWidth < 360;
              final changeButton = OutlinedButton.icon(
                onPressed: onChange,
                icon: const Icon(AppIcons.edit),
                label: Text(hasKeyFile ? 'Change key file' : 'Select key file'),
              );
              final removeButton = OutlinedButton.icon(
                onPressed: onRemove,
                icon: const Icon(AppIcons.close),
                label: const Text('Remove key file'),
              );

              if (stackButtons) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    changeButton,
                    const SizedBox(height: 8),
                    removeButton,
                  ],
                );
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [changeButton, removeButton],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DatabaseSettingsInfoCallout extends StatelessWidget {
  const _DatabaseSettingsInfoCallout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatabaseSettingsChangesSummary extends StatelessWidget {
  const _DatabaseSettingsChangesSummary({required this.changes});

  final List<String> changes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.34),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  AppIcons.check,
                  size: 18,
                  color: colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Changes summary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...changes.map(
              (change) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        change,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Duplicate badge ──────────────────────────────────────────────────────────

class _DuplicateBadge extends StatelessWidget {
  const _DuplicateBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return child;
    final colorScheme = Theme.of(context).colorScheme;
    return Badge(
      label: Text('$count'),
      backgroundColor: colorScheme.error,
      textColor: colorScheme.onError,
      child: child,
    );
  }
}

// ─── Settings bottom sheet ────────────────────────────────────────────────────

class _VaultSettingsSheet extends StatelessWidget {
  const _VaultSettingsSheet({
    required this.state,
    required this.themeMode,
    required this.canConfigureAndroidAutofill,
    required this.canConfigureBrowserAutofill,
    required this.onSelect,
  });

  final VaultState state;
  final ThemeMode themeMode;
  final bool canConfigureAndroidAutofill;
  final bool canConfigureBrowserAutofill;
  final Future<void> Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.88;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      minimum: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      AppIcons.settings,
                      size: 17,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Settings',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Google Drive ──────────────────────────────────────
                    _SheetSection(
                      label: 'Google Drive',
                      icon: AppIcons.cloud,
                      iconColor: colorScheme.primary,
                      children: [
                        if (!state.isDriveConnected)
                          _SheetItem(
                            icon: AppIcons.cloud,
                            iconContainerColor: colorScheme.primaryContainer
                                .withValues(alpha: 0.6),
                            iconColor: colorScheme.onPrimaryContainer,
                            label: 'Connect Google Drive',
                            subtitle: 'Enable cloud backup and sync',
                            onTap: () => onSelect('connect'),
                          )
                        else if (!state.isDriveLinked)
                          _SheetItem(
                            icon: AppIcons.linkSimple,
                            iconContainerColor: colorScheme.primaryContainer
                                .withValues(alpha: 0.6),
                            iconColor: colorScheme.onPrimaryContainer,
                            label: 'Link database to Drive',
                            subtitle: 'Choose a .kdbx file to sync with',
                            onTap: () => onSelect('link'),
                          ),
                        _SheetToggleItem(
                          icon: AppIcons.sync,
                          iconContainerColor:
                              state.isDriveConnected && state.isDriveLinked
                              ? colorScheme.secondaryContainer.withValues(
                                  alpha: 0.7,
                                )
                              : colorScheme.surfaceContainerHighest,
                          iconColor:
                              state.isDriveConnected && state.isDriveLinked
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                          label: 'Auto-sync',
                          subtitle:
                              state.isDriveConnected && state.isDriveLinked
                              ? 'Sync automatically when the vault changes'
                              : 'Connect and link Drive first',
                          value: state.autoSyncEnabled,
                          enabled:
                              state.isDriveConnected && state.isDriveLinked,
                          onChanged: (_) => onSelect('toggleAutoSync'),
                        ),
                        if (state.isDriveConnected)
                          _SheetItem(
                            icon: AppIcons.cloudOff,
                            iconContainerColor: colorScheme.errorContainer
                                .withValues(alpha: 0.42),
                            iconColor: colorScheme.error,
                            label: 'Disconnect Google Drive',
                            labelColor: colorScheme.error,
                            onTap: () => onSelect('disconnect'),
                          ),
                      ],
                    ),
                    const _SheetDivider(),

                    // ── Vault ─────────────────────────────────────────────
                    _SheetSection(
                      label: 'Vault',
                      icon: AppIcons.key,
                      iconColor: colorScheme.secondary,
                      children: [
                        _SheetItem(
                          icon: AppIcons.settings,
                          iconContainerColor: colorScheme.secondaryContainer
                              .withValues(alpha: 0.6),
                          iconColor: colorScheme.onSecondaryContainer,
                          label: 'Database settings',
                          subtitle: 'Password, key file, biometrics',
                          onTap: () => onSelect('databaseSettings'),
                        ),
                        _SheetItem(
                          icon: AppIcons.folderCopy,
                          iconContainerColor: colorScheme.secondaryContainer
                              .withValues(alpha: 0.6),
                          iconColor: colorScheme.onSecondaryContainer,
                          label: 'Change database',
                          subtitle: 'Switch to a different .kdbx file',
                          onTap: () => onSelect('changeDatabase'),
                        ),
                        _SheetItem(
                          icon: AppIcons.lock,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.6),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Lock vault',
                          subtitle: 'Require password to access again',
                          onTap: () => onSelect('lockVault'),
                        ),
                      ],
                    ),
                    const _SheetDivider(),

                    // ── Tools ─────────────────────────────────────────────
                    _SheetSection(
                      label: 'Tools',
                      icon: AppIcons.fileText,
                      iconColor: colorScheme.tertiary,
                      children: [
                        _SheetItem(
                          icon: AppIcons.import,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.55),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Import from CSV',
                          subtitle: 'Add records from a spreadsheet export',
                          onTap: () => onSelect('importCsv'),
                        ),
                        _SheetItem(
                          icon: AppIcons.export,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.55),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Export database backup',
                          subtitle: 'Save a copy of the .kdbx file',
                          onTap: () => onSelect('exportDatabaseBackup'),
                        ),
                        _SheetItem(
                          icon: AppIcons.fileKey,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.55),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Export key file',
                          subtitle: 'Back up the key file to a safe location',
                          onTap: () => onSelect('exportKeyFile'),
                        ),
                        _SheetItem(
                          icon: AppIcons.delete,
                          iconContainerColor:
                              colorScheme.surfaceContainerHighest,
                          iconColor: colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                          label: 'Recycle bin',
                          subtitle: 'View and restore deleted records',
                          onTap: () => onSelect('recycleBin'),
                        ),
                        _SheetItem(
                          icon: AppIcons.copy,
                          iconContainerColor: state.duplicateGroupCount > 0
                              ? colorScheme.tertiaryContainer.withValues(
                                  alpha: 0.6,
                                )
                              : colorScheme.surfaceContainerHighest,
                          iconColor: state.duplicateGroupCount > 0
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurface.withValues(alpha: 0.7),
                          label: 'Manage duplicates',
                          subtitle: state.duplicateGroupCount > 0
                              ? '${state.duplicateGroupCount} group${state.duplicateGroupCount == 1 ? '' : 's'} detected'
                              : 'Merge or remove duplicate entries',
                          onTap: () => onSelect('manageDuplicates'),
                        ),
                        if (canConfigureAndroidAutofill)
                          _SheetItem(
                            icon: AppIcons.fingerprint,
                            iconContainerColor: colorScheme.secondaryContainer
                                .withValues(alpha: 0.6),
                            iconColor: colorScheme.onSecondaryContainer,
                            label: 'Android autofill',
                            subtitle: 'Fill passwords in apps and browsers',
                            onTap: () => onSelect('androidAutofill'),
                          ),
                        if (canConfigureBrowserAutofill)
                          _SheetItem(
                            icon: AppIcons.globe,
                            iconContainerColor: colorScheme.secondaryContainer
                                .withValues(alpha: 0.6),
                            iconColor: colorScheme.onSecondaryContainer,
                            label: 'Desktop browser extension',
                            subtitle:
                                'Install and connect the desktop browser host',
                            onTap: () => onSelect('browserSetup'),
                          ),
                      ],
                    ),
                    const _SheetDivider(),

                    // ── Appearance ────────────────────────────────────────
                    _SheetSection(
                      label: 'Appearance',
                      icon: AppIcons.sun,
                      iconColor: colorScheme.tertiary,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: _ThemePicker(
                            themeMode: themeMode,
                            onSelect: (mode) {
                              switch (mode) {
                                case ThemeMode.system:
                                  onSelect('themeSystem');
                                case ThemeMode.light:
                                  onSelect('themeLight');
                                case ThemeMode.dark:
                                  onSelect('themeDark');
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: colorScheme.onSurface.withValues(alpha: 0.52),
                ),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SheetDivider extends StatelessWidget {
  const _SheetDivider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
  }
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({
    required this.icon,
    required this.iconContainerColor,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.labelColor,
    this.onTap,
  });

  final IconData icon;
  final Color iconContainerColor;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconContainerColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 17, color: iconColor),
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: labelColor,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.58),
              ),
            )
          : null,
    );
  }
}

class _SheetToggleItem extends StatelessWidget {
  const _SheetToggleItem({
    required this.icon,
    required this.iconContainerColor,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconContainerColor;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveAlpha = enabled ? 1.0 : 0.5;

    return SwitchListTile.adaptive(
      value: value,
      onChanged: enabled ? onChanged : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      secondary: Opacity(
        opacity: effectiveAlpha,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconContainerColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
      ),
      title: Opacity(
        opacity: effectiveAlpha,
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      subtitle: subtitle != null
          ? Opacity(
              opacity: effectiveAlpha,
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            )
          : null,
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.themeMode, required this.onSelect});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget option(ThemeMode mode, IconData icon, String label) {
      final selected = themeMode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.76)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outlineVariant.withValues(alpha: 0.55),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(ThemeMode.system, AppIcons.desktop, 'System'),
        const SizedBox(width: 8),
        option(ThemeMode.light, AppIcons.sun, 'Light'),
        const SizedBox(width: 8),
        option(ThemeMode.dark, AppIcons.moon, 'Dark'),
      ],
    );
  }
}
