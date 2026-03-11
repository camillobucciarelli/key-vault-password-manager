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
    required this.onOpenRecycleBin,
    required this.onChangeDatabase,
  });

  final VaultState state;
  final bool canConfigureAndroidAutofill;
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

    final currentDatabaseFile = File(currentDatabasePath);
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
        .sl<GetBiometricProtectionEnabledUseCase>()();
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
                        TextFormField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Database file name',
                            prefixIcon: Icon(AppIcons.file),
                          ),
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
                        const SizedBox(height: 4),
                        ListTile(
                          dense: true,
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
                              Tooltip(
                                message: 'Change key file',
                                ignorePointer: true,
                                child: IconButton(
                                  onPressed: () async {
                                    final picked = await FilePicker.platform
                                        .pickFiles(allowMultiple: false);
                                    final selected = picked?.files.single.path;
                                    if (selected == null || selected.isEmpty) {
                                      return;
                                    }
                                    setState(() {
                                      selectedKeyPath = selected;
                                    });
                                  },
                                  icon: const Icon(AppIcons.edit),
                                ),
                              ),
                              Tooltip(
                                message: 'Remove key file',
                                ignorePointer: true,
                                child: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      selectedKeyPath = null;
                                    });
                                  },
                                  icon: const Icon(AppIcons.close),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
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
                          const SizedBox(height: 8),
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
                        ],
                        const SizedBox(height: 8),
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
                  onPressed: () {
                    if (!formKey.currentState!.validate()) {
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

    try {
      final updatedName = titleCtrl.text.trim().toLowerCase().endsWith('.kdbx')
          ? titleCtrl.text.trim()
          : '${titleCtrl.text.trim()}.kdbx';
      final parentDir = path.dirname(currentDatabasePath);
      final targetPath = path.join(parentDir, updatedName);
      var effectivePath = currentDatabasePath;

      if (targetPath != currentDatabasePath) {
        if (await File(targetPath).exists()) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('A database file with this name already exists.'),
            ),
          );
          titleCtrl.dispose();
          return;
        }
        await currentDatabaseFile.rename(targetPath);
        effectivePath = targetPath;
      }

      await di.sl<SaveSelectedDatabasePathUseCase>()(effectivePath);
      await di.sl<AddRecentDatabasePathUseCase>()(effectivePath);
      await di.sl<SaveSelectedKeyFilePathUseCase>()(selectedKeyPath);
      await di.sl<SetBiometricProtectionEnabledUseCase>()(biometricEnabled);

      var passwordChanged = false;
      if (changePassword) {
        await di.sl<VaultKdbxService>().changeMasterPassword(
          databasePath: effectivePath,
          currentPassword: currentPasswordCtrl.text,
          keyFilePath: selectedKeyPath,
          newPassword: newPasswordCtrl.text,
        );
        await di.sl<SecureDataSource>().saveMasterPassword(
          newPasswordCtrl.text,
        );
        passwordChanged = true;
      }

      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            passwordChanged
                ? 'Database settings updated. Master password changed successfully.'
                : 'Database settings updated.',
          ),
        ),
      );
      await AppNavigation.pushFadeReplacement(
        context,
        VaultScreen(databasePath: effectivePath),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to update database settings.')),
      );
    } finally {
      titleCtrl.dispose();
      currentPasswordCtrl.dispose();
      newPasswordCtrl.dispose();
      confirmNewPasswordCtrl.dispose();
    }
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
          ? 'Link this database'
          : 'Connect Google Drive',
      ignorePointer: true,
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
