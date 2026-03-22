import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/utils/mobile_file_storage.dart';
import '../../../../../injection_container.dart' as di;
import '../../domain/repositories/database_sync_repository.dart';
import '../../domain/models/database_dedup_result.dart';
import '../../domain/usecases/connect_google_account_usecase.dart';
import '../../domain/usecases/get_drive_connection_status_usecase.dart';
import '../../domain/usecases/list_drive_remote_files_usecase.dart';
import '../../domain/models/drive_remote_file.dart';
import '../bloc/database_selection/database_selection_bloc.dart';
import '../bloc/database_selection/database_selection_event.dart';
import '../bloc/database_selection/database_selection_state.dart';
import 'coordinators/database_flow_coordinator.dart';
import '../widgets/create_database_dialog.dart';
import '../widgets/database/database_action_tile.dart';
import '../widgets/database/recent_databases_section.dart';
import '../utils/platform_utils.dart';

class DatabaseSelectionScreen extends StatelessWidget {
  const DatabaseSelectionScreen({super.key});

  static const DatabaseFlowCoordinator _flowCoordinator =
      DatabaseFlowCoordinator();

  Future<void> _openFromGoogleDrive(BuildContext context) async {
    if (kIsWeb) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open from Google Drive is currently desktop/mobile only.',
          ),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    var progressVisible = false;

    void showProgress(String message) {
      progressVisible = true;
      _showBlockingProgress(context, message);
    }

    void hideProgressIfNeeded() {
      if (!progressVisible || !context.mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      progressVisible = false;
    }

    showProgress('Connecting to Google Drive...');

    try {
      final isConnected = await di.sl<GetDriveConnectionStatusUseCase>()();
      if (!isConnected) {
        await di.sl<ConnectGoogleAccountUseCase>()();
      }

      final files = await di.sl<ListDriveRemoteFilesUseCase>()();
      hideProgressIfNeeded();

      if (!context.mounted) {
        return;
      }

      if (files.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No .kdbx files found in your Google Drive.'),
          ),
        );
        return;
      }

      final selected = await _showDriveFilePickerDialog(context, files);
      if (selected == null || !context.mounted) {
        return;
      }

      var overwriteExisting = false;
      if (isManagedStoragePlatform) {
        final exists = await MobileFileStorage.fileExistsInAppDirectory(
          fileName: selected.name,
          subdirectory: 'databases',
        );
        if (!context.mounted) {
          return;
        }
        if (exists) {
          final confirm = await _showOverwriteDatabaseDialog(
            context,
            selected.name,
          );
          if (confirm != true || !context.mounted) {
            return;
          }
          overwriteExisting = true;
        }
      }

      String? savePath;
      if (isManagedStoragePlatform) {
        savePath = selected.name;
      } else {
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save a local copy of the Drive database',
          fileName: selected.name,
          type: FileType.custom,
          allowedExtensions: ['kdbx'],
        );

        if (savePath == null || savePath.trim().isEmpty) {
          return;
        }

