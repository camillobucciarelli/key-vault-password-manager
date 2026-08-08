part of '../vault_screen.dart';

// FR-1..FR-3 / T5-T9: Sync destination — status hero (screen 1,2,4-7),
// remote file picker (screen 3), conflict sheet (screen 8). Replaces the
// dialog-based `_showLinkDatabaseDialog` combined create/pick flow: the
// hero now offers "Create a new file" and "Pick an existing .kdbx" as two
// independent one-tap actions, matching the mock.

class _VaultSyncDestination extends StatelessWidget {
  const _VaultSyncDestination();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: _syncStatusStripBuildWhen,
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sync',
                style: AppTextStyles.screenTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              Text(
                path.basename(state.databasePath),
                style: AppTextStyles.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 18),
              SyncStatusHero(
                status: state.syncStatus,
                isDriveConnected: state.isDriveConnected,
                isDriveLinked: state.isDriveLinked,
                linkedDriveFileName: state.linkedDriveFileName,
                lastSyncAt: state.lastSyncAt,
                localChecksum: null,
                autoSyncEnabled: state.autoSyncEnabled,
                syncError: state.syncError,
                recentActivity: _recentActivity(state),
                isOffline: state.isOffline,
                onConnect: () =>
                    context.read<VaultBloc>().add(const ConnectGoogleDrive()),
                onExportBackup: () =>
                    _exportDatabaseBackup(context, state.databasePath),
                onCreateNewFile: () => _createNewDriveFile(context, state),
                onPickExisting: () => _pickExistingDriveFile(context),
                onToggleAutoSync: (enabled) => context.read<VaultBloc>().add(
                  ToggleCurrentDatabaseAutoSync(enabled),
                ),
                onSyncNow: () => context.read<VaultBloc>().add(
                  const SyncCurrentDatabaseNow(),
                ),
                onUnlink: () => context.read<VaultBloc>().add(
                  const UnlinkCurrentDatabaseFromDrive(),
                ),
                onReconnect: () =>
                    context.read<VaultBloc>().add(const ConnectGoogleDrive()),
                onRetryOffline: () => context.read<VaultBloc>().add(
                  const SyncCurrentDatabaseNow(),
                ),
                onOpenConflict: state.pendingSyncConflict == null
                    ? null
                    : () => _showSyncConflictDialog(
                        context,
                        state.pendingSyncConflict!,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// spec-005 FR-1 adopted proposal: the app does not persist a real sync
  /// history (only `lastSyncAt`), so this derives at most one row instead
  /// of fabricating one — see `SyncActivityItem` doc.
  List<SyncActivityItem> _recentActivity(VaultState state) {
    if (state.lastSyncAt == null || !state.isDriveLinked) {
      return const [];
    }
    return [
      SyncActivityItem(
        icon: AppGlyph.import,
        title: 'Synced with Drive',
        meta: _formatSyncDateTime(state.lastSyncAt!),
      ),
    ];
  }
}

String _suggestedRemoteFileName(String databasePath) {
  final localName = path.basename(databasePath);
  return localName.toLowerCase().endsWith('.kdbx')
      ? localName
      : '$localName.kdbx';
}

void _createNewDriveFile(BuildContext context, VaultState state) {
  context.read<VaultBloc>().add(
    LinkCurrentDatabaseToDrive(
      remoteFileName: _suggestedRemoteFileName(state.databasePath),
    ),
  );
}

Future<void> _pickExistingDriveFile(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  bloc.add(const LoadDriveRemoteFiles());

  final result = await VaultShellRouterScope.of(context).open<DriveLinkResult>(
    context: context,
    surface: SyncLinkSurface<DriveLinkResult>(
      builder: (dialogContext) => BlocProvider.value(
        value: bloc,
        child: const _RemoteFilePickerScreen(),
      ),
    ),
  );

  if (result is ExistingDriveLinkResult && context.mounted) {
    context.read<VaultBloc>().add(
      LinkCurrentDatabaseToDrive(remoteFileId: result.remoteFileId),
    );
  }
}

class _RemoteFilePickerScreen extends StatefulWidget {
  const _RemoteFilePickerScreen();

  @override
  State<_RemoteFilePickerScreen> createState() =>
      _RemoteFilePickerScreenState();
}

class _RemoteFilePickerScreenState extends State<_RemoteFilePickerScreen> {
  String? _selectedId;
  List<DatabaseSyncMapping> _otherMappings = const [];

  @override
  void initState() {
    super.initState();
    _loadOtherMappings();
  }

  Future<void> _loadOtherMappings() async {
    final databasePath = context.read<VaultBloc>().state.databasePath;
    final mappings = await di.sl<DatabaseSyncRepository>().getAllMappings();
    if (!mounted) return;
    setState(() {
      _otherMappings = mappings
          .where((mapping) => mapping.databasePath != databasePath)
          .toList(growable: false);
    });
  }

  bool _isLinkedElsewhere(String remoteFileId) {
    return _otherMappings.any((mapping) => mapping.driveFileId == remoteFileId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => VaultOperationScope.of(context).cancel(),
                    icon: KvIcon(
                      glyph: AppGlyph.close,
                      size: 19,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Link to a Drive file',
                    style: AppTextStyles.panelTitleLarge.copyWith(
                      fontSize: 17,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search .kdbx file',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: KvIcon(
                      glyph: AppGlyph.search,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                onChanged: (value) => context.read<VaultBloc>().add(
                  LoadDriveRemoteFiles(query: value),
                ),
              ),
            ),
            Expanded(
              child: BlocBuilder<VaultBloc, VaultState>(
                buildWhen: (p, n) =>
                    p.remoteDriveFiles != n.remoteDriveFiles ||
                    p.isLoadingRemoteDriveFiles != n.isLoadingRemoteDriveFiles,
                builder: (context, state) {
                  if (state.isLoadingRemoteDriveFiles) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.remoteDriveFiles.isEmpty) {
                    return Center(
                      child: Text(
                        'No .kdbx files found.',
                        style: AppTextStyles.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    );
                  }
                  _selectedId ??= state.remoteDriveFiles.first.id;
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: state.remoteDriveFiles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final file = state.remoteDriveFiles[index];
                      return RemoteFileRow(
                        file: file,
                        selected: _selectedId == file.id,
                        isLinkedElsewhere: _isLinkedElsewhere(file.id),
                        onTap: () => setState(() => _selectedId = file.id),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Linking replaces nothing right away: the next sync '
                  'compares checksums and asks you if they differ.',
                  style: AppTextStyles.secondary.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: KvSecondaryPillButton(
                      label: 'Cancel',
                      onPressed: () => VaultOperationScope.of(context).cancel(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: KvPillButton(
                      label: 'Link',
                      onPressed: _selectedId == null
                          ? null
                          : () => VaultOperationScope.of(
                              context,
                            ).complete(DriveLinkResult.existing(_selectedId!)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
