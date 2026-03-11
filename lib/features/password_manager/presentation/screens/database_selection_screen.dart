import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/utils/mobile_file_storage.dart';
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

      String? savePath;
      if (_isMobilePlatform) {
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
      final localPath = _isMobilePlatform
          ? await MobileFileStorage.saveBytesToAppDirectory(
              bytes: bytes,
              fileName: p.basename(savePath),
              subdirectory: 'databases',
            )
          : savePath;

      if (!_isMobilePlatform) {
        await File(localPath).writeAsBytes(bytes, flush: true);
      }
      hideProgressIfNeeded();

      if (!context.mounted) {
        return;
      }

      if (_isMobilePlatform) {
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

  Widget _buildRecentDatabasesSection(
    BuildContext context,
    List<String> recentDatabasePaths,
  ) {
    return _RecentDatabasesSection(
      recentDatabasePaths: recentDatabasePaths,
      onOpen: (path) => _onOpenRecentDatabase(context, path),
      onRemove: (path) => _onRemoveRecentDatabase(context, path),
    );
  }

  Widget _buildPrimaryActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SelectionActionTile(
          icon: AppIcons.folderOpen,
          title: 'Open existing database',
          subtitle: 'Choose a .kdbx file from your device',
          onTap: () {
            context.read<DatabaseSelectionBloc>().add(SelectExistingDatabase());
          },
        ),
        const SizedBox(height: 10),
        _SelectionActionTile(
          icon: AppIcons.add,
          title: 'Create new database',
          subtitle: 'Create a protected vault with password and key file',
          onTap: () => _onCreateDatabase(context),
        ),
        const SizedBox(height: 10),
        _SelectionActionTile(
          icon: AppIcons.cloud,
          title: 'Open from Google Drive',
          subtitle: 'Download a .kdbx and open a local copy',
          onTap: () => _openFromGoogleDrive(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = viewportWidth < 420 ? 16.0 : 24.0;
    final cardPadding = viewportWidth < 420 ? 18.0 : 24.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
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
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  topInset + 20,
                  horizontalPadding,
                  24,
                ),
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
                        padding: EdgeInsets.all(cardPadding),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.lock,
                              size: 64,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Vault setup',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    letterSpacing: 0.2,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 8),
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
                            if (_isMobilePlatform) ...[
                              const SizedBox(height: 18),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  'On mobile, databases and key files are imported into app internal storage. Keep manual backups in a separate location to avoid data loss after app removal.',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ),
                            ],
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

bool get _isMobilePlatform {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}

class _SelectionActionTile extends StatelessWidget {
  const _SelectionActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant),
          color: colorScheme.surface.withValues(alpha: 0.72),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              AppIcons.chevronRight,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentDatabasesSection extends StatefulWidget {
  const _RecentDatabasesSection({
    required this.recentDatabasePaths,
    required this.onOpen,
    required this.onRemove,
  });

  final List<String> recentDatabasePaths;
  final Future<void> Function(String path) onOpen;
  final Future<void> Function(String path) onRemove;

  @override
  State<_RecentDatabasesSection> createState() =>
      _RecentDatabasesSectionState();
}

class _RecentDatabasesSectionState extends State<_RecentDatabasesSection> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    if (widget.recentDatabasePaths.isEmpty) {
      return const SizedBox.shrink();
    }

    final normalizedQuery = _query.trim().toLowerCase();
    var filtered = widget.recentDatabasePaths
        .where((path) {
          if (normalizedQuery.isEmpty) {
            return true;
          }
          final fileName = p.basename(path).toLowerCase();
          return fileName.contains(normalizedQuery) ||
              path.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);

    filtered = filtered.reversed.toList(growable: false);

    final showSearch = widget.recentDatabasePaths.length > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(AppIcons.refresh, size: 18),
            const SizedBox(width: 8),
            Text(
              'Recent databases',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (showSearch) ...[
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Search recent databases',
              prefixIcon: Icon(AppIcons.search),
            ),
            onChanged: (value) {
              setState(() {
                _query = value;
              });
            },
          ),
          const SizedBox(height: 8),
        ],
        ...filtered.asMap().entries.map((entry) {
          final index = entry.key;
          final pathValue = entry.value;
          final fileName = p.basename(pathValue);
          final isMostRecent = index == 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _RecentDatabaseTile(
              path: pathValue,
              fileName: fileName,
              isMostRecent: isMostRecent,
              onOpen: () => widget.onOpen(pathValue),
              onRemove: () => widget.onRemove(pathValue),
            ),
          );
        }),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No recent database matches your search.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _RecentDatabaseTile extends StatefulWidget {
  const _RecentDatabaseTile({
    required this.path,
    required this.fileName,
    required this.isMostRecent,
    required this.onOpen,
    required this.onRemove,
  });

  final String path;
  final String fileName;
  final bool isMostRecent;
  final Future<void> Function() onOpen;
  final Future<void> Function() onRemove;

  @override
  State<_RecentDatabaseTile> createState() => _RecentDatabaseTileState();
}

class _RecentDatabaseTileState extends State<_RecentDatabaseTile> {
  bool _isDriveLinked = false;
  bool _loadingDriveState = true;
  int? _sizeBytes;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final mapping = await di.sl<DatabaseSyncRepository>().getMapping(
        widget.path,
      );

      int? sizeBytes;
      if (!kIsWeb) {
        final file = File(widget.path);
        if (await file.exists()) {
          sizeBytes = await file.length();
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isDriveLinked = mapping != null;
        _sizeBytes = sizeBytes;
        _loadingDriveState = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingDriveState = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: widget.onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            const Icon(AppIcons.file),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (widget.isMostRecent)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Most recent',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (_sizeBytes != null)
                        Text(
                          _formatSize(_sizeBytes!),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (_sizeBytes != null)
                        Text(
                          '  •  ',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (_loadingDriveState)
                        Text(
                          'Checking Drive link...',
                          style: Theme.of(context).textTheme.labelSmall,
                        )
                      else if (_isDriveLinked)
                        Row(
                          children: [
                            const Icon(AppIcons.cloud, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Linked to Drive',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        )
                      else
                        Text(
                          'Local only',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!_isMobilePlatform)
              FilledButton.tonalIcon(
                onPressed: widget.onOpen,
                icon: const Icon(AppIcons.folderOpen),
                label: const Text('Open'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'More actions',
              onSelected: (value) {
                if (value == 'remove') {
                  widget.onRemove();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(AppIcons.more),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