        if (!savePath.toLowerCase().endsWith('.kdbx')) {
          savePath = '$savePath.kdbx';
        }
      }

      if (!context.mounted) {
        return;
      }

      showProgress('Downloading database from Drive...');
      final bytes = await di.sl<DatabaseSyncRepository>().downloadRemoteFile(
        selected.id,
      );
      final localPath = isManagedStoragePlatform
          ? await MobileFileStorage.saveBytesToAppDirectory(
              bytes: bytes,
              fileName: p.basename(savePath),
              subdirectory: 'databases',
              overwriteIfExists: overwriteExisting,
            )
          : savePath;

      if (!isManagedStoragePlatform) {
        await File(localPath).writeAsBytes(bytes, flush: true);
      }
      hideProgressIfNeeded();

      if (!context.mounted) {
        return;
      }

      if (isManagedStoragePlatform) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Database saved to app internal storage.'),
          ),
        );
      }

      context.read<DatabaseSelectionBloc>().add(
        SelectDriveDatabaseLocalCopy(
          localPath: localPath,
          remoteFileId: selected.id,
        ),
      );
    } catch (e) {
      hideProgressIfNeeded();
      messenger.showSnackBar(
        SnackBar(content: Text(_buildDriveOpenErrorMessage(e))),
      );
    }
  }

  String _buildDriveOpenErrorMessage(Object error) {
    final message = error.toString();
    final normalized = message.toLowerCase();

    if (normalized.contains('google sign-in cancelled')) {
      return 'Google sign-in was cancelled during authorization. Please try again and grant Drive permissions.';
    }
    if (normalized.contains(
      'google account selected, but drive permission was not granted',
    )) {
      return 'Account selected, but Drive permission was not granted. Please try again and accept the requested permissions.';
    }
    if (normalized.contains('android google sign-in is not configured')) {
      return 'Android Google Sign-In is not configured. Check GOOGLE_ANDROID_SERVER_CLIENT_ID.';
    }
    if (normalized.contains('ios google sign-in is not configured')) {
      return 'iOS Google Sign-In is not configured. Check GOOGLE_MOBILE_CLIENT_ID.';
    }
    if (normalized.contains('authorization was not granted')) {
      return 'Google Drive permission was not granted. Enable Drive access and try again.';
    }
    if (normalized.contains('authorization needs to be renewed') ||
        normalized.contains('authorization is outdated') ||
        normalized.contains('google account not connected')) {
      return 'Google Drive session expired or unavailable. Tap "Open from Google Drive" again and complete reconnection.';
    }
    return 'Unable to open database from Google Drive. $message';
  }

  void _showBlockingProgress(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(message)),
            ],
          ),
        );
      },
    );
  }

  Future<DriveRemoteFile?> _showDriveFilePickerDialog(
    BuildContext context,
    List<DriveRemoteFile> files,
  ) {
    var selectedId = files.first.id;
    return showDialog<DriveRemoteFile>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Select Drive database'),
              insetPadding: _dialogInsetPadding(dialogContext),
              contentPadding: _dialogContentPadding(dialogContext),
              actionsOverflowDirection: VerticalDirection.down,
              actionsOverflowButtonSpacing: 8,
              content: SizedBox(
                width: _dialogContentWidth(dialogContext, 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Choose a .kdbx file from Google Drive.'),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: files.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, index) {
                          final file = files[index];
                          final selected = selectedId == file.id;
                          final isDark =
                              Theme.of(context).brightness == Brightness.dark;
                          final modifiedAt = file.modifiedTime == null
                              ? 'Unknown date'
                              : _formatDriveFileDate(file.modifiedTime!);

                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() {
                                selectedId = file.id;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                ),
                                color: selected
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer.withValues(
                                        alpha: isDark ? 0.28 : 0.52,
                                      )
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(
                                            alpha: isDark ? 0.24 : 0.62,
                                          ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    AppIcons.file,
                                    size: 18,
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          file.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: selected
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Modified: $modifiedAt',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    selected
                                        ? AppIcons.check
                                        : AppIcons.chevronRight,
                                    size: selected ? 18 : 16,
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: _adaptiveDialogActions(dialogContext, [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final selected = files.firstWhere(
                      (file) => file.id == selectedId,
                    );
                    Navigator.of(dialogContext).pop(selected);
                  },
                  child: const Text('Continue'),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  String _formatDriveFileDate(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day-$month-$year $hour:$minute';
  }

  double _dialogContentWidth(BuildContext context, double preferredWidth) {
    final viewport = MediaQuery.sizeOf(context).width;
    final availableWidth = viewport - 56;
    if (availableWidth < 280) {
      return viewport - 24;
    }
    return availableWidth < preferredWidth ? availableWidth : preferredWidth;
  }

  bool _isVeryCompactDialogWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 340;
  }

  EdgeInsets _dialogInsetPadding(BuildContext context) {
    if (_isVeryCompactDialogWidth(context)) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 20);
    }
    return const EdgeInsets.symmetric(horizontal: 20, vertical: 24);
  }

  EdgeInsets _dialogContentPadding(BuildContext context) {
    if (_isVeryCompactDialogWidth(context)) {
      return const EdgeInsets.fromLTRB(12, 10, 12, 6);
    }
    return const EdgeInsets.fromLTRB(20, 18, 20, 12);
  }

  List<Widget> _adaptiveDialogActions(
    BuildContext context,
    List<Widget> actions,
  ) {
    if (MediaQuery.sizeOf(context).width >= 360) {
      return actions;
    }

    return actions
        .map((action) => SizedBox(width: double.infinity, child: action))
        .toList(growable: false);
  }

  Future<void> _onOpenRecentDatabase(BuildContext context, String path) async {
    context.read<DatabaseSelectionBloc>().add(OpenRecentDatabase(path));
  }

  Future<void> _onExportRecentDatabase(
    BuildContext context,
    String path,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    if (kIsWeb) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Export is currently available on desktop/mobile only.',
          ),
        ),
      );
      return;
    }

    final source = File(path);
    if (!await source.exists()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Selected database file was not found.')),
      );
      return;
    }

    final defaultName = p.basename(path);
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

    try {
      await source.copy(resolvedPath);
      messenger.showSnackBar(
        const SnackBar(content: Text('Database backup exported.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to export selected database.')),
      );
    }
  }

  Future<void> _onSelectExistingDatabase(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kdbx'],
      withData: kIsWeb || isManagedStoragePlatform,
    );

    if (result == null || !context.mounted) {
      return;
    }

    final selectedFile = result.files.single;
    final selectedPath = selectedFile.path;
    final fallbackName = selectedPath == null || selectedPath.trim().isEmpty
        ? 'database.kdbx'
        : p.basename(selectedPath);
    final fileName = selectedFile.name.trim().isEmpty
        ? fallbackName
        : selectedFile.name;

    var overwriteExisting = false;
    if (isManagedStoragePlatform) {
      final exists = await MobileFileStorage.fileExistsInAppDirectory(
        fileName: fileName,
        subdirectory: 'databases',
      );
      if (!context.mounted) {
        return;
      }
      if (exists) {
        final confirm = await _showOverwriteDatabaseDialog(context, fileName);
        if (confirm != true || !context.mounted) {
          return;
        }
        overwriteExisting = true;
      }
    }

    if (!context.mounted) {
      return;
    }

    context.read<DatabaseSelectionBloc>().add(
      SelectExistingDatabase(
        fileName: fileName,
        selectedPath: selectedPath,
        selectedBytes: selectedFile.bytes,
        overwriteExisting: overwriteExisting,
      ),
    );
  }

  Future<void> _onCreateDatabase(BuildContext context) async {
    final credentials = await showDialog<CreateDatabaseCredentials>(
      context: context,
      builder: (_) => const CreateDatabaseDialog(),
    );
    if (credentials != null && context.mounted) {
      context.read<DatabaseSelectionBloc>().add(
        CreateNewDatabase(
          databaseFileName: credentials.databaseFileName,
          password: credentials.password,
          keyFilePath: credentials.keyFilePath,
          biometricProtectionEnabled: credentials.biometricProtectionEnabled,
          generateKeyFile: credentials.generateKeyFile,
          generatedKeyFilePath: credentials.generatedKeyFilePath,
        ),
      );
    }
  }

  Future<void> _onRemoveRecentDatabase(
    BuildContext context,
    String path,
  ) async {
    final mode = await _showRecentDatabaseRemovalDialog(context, path);
    if (mode == null || !context.mounted) {
      return;
    }

    if (mode == RecentDatabaseRemovalMode.removeAndDeleteFile) {
      final confirmed = await _showDeleteFileConfirmationDialog(context, path);
      if (confirmed != true || !context.mounted) {
        return;
      }
    }

    context.read<DatabaseSelectionBloc>().add(
      RemoveRecentDatabase(path: path, mode: mode),
    );
  }

  Future<RecentDatabaseRemovalMode?> _showRecentDatabaseRemovalDialog(
    BuildContext context,
    String path,
  ) {
    final fileName = p.basename(path);
    return showDialog<RecentDatabaseRemovalMode>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove recent database'),
          insetPadding: _dialogInsetPadding(dialogContext),
          contentPadding: _dialogContentPadding(dialogContext),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          content: Text('Choose how to remove "$fileName".'),
          actions: _adaptiveDialogActions(dialogContext, [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(RecentDatabaseRemovalMode.removeOnly),
              child: const Text('Remove from list'),
            ),
            FilledButton.tonal(
              onPressed: kIsWeb
                  ? null
                  : () => Navigator.of(
                      dialogContext,
                    ).pop(RecentDatabaseRemovalMode.removeAndDeleteFile),
              child: const Text('Remove and delete file'),
            ),
          ]),
        );
      },
    );
  }

  Future<bool?> _showDeleteFileConfirmationDialog(
    BuildContext context,
    String path,
  ) {
    final fileName = p.basename(path);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete file?'),
          insetPadding: _dialogInsetPadding(dialogContext),
          contentPadding: _dialogContentPadding(dialogContext),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          content: Text(
            'This will try to permanently delete "$fileName" from disk.',
          ),
          actions: _adaptiveDialogActions(dialogContext, [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete file'),
            ),
          ]),
        );
      },
    );
  }

  Future<bool?> _showOverwriteDatabaseDialog(
    BuildContext context,
    String fileName,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Replace existing database?'),
          insetPadding: _dialogInsetPadding(dialogContext),
          contentPadding: _dialogContentPadding(dialogContext),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          content: Text(
            'A database named "$fileName" already exists in app storage. Do you want to replace it?',
          ),
          actions: _adaptiveDialogActions(dialogContext, [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Replace'),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildRecentDatabasesSection(
    BuildContext context,
    List<String> recentDatabasePaths,
  ) {
    return RecentDatabasesSection(
      recentDatabasePaths: recentDatabasePaths,
      onOpen: (path) => _onOpenRecentDatabase(context, path),
      onExport: (path) => _onExportRecentDatabase(context, path),
      onRemove: (path) => _onRemoveRecentDatabase(context, path),
    );
  }

  Widget _buildPrimaryActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DatabaseActionTile(
          icon: AppIcons.folderOpen,
          title: 'Open existing database',
          subtitle: 'Choose a .kdbx file from your device',
          onTap: () => _onSelectExistingDatabase(context),
        ),
        const SizedBox(height: 10),
        DatabaseActionTile(
          icon: AppIcons.add,
          title: 'Create new database',
          subtitle: 'Create a protected vault with password and key file',
          onTap: () => _onCreateDatabase(context),
        ),
        const SizedBox(height: 10),
        DatabaseActionTile(
          icon: AppIcons.cloud,
          title: 'Open from Google Drive',
          subtitle: 'Download a .kdbx and open a local copy',
          onTap: () => _openFromGoogleDrive(context),
        ),
      ],
    );
  }

  Future<void> _handleDuplicateDecisionPrompt(
    BuildContext context,
    DatabaseSelectionDuplicateDecisionRequired state,
  ) async {
    final decision = await showDialog<DatabaseDuplicateResolution>(
      context: context,
      builder: (dialogContext) {
        final imported = state.duplicatePrompt.imported.fileName;
        final existing = state.duplicatePrompt.existingRecord.displayName;
        return AlertDialog(
          title: const Text('Duplicate database detected'),
          content: Text(
            'Imported: $imported\nExisting: $existing\n\nChoose how to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(DatabaseDuplicateResolution.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(DatabaseDuplicateResolution.keepBoth),
              child: const Text('Keep both'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(DatabaseDuplicateResolution.replaceExisting),
              child: const Text('Replace existing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(DatabaseDuplicateResolution.useExisting),
              child: const Text('Use existing'),
            ),
          ],
        );
      },
    );

    if (!context.mounted || decision == null) {
      return;
    }

    context.read<DatabaseSelectionBloc>().add(
      ResolveDuplicateDecision(decision),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = viewportWidth < 420
        ? 16.0
        : (viewportWidth - 600) * 0.5;
    final cardPadding = viewportWidth < 420 ? 18.0 : 24.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(gradient: AppBackgrounds.gradient(context)),
        child: BlocConsumer<DatabaseSelectionBloc, DatabaseSelectionState>(
          listener: (context, state) {
            if (state is DatabaseSelectionDuplicateDecisionRequired) {
              _handleDuplicateDecisionPrompt(context, state);
              return;
            }
            _flowCoordinator.onDatabaseSelectionState(context, state);
          },
          builder: (context, state) {
            if (state is DatabaseSelectionLoading ||
                state is DatabaseSelectionInitial) {
              return const Center(child: CircularProgressIndicator());
            }

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  topInset + 20,
                  horizontalPadding,
                  24,
                ),
                child: TweenAnimationBuilder<double>(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0.98, end: 1),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(cardPadding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/logo/keyvault-source.png',
                            width: 120,
                            height: 120,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            state.recentDatabasePaths.length > 1
                                ? 'Choose a database to continue'
                                : 'Welcome to your vault',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.recentDatabasePaths.length > 1
                                ? 'Multiple databases are available. Pick one from recent list or open another file.'
                                : 'Open an existing KDBX database or create a new one to start securely storing your credentials.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          _buildRecentDatabasesSection(
                            context,
                            state.recentDatabasePaths,
                          ),
                          const SizedBox(height: 6),
                          _buildPrimaryActions(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
