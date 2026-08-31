part of '../vault_screen.dart';

// FR-1..FR-3 / T5-T9: Sync destination — status hero (screen 1,2,4-7),
// remote file picker (screen 3), conflict sheet (screen 8). Replaces the
// dialog-based `_showLinkDatabaseDialog` combined create/pick flow: the
// hero now offers "Create a new file" and "Pick an existing .kdbx" as two
// independent one-tap actions, matching the mock.

class _VaultSyncDestination extends StatefulWidget {
  const _VaultSyncDestination();

  @override
  State<_VaultSyncDestination> createState() => _VaultSyncDestinationState();
}

class _VaultSyncDestinationState extends State<_VaultSyncDestination> {
  bool _isReconnecting = false;

  Future<void> _reconnectAndResume() async {
    if (_isReconnecting) return;
    setState(() => _isReconnecting = true);
    final bloc = context.read<VaultBloc>();
    await di.sl<GoogleDriveReconnectCoordinator>().reconnect(
      owner: this,
      bloc: bloc,
      continuation: GoogleDriveReconnectContinuation.resumeSync,
      isOwnerActive: () => mounted,
    );
    if (!mounted) return;
    setState(() => _isReconnecting = false);
  }

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
                localChecksum: state.lastSyncedLocalChecksum,
                autoSyncEnabled: state.autoSyncEnabled,
                syncError: state.syncError,
                reconnectRequired: state.driveReconnectRequired,
                isReconnecting: _isReconnecting,
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
                onReconnect: _isReconnecting ? null : _reconnectAndResume,
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

