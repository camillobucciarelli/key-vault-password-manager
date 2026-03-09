part of '../vault_screen.dart';

class _VaultLayoutBreakpoints {
  const _VaultLayoutBreakpoints._();

  static const double tabletMax = Breakpoints.tablet;
  static const double compactPhone = 380;
  static const double searchSortStack = 620;
  static const double breadcrumbBarHeight = 40;
  static const double syncStripHeight = 44;
}

class _VaultUiTokens {
  const _VaultUiTokens._();

  static const double cardPadding = 14;
  static const double cardRadius = 18;
  static const double folderIconContainerSize = 32;
  static const double recordItemRadius = 12;
  static const double recordItemHeight = 62;
  static const double recordListSpacing = 8;
  static const Duration itemTransitionDuration = Duration(milliseconds: 190);
  static const Duration buttonTransitionDuration = Duration(milliseconds: 220);
  static const Duration chipTransitionDuration = Duration(milliseconds: 180);
  static const Duration backgroundLockTimeout = Duration(seconds: 30);
}

class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key, required this.databasePath});

  final String databasePath;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<VaultBloc>(param1: databasePath)..add(const InitializeVault()),
      child: const _VaultView(),
    );
  }
}

class _VaultLayoutSpec {
  const _VaultLayoutSpec({
    required this.isCompact,
    required this.isTablet,
    required this.horizontalPadding,
    required this.contentTopPadding,
  });

  final bool isCompact;
  final bool isTablet;
  final double horizontalPadding;
  final double contentTopPadding;

  static _VaultLayoutSpec fromWidth(double width) {
    final isCompact = width < _VaultLayoutBreakpoints.tabletMax;
    final isTablet =
        width >= Breakpoints.mobile &&
        width < _VaultLayoutBreakpoints.tabletMax;
    final horizontalPadding = width < _VaultLayoutBreakpoints.compactPhone
        ? 12.0
        : 16.0;

    return _VaultLayoutSpec(
      isCompact: isCompact,
      isTablet: isTablet,
      horizontalPadding: horizontalPadding,
      contentTopPadding: isCompact ? 8 : 12,
    );
  }
}

class _VaultView extends StatefulWidget {
  const _VaultView();

  @override
  State<_VaultView> createState() => _VaultViewState();
}

