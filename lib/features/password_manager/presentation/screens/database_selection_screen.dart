import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../injection_container.dart' as di;
import '../../domain/repositories/database_sync_repository.dart';
import '../../domain/usecases/connect_google_account_usecase.dart';
import '../../domain/usecases/get_drive_connection_status_usecase.dart';
import '../../domain/usecases/list_drive_remote_files_usecase.dart';
import '../../domain/models/drive_remote_file.dart';
import '../bloc/database_selection/database_selection_bloc.dart';
import '../bloc/database_selection/database_selection_event.dart';
import '../bloc/database_selection/database_selection_state.dart';
import 'coordinators/database_flow_coordinator.dart';
import '../widgets/android_autofill_action.dart';
import '../widgets/create_database_dialog.dart';

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

      var savePath = await FilePicker.platform.saveFile(
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

      if (!context.mounted) {
        return;
      }

      showProgress('Downloading database from Drive...');
      final bytes = await di.sl<DatabaseSyncRepository>().downloadRemoteFile(
        selected.id,
      );
      await File(savePath).writeAsBytes(bytes, flush: true);
      hideProgressIfNeeded();

      if (!context.mounted) {
        return;
      }

      context.read<DatabaseSelectionBloc>().add(
        SelectDriveDatabaseLocalCopy(
          localPath: savePath,
          remoteFileId: selected.id,
        ),
      );
    } catch (e) {
      hideProgressIfNeeded();
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to open database from Drive. $e')),
      );
    }
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
              title: const Text('Step 2/2: Select Drive database'),
              content: SizedBox(
                width: 460,
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
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.28)
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.24),
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
              actions: [
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
              ],
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
    return '$year-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Select Database'),
        actions: const [AndroidAutofillAction()],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppBackgrounds.gradient(context)),
        child: BlocConsumer<DatabaseSelectionBloc, DatabaseSelectionState>(
          listener: (context, state) {
            _flowCoordinator.onDatabaseSelectionState(context, state);
          },
          builder: (context, state) {
            if (state is DatabaseSelectionLoading ||
                state is DatabaseSelectionInitial) {
              return const Center(child: CircularProgressIndicator());
            }

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(32, topInset + 24, 32, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
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
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.lock,
                              size: 72,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'No database selected',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Please select an existing KDBX database or create a new one to continue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 32),
                            FilledButton.icon(
                              onPressed: () {
                                context.read<DatabaseSelectionBloc>().add(
                                  SelectExistingDatabase(),
                                );
                              },
                              icon: const Icon(AppIcons.folderOpen),
                              label: const Text('Open Existing Database'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final credentials =
                                    await showDialog<CreateDatabaseCredentials>(
                                      context: context,
                                      builder: (_) =>
                                          const CreateDatabaseDialog(),
                                    );
                                if (credentials != null && context.mounted) {
                                  context.read<DatabaseSelectionBloc>().add(
                                    CreateNewDatabase(
                                      password: credentials.password,
                                      keyFilePath: credentials.keyFilePath,
                                      generateKeyFile:
                                          credentials.generateKeyFile,
                                      generatedKeyFilePath:
                                          credentials.generatedKeyFilePath,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(AppIcons.add),
                              label: const Text('Create New Database'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await _openFromGoogleDrive(context);
                              },
                              icon: const Icon(AppIcons.cloud),
                              label: const Text('Open from Google Drive'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                            ),
                          ],
                        ),
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