  // On desktop the picker is a pane that REPLACES this destination's body,
  // so `context` is unmounted by the time the await resolves — dispatch on
  // the captured bloc, never through the dead context (the "Link does
  // nothing" defect, 2026-08-31).
  if (result is ExistingDriveLinkResult && !bloc.isClosed) {
    bloc.add(LinkCurrentDatabaseToDrive(remoteFileId: result.remoteFileId));
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
  String _query = '';
  List<DatabaseSyncMapping> _otherMappings = const [];
  bool _isReconnecting = false;

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

  void _completeSelectedLink() {
    final selectedId = _selectedId;
    final state = context.read<VaultBloc>().state;
    final valid =
        selectedId != null &&
        state.isDriveConnected &&
        !state.isLoadingRemoteDriveFiles &&
        state.remoteDriveFilesError == null &&
        state.remoteDriveFiles.any((file) => file.id == selectedId);
    if (!valid) {
      if (_selectedId != null) {
        setState(() => _selectedId = null);
      }
      return;
    }
    VaultOperationScope.of(
      context,
    ).complete(DriveLinkResult.existing(selectedId));
  }

  Future<void> _reconnectAndReload() async {
    if (_isReconnecting) return;
    setState(() => _isReconnecting = true);
    final bloc = context.read<VaultBloc>();
    await di.sl<GoogleDriveReconnectCoordinator>().reconnect(
      owner: this,
      bloc: bloc,
      continuation: GoogleDriveReconnectContinuation.reloadRemoteFiles,
      remoteFilesQuery: _query,
      isOwnerActive: () => mounted,
    );
    if (!mounted) return;
    setState(() => _isReconnecting = false);
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
              padding: const EdgeInsets.fromLTRB(18, 12, 14, 0),
              child: Row(
                children: [
                  KvCircleIconButton(
                    glyph: AppGlyph.back,
                    tooltip: 'Back',
                    onPressed: () => VaultOperationScope.of(context).cancel(),
                  ),
                  const SizedBox(width: 12),
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
                enabled: !_isReconnecting,
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
                onChanged: (value) {
                  _query = value;
                  final bloc = context.read<VaultBloc>();
                  final state = bloc.state;
                  if (_isReconnecting ||
                      state.remoteDriveFilesError != null ||
                      !state.isDriveConnected) {
                    return;
                  }
                  bloc.add(LoadDriveRemoteFiles(query: value));
                },
              ),
            ),
            Expanded(
              child: BlocBuilder<VaultBloc, VaultState>(
                buildWhen: (p, n) =>
                    p.remoteDriveFiles != n.remoteDriveFiles ||
                    p.isLoadingRemoteDriveFiles !=
                        n.isLoadingRemoteDriveFiles ||
                    p.remoteDriveFilesError != n.remoteDriveFilesError ||
                    p.remoteDriveFilesReconnectRequired !=
                        n.remoteDriveFilesReconnectRequired,
                builder: (context, state) {
                  final syncError = state.remoteDriveFilesError;
                  if (syncError != null) {
                    final reconnectRequired =
                        state.remoteDriveFilesReconnectRequired;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              reconnectRequired
                                  ? 'Google authorization expired'
                                  : 'Unable to reconnect',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.panelTitleLarge.copyWith(
                                color: colors.attentionText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              syncError,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body.copyWith(
                                color: colors.attentionText,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Semantics(
                              container: true,
                              button: true,
                              enabled: !_isReconnecting,
                              label: reconnectRequired
                                  ? 'Reconnect Google Drive'
                                  : 'Retry Google Drive connection',
                              child: ExcludeSemantics(
                                child: KvPillButton(
                                  label: _isReconnecting
                                      ? 'Reconnecting...'
                                      : reconnectRequired
                                      ? 'Reconnect'
                                      : 'Retry',
                                  onPressed: _isReconnecting
                                      ? null
                                      : _reconnectAndReload,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (state.isLoadingRemoteDriveFiles) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // If the list changed (e.g. the user filtered by typing) and
                  // the previously selected file is no longer in it, drop the
                  // stale selection instead of leaving "Link" enabled against
                  // an id no longer visible/valid — see spec-005 Copilot fix.
                  // MUST run before the isEmpty early-return below: a filter
                  // that narrows the list to zero results is exactly the
                  // case where the selection needs clearing.
                  if (_selectedId != null &&
                      !state.remoteDriveFiles.any(
                        (file) => file.id == _selectedId,
                      )) {
                    _selectedId = null;
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
                        onTap: () => setState(
                          () => _selectedId =
                              _selectedId == file.id ? null : file.id,
                        ),
                        onLink: _completeSelectedLink,
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
          ],
        ),
      ),
    );
  }
}

Future<void> _showSyncConflictDialog(
  BuildContext context,
  SyncConflict conflict,
) async {
  // Captured before the await: on desktop the conflict surface is a pane
  // that replaces this destination's body, unmounting `context` (same
  // defect as _pickExistingDriveFile).
  final bloc = context.read<VaultBloc>();
  final resolution = await VaultShellRouterScope.of(context)
      .open<SyncConflictRouteResult>(
        context: context,
        surface: SyncConflictSurface<SyncConflictRouteResult>(
          builder: (dialogContext) => _SyncConflictSheet(conflict: conflict),
        ),
      );

  if (bloc.isClosed) {
    return;
  }

  bloc.add(const ClearVaultSyncFeedback());

  if (resolution == null ||
      resolution.resolution == SyncConflictResolution.cancel) {
    return;
  }

  bloc.add(SyncCurrentDatabaseNow(resolution: resolution.resolution));
}

/// T9: two version cards radius 20 padding 14/16 with a 40 square, checksum
/// mono 11, `remoteModifiedTime`; Keep local / Use remote / Cancel with
/// which-side labels. `SyncConflictResolution` semantics unchanged.
class _SyncConflictSheet extends StatelessWidget {
  const _SyncConflictSheet({required this.conflict});

  final SyncConflict conflict;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Both versions changed',
            style: AppTextStyles.sheetTitleLarge.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This device and "${conflict.driveFileName}" on Drive were both '
            'edited since the last sync. Pick which one to keep — the '
            'other is not deleted, it stays as a Drive revision.',
            style: AppTextStyles.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          _VersionCard(
            label: 'This device',
            meta: _shortChecksum(conflict.localChecksum),
            background: colors.attentionTint,
            foreground: colors.attentionText,
          ),
          const SizedBox(height: 9),
          _VersionCard(
            label: 'Drive',
            meta: _shortChecksum(conflict.remoteChecksum),
            secondaryMeta: conflict.remoteModifiedTime == null
                ? null
                : 'Modified ${_formatSyncDateTime(conflict.remoteModifiedTime!)}',
            background: colors.surface,
            foreground: colors.textSecondary,
          ),
          const SizedBox(height: 10),
          // Material ancestor of its own: `ListTile` (inside
          // `ExpansionTile`) paints ink/background on the nearest
          // Material, and the sheet's own rounded-top DecoratedBox would
          // otherwise hide it (Flutter's own debug assertion catches this).
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Technical details',
                style: AppTextStyles.secondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              children: [
                _syncConflictDetailRow(
                  'Local checksum',
                  _shortChecksum(conflict.localChecksum),
                ),
                _syncConflictDetailRow(
                  'Remote checksum',
                  _shortChecksum(conflict.remoteChecksum),
                ),
                _syncConflictDetailRow(
                  'Previous local checksum',
                  _shortChecksumOrDash(conflict.previousLocalChecksum),
                ),
                _syncConflictDetailRow(
                  'Previous remote checksum',
                  _shortChecksumOrDash(conflict.previousRemoteChecksum),
                ),
                _syncConflictDetailRow(
                  'Remote modified',
                  conflict.remoteModifiedTime == null
                      ? '-'
                      : _formatSyncDateTime(conflict.remoteModifiedTime!),
                ),
                _syncConflictDetailRow(
                  'Local changed',
                  _boolLabel(conflict.localChanged),
                ),
                _syncConflictDetailRow(
                  'Remote changed',
                  _boolLabel(conflict.remoteChanged),
                ),
                _syncConflictDetailRow(
                  'First sync no baseline',
                  _boolLabel(conflict.firstSyncWithoutBaseline),
                ),
                _syncConflictDetailRow(
                  'Remote checksum source',
                  conflict.remoteChecksumComputedFromDownload == true
                      ? 'download-fallback'
                      : 'metadata-md5',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          KvPillButton(
            label: 'Keep local',
            onPressed: () => VaultOperationScope.of(context).complete(
              const SyncConflictRouteResult(SyncConflictResolution.keepLocal),
            ),
          ),
          const SizedBox(height: 9),
          KvSecondaryPillButton(
            label: 'Use remote',
            onPressed: () => VaultOperationScope.of(context).complete(
              const SyncConflictRouteResult(SyncConflictResolution.useRemote),
            ),
          ),
          const SizedBox(height: 9),
          Center(
            child: TextButton(
              onPressed: () => VaultOperationScope.of(context).complete(
                const SyncConflictRouteResult(SyncConflictResolution.cancel),
              ),
              child: Text(
                'Cancel',
                style: AppTextStyles.body.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.label,
    required this.meta,
    required this.background,
    required this.foreground,
    this.secondaryMeta,
  });

  final String label;
  final String meta;
  final String? secondaryMeta;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.ground,
              borderRadius: BorderRadius.circular(AppRadii.iconSquare),
            ),
            alignment: Alignment.center,
            child: KvIcon(
              glyph: label == 'This device' ? AppGlyph.desktop : AppGlyph.cloud,
              size: 18,
              color: foreground,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.rowTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (secondaryMeta != null)
                  Text(
                    secondaryMeta!,
                    style: AppTextStyles.meta.copyWith(color: foreground),
                  ),
                Text(
                  meta,
                  style: AppTextStyles.secret.copyWith(
                    fontSize: 11,
                    color: foreground,
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

Widget _syncConflictDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 168, child: Text('$label:')),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

String _shortChecksum(String checksum) {
  if (checksum.length <= 12) {
    return checksum;
  }
  return '${checksum.substring(0, 12)}...';
}

String _shortChecksumOrDash(String? checksum) {
  if (checksum == null || checksum.isEmpty) {
    return '-';
  }
  return _shortChecksum(checksum);
}

String _boolLabel(bool? value) {
  if (value == null) {
    return '-';
  }
  return value ? 'true' : 'false';
}
