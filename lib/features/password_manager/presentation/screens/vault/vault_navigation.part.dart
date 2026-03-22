part of '../vault_screen.dart';

class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip({
    required this.state,
    required this.onRefresh,
    required this.onOpenRecycleBin,
    required this.onChangeDatabase,
  });

  final VaultState state;
  final VoidCallback onRefresh;
  final VoidCallback onOpenRecycleBin;
  final Future<void> Function() onChangeDatabase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final compactActions = MediaQuery.sizeOf(context).width < 390;
    final canConfigureAndroidAutofill =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final canConfigureBrowserAutofill =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
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
    required this.onChangeDatabase,
  });

  final VaultState state;
  final bool canConfigureAndroidAutofill;
  final bool canConfigureBrowserAutofill;
  final VoidCallback onOpenRecycleBin;
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
    final savePath = await FilePicker.platform.saveFile(
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
    final keyPath = await di.sl<GetSelectedKeyFilePathUseCase>()();
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
    final savePath = await FilePicker.platform.saveFile(
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

    final titleCtrl = TextEditingController(
      text: path.basenameWithoutExtension(currentDatabasePath),
    );
    final currentKeyPath = await di.sl<GetSelectedKeyFilePathUseCase>()();
    if (!context.mounted) {
      titleCtrl.dispose();
      return;
    }
    var selectedKeyPath = currentKeyPath;
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmNewPasswordCtrl = TextEditingController();
    var changePassword = false;
    var biometricEnabled = await di
        .sl<VaultSessionCoordinator>()
        .getBiometricProtectionEnabledForPath(
          databasePath: currentDatabasePath,
        );
    final initialBiometricEnabled = biometricEnabled;
    final initialFileName = path.basename(currentDatabasePath);
    final normalizedCurrentKeyPath = _normalizeKeyPathForComparison(
      currentKeyPath,
    );
    if (!context.mounted) {
      titleCtrl.dispose();
      currentPasswordCtrl.dispose();
      newPasswordCtrl.dispose();
      confirmNewPasswordCtrl.dispose();
      return;
    }
    final formKey = GlobalKey<FormState>();

    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final normalizedSelectedKeyPath = _normalizeKeyPathForComparison(
              selectedKeyPath,
            );
            final keyFileChanged =
                normalizedSelectedKeyPath != normalizedCurrentKeyPath;
            final fileNameChanged =
                _normalizeDatabaseFileName(titleCtrl.text) != initialFileName;
            final biometricChanged =
                biometricEnabled != initialBiometricEnabled;
            final pendingChanges = <String>[
              if (fileNameChanged) 'Database file name',
              if (biometricChanged) 'Biometric protection',
              if (keyFileChanged) 'Key file',
              if (changePassword) 'Master password',
            ];

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
                        Text(
                          'General',
                          style: Theme.of(dialogContext).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Database file name',
                            prefixIcon: Icon(AppIcons.file),
                          ),
                          onChanged: (_) => setState(() {}),
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
                        const SizedBox(height: 10),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable biometric protection'),
                          value: biometricEnabled,
                          onChanged: (value) {
                            setState(() {
                              biometricEnabled = value;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Key file',
                          style: Theme.of(dialogContext).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(AppIcons.fileKey),
                          title: Text(
                            selectedKeyPath == null ||
                                    selectedKeyPath!.trim().isEmpty
                                ? 'No key file selected'
                                : path.basename(selectedKeyPath!),
                          ),
                          subtitle: selectedKeyPath == null
                              ? null
                              : Text(
                                  selectedKeyPath!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final usesManagedStorage =
                                      !kIsWeb &&
                                      (defaultTargetPlatform ==
                                              TargetPlatform.android ||
                                          defaultTargetPlatform ==
                                              TargetPlatform.iOS ||
                                          defaultTargetPlatform ==
                                              TargetPlatform.macOS);
                                  if (usesManagedStorage) {
                                    final currentSelectedPath = selectedKeyPath;
                                    final result =
                                        await showInternalKeyFileManagerDialog(
                                          dialogContext,
                                          initiallySelectedPath:
                                              currentSelectedPath,
                                        );
                                    if (result == null) {
                                      return;
                                    }
                                    setState(() {
                                      if (result.selectedPath != null) {
                                        selectedKeyPath = result.selectedPath;
                                        return;
                                      }
                                      if (result.currentSelectionDeleted &&
                                          currentSelectedPath != null &&
                                          currentSelectedPath
                                              .trim()
                                              .isNotEmpty) {
                                        selectedKeyPath = null;
                                      }
                                    });
                                    return;
                                  }

                                  final picked = await FilePicker.platform
                                      .pickFiles(
                                        allowMultiple: false,
                                        withData: false,
                                      );
                                  final selectedFile = picked?.files.single;
                                  if (selectedFile == null) {
                                    return;
                                  }

                                  final selectedPath = selectedFile.path;
                                  if (selectedPath == null ||
                                      selectedPath.isEmpty) {
                                    return;
                                  }

                                  setState(() {
                                    selectedKeyPath = selectedPath;
                                  });
                                },
                                icon: const Icon(AppIcons.edit),
                                label: const Text('Change key file'),
                              ),
                              OutlinedButton.icon(
                                onPressed: selectedKeyPath == null
                                    ? null
                                    : () {
                                        setState(() {
                                          selectedKeyPath = null;
                                        });
                                      },
                                icon: const Icon(AppIcons.close),
                                label: const Text('Remove key file'),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Changing key file updates the unlock credentials for this vault. Keep a backup in a separate location.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Master password',
                          style: Theme.of(dialogContext).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Change master password'),
                          subtitle: const Text(
                            'Re-encrypts the current database with a new password.',
                          ),
                          value: changePassword,
                          onChanged: (value) {
                            setState(() {
                              changePassword = value;
                            });
                          },
                        ),
                        if (changePassword) ...[
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: currentPasswordCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Current master password',
                            ),
                            validator: (value) {
                              if (!changePassword) {
                                return null;
                              }
                              if ((value ?? '').isEmpty) {
                                return 'Current password is required.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: newPasswordCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'New master password',
                            ),
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
                            controller: confirmNewPasswordCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Confirm new password',
                            ),
                            validator: (value) {
                              if (!changePassword) {
                                return null;
                              }
                              if ((value ?? '') != newPasswordCtrl.text) {
                                return 'Passwords do not match.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'After saving, use the new master password the next time you unlock this vault.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (pendingChanges.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                dialogContext,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Changes to apply: ${pendingChanges.join(', ')}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          'Google Drive sync stores only the .kdbx database. Keep key file backups in a separate location.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: _adaptiveDialogActions(dialogContext, [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }
                    if (changePassword) {
                      final securityChanges = <String>[
                        'Master password',
                        if (keyFileChanged) 'Key file',
                      ];
                      final confirmed = await showDialog<bool>(
                        context: dialogContext,
                        builder: (confirmContext) {
                          return AlertDialog(
                            title: const Text('Confirm security changes'),
                            content: Text(
                              'You are about to update: ${securityChanges.join(' + ')}. '
                              'Use the new credentials to unlock this vault after saving.',
                            ),
                            actions: _adaptiveDialogActions(confirmContext, [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(confirmContext).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(confirmContext).pop(true),
                                child: const Text('Confirm and apply'),
                              ),
                            ]),
                          );
                        },
                      );
                      if (confirmed != true) {
                        return;
                      }
                    }
                    if (!dialogContext.mounted) {
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Save'),
                ),
              ]),
            );
          },
        );
      },
    );

    if (!context.mounted) {
      titleCtrl.dispose();
      currentPasswordCtrl.dispose();
      newPasswordCtrl.dispose();
      confirmNewPasswordCtrl.dispose();
      return;
    }

    if (shouldApply != true) {
      titleCtrl.dispose();
      currentPasswordCtrl.dispose();
      newPasswordCtrl.dispose();
      confirmNewPasswordCtrl.dispose();
      return;
    }

    final keyFileChanged =
        _normalizeKeyPathForComparison(currentKeyPath) !=
        _normalizeKeyPathForComparison(selectedKeyPath);
    final requestedPasswordChange = changePassword;

    try {
      final result = await di
          .sl<VaultSessionCoordinator>()
          .updateDatabaseSettings(
            DatabaseSettingsUpdateRequest(
              currentDatabasePath: currentDatabasePath,
              fileName: titleCtrl.text.trim(),
              keyFilePath: selectedKeyPath,
              biometricProtectionEnabled: biometricEnabled,
              changePassword: changePassword,
              currentPassword: currentPasswordCtrl.text,
              newPassword: newPasswordCtrl.text,
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
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to update database settings. $e')),
      );
    } finally {
      titleCtrl.dispose();
      currentPasswordCtrl.dispose();
      newPasswordCtrl.dispose();
      confirmNewPasswordCtrl.dispose();
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
        case 'changeDatabase':
          await onChangeDatabase();
          break;
        case 'importCsv':
          await _startCsvImportFlow(context);
          break;
        case 'lockVault':
          final databasePath = state.databasePath;
          if (databasePath.trim().isNotEmpty) {
            unawaited(
              di.sl<VaultSessionCoordinator>().lockVault(
                currentDatabasePath: databasePath,
              ),
            );
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
          await AppNavigation.pushFade(context, const BrowserSetupScreen());
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
              final maxSheetHeight =
                  MediaQuery.sizeOf(sheetContext).height * 0.82;
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
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSheetHeight),
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
                                onTap: () => closeAndSelect('changeDatabase'),
                                title: const Text('Change database'),
                              ),
                              ListTile(
                                onTap: () => closeAndSelect('databaseSettings'),
                                title: const Text('Database settings'),
                              ),
                              ListTile(
                                onTap: () => closeAndSelect('lockVault'),
                                title: const Text('Lock vault'),
                              ),
                              ListTile(
                                onTap: () =>
                                    closeAndSelect('exportDatabaseBackup'),
                                title: const Text('Export database backup'),
                              ),
                              ListTile(
                                onTap: () => closeAndSelect('exportKeyFile'),
                                title: const Text('Export key file'),
                              ),
                              ListTile(
                                onTap: () => closeAndSelect('importCsv'),
                                title: const Text('Import from CSV'),
                              ),
                              if (canConfigureAndroidAutofill)
                                ListTile(
                                  onTap: () =>
                                      closeAndSelect('androidAutofill'),
                                  title: const Text('Autofill Android'),
                                ),
                              if (canConfigureBrowserAutofill)
                                ListTile(
                                  onTap: () => closeAndSelect('browserSetup'),
                                  title: const Text('Connetti Browser'),
                                  subtitle: const Text(
                                    'Chrome, Brave, Edge — One-click autofill',
                                  ),
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
                ),
              );
            },
          );
        },
        icon: const _SyncStripActionIcon(icon: AppIcons.more),
      ),
    );
  }
}