class _VaultViewState extends State<_VaultView> with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  bool _isLockNavigationInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt = DateTime.now();
        break;
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onAppResumed() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null || _isLockNavigationInProgress || !mounted) {
      return;
    }

    final elapsed = DateTime.now().difference(backgroundedAt);
    if (elapsed < _VaultUiTokens.backgroundLockTimeout) {
      return;
    }

    final databasePath = context.read<VaultBloc>().state.databasePath;
    if (databasePath.trim().isEmpty) {
      return;
    }

    _isLockNavigationInProgress = true;
    AppNavigation.pushFadeReplacement(
      context,
      DatabaseUnlockScreen(databasePath: databasePath),
    );
  }

  Future<void> _closeCurrentDatabaseAndSelectAnother() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Close database'),
          content: const Text(
            'Close this database and return to file selection? Saved credentials for the current database will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Close database'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await di.sl<SaveSelectedDatabasePathUseCase>()('');
      await di.sl<SaveSelectedKeyFilePathUseCase>()(null);
      await di.sl<SecureDataSource>().clearMasterPassword();

      if (!mounted) {
        return;
      }

      await AppNavigation.pushFadeReplacement(
        context,
        const DatabaseSelectionScreen(),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to close current database.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarOverlayHeight =
        MediaQuery.paddingOf(context).top +
        kToolbarHeight +
        _VaultLayoutBreakpoints.breadcrumbBarHeight +
        _VaultLayoutBreakpoints.syncStripHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            final current = state.currentGroup;
            if (current?.parentId == null) {
              return const SizedBox.shrink();
            }

            return IconButton(
              tooltip: 'Go to parent folder',
              onPressed: () {
                context.read<VaultBloc>().add(const OpenParentGroup());
              },
              icon: const Icon(AppIcons.back),
            );
          },
        ),
        title: BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            final colorScheme = Theme.of(context).colorScheme;
            final title = state.currentGroup?.name;
            final resolvedTitle = (title == null || title.trim().isEmpty)
                ? 'Vault'
                : title;
            return Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _syncStatusColor(state.syncStatus, colorScheme),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(resolvedTitle, overflow: TextOverflow.ellipsis),
                ),
              ],
            );
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(
            _VaultLayoutBreakpoints.breadcrumbBarHeight +
                _VaultLayoutBreakpoints.syncStripHeight,
          ),
          child: BlocBuilder<VaultBloc, VaultState>(
            builder: (context, state) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BreadcrumbsBar(
                    groups: state.breadcrumbs(),
                    rootGroupId: state.rootGroupId,
                    childGroups: state.currentChildGroups,
                    allGroups: state.groups,
                  ),
                  _SyncStatusStrip(state: state),
                ],
              );
            },
          ),
        ),
        actions: [
          const AndroidAutofillAction(),
          PopupMenuButton<String>(
            tooltip: 'Vault options',
            icon: const Icon(AppIcons.more),
            onSelected: (value) async {
              if (value == 'switchDatabase') {
                await _closeCurrentDatabaseAndSelectAnother();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'switchDatabase',
                child: Text('Switch database'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Open recycle bin',
            onPressed: () => _showRecycleBinDialog(context),
            icon: const Icon(AppIcons.delete),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              context.read<VaultBloc>().add(const RefreshVault());
            },
            icon: const Icon(AppIcons.refresh),
          ),
          BlocBuilder<VaultBloc, VaultState>(
            builder: (context, state) {
              final icon = switch (state.syncStatus) {
                DatabaseSyncStatus.syncing => AppIcons.sync,
                DatabaseSyncStatus.success => AppIcons.cloudDone,
                DatabaseSyncStatus.error => AppIcons.cloudOff,
                DatabaseSyncStatus.conflict => AppIcons.warning,
                DatabaseSyncStatus.disconnected => AppIcons.cloudOff,
                DatabaseSyncStatus.idle => AppIcons.cloud,
              };
              return PopupMenuButton<String>(
                tooltip: 'Drive sync',
                icon: Icon(icon),
                onSelected: (value) async {
                  switch (value) {
                    case 'connect':
                      context.read<VaultBloc>().add(const ConnectGoogleDrive());
                      break;
                    case 'disconnect':
                      context.read<VaultBloc>().add(
                        const DisconnectGoogleDrive(),
                      );
                      break;
                    case 'link':
                      await _startDriveLinkFlow(context);
                      break;
                    case 'syncNow':
                      context.read<VaultBloc>().add(
                        const SyncCurrentDatabaseNow(),
                      );
                      break;
                    case 'toggleAutoSync':
                      context.read<VaultBloc>().add(
                        ToggleCurrentDatabaseAutoSync(!state.autoSyncEnabled),
                      );
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'Status: ${_syncStatusLabel(state.syncStatus)}',
                    ),
                  ),
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      state.linkedDriveFileName == null
                          ? 'Linked file: -'
                          : 'Linked file: ${state.linkedDriveFileName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      state.lastSyncAt == null
                          ? 'Last sync: never'
                          : 'Last sync: ${_formatSyncDateTime(state.lastSyncAt!)}',
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: state.isDriveConnected ? 'disconnect' : 'connect',
                    child: Text(
                      state.isDriveConnected
                          ? 'Disconnect Google Drive'
                          : 'Step 1/2: Connect Google Drive',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'link',
                    enabled: state.isDriveConnected,
                    child: const Text('Step 2/2: Link this database'),
                  ),
                  PopupMenuItem(
                    value: 'syncNow',
                    enabled: state.isDriveConnected && state.isDriveLinked,
                    child: const Text('Sync now'),
                  ),
                  PopupMenuItem(
                    value: 'toggleAutoSync',
                    child: Text(
                      state.autoSyncEnabled
                          ? 'Disable auto-sync'
                          : 'Enable auto-sync',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppBackgrounds.gradient(context),
            ),
          ),
          BlocConsumer<VaultBloc, VaultState>(
            listener: (context, state) {
              if (state.errorMessage != null &&
                  state.errorMessage!.isNotEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
                context.read<VaultBloc>().add(const ClearVaultError());
              }
              if (state.infoMessage != null && state.infoMessage!.isNotEmpty) {
                final isSyncInfo =
                    state.infoMessage!.toLowerCase().contains('sync') ||
                    state.infoMessage!.toLowerCase().contains('google drive');
                if (isSyncInfo) {
                  _showSyncSnackBar(
                    context,
                    state.infoMessage!,
                    status: state.syncStatus,
                  );
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(state.infoMessage!)));
                }
                context.read<VaultBloc>().add(const ClearVaultInfo());
              }
              if (state.syncError != null && state.syncError!.isNotEmpty) {
                _showSyncSnackBar(
                  context,
                  state.syncError!,
                  status: state.syncStatus,
                );
                context.read<VaultBloc>().add(const ClearVaultSyncFeedback());
              }
              if (state.pendingSyncConflict != null) {
                _showSyncConflictDialog(context, state.pendingSyncConflict!);
              }
            },
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final spec = _VaultLayoutSpec.fromWidth(
                        constraints.maxWidth,
                      );

                      if (spec.isCompact) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            spec.horizontalPadding,
                            appBarOverlayHeight + spec.contentTopPadding,
                            spec.horizontalPadding,
                            spec.horizontalPadding,
                          ),
                          child: _EntriesCard(
                            entries: state.visibleEntries,
                            groups: state.groups,
                            searchQuery: state.searchQuery,
                            sortBy: state.sortBy,
                            keepSearchSortInline: spec.isTablet,
                            isScrollablePage: true,
                          ),
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          spec.horizontalPadding,
                          appBarOverlayHeight + spec.contentTopPadding,
                          spec.horizontalPadding,
                          spec.horizontalPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _EntriesCard(
                                entries: state.visibleEntries,
                                groups: state.groups,
                                searchQuery: state.searchQuery,
                                sortBy: state.sortBy,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (state.isSaving)
                    Container(
                      color: Colors.black.withValues(alpha: 0.15),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
