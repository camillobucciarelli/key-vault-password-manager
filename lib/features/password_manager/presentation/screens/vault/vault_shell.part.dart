part of '../vault_screen.dart';

class _VaultLayoutBreakpoints {
  const _VaultLayoutBreakpoints._();

  static const double tabletMax = Breakpoints.tablet;
  static const double compactPhone = 380;
}

class _VaultUiTokens {
  const _VaultUiTokens._();

  static const double cardPadding = 14;
  static const double cardRadius = 18;
  static const double panelGap = 12;
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
    required this.isMobile,
    required this.isCompact,
    required this.isTablet,
    required this.horizontalPadding,
    required this.contentTopPadding,
  });

  final bool isMobile;
  final bool isCompact;
  final bool isTablet;
  final double horizontalPadding;
  final double contentTopPadding;

  static _VaultLayoutSpec fromWidth(double width) {
    final isMobile = width < Breakpoints.mobile;
    final isCompact = width < _VaultLayoutBreakpoints.tabletMax;
    final isTablet =
        width >= Breakpoints.mobile &&
        width < _VaultLayoutBreakpoints.tabletMax;
    final horizontalPadding = width < _VaultLayoutBreakpoints.compactPhone
        ? 12.0
        : 16.0;

    return _VaultLayoutSpec(
      isMobile: isMobile,
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
  bool _autofillPromptChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowAutofillOnboardingDialog();
    });
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

  Future<void> _maybeShowAutofillOnboardingDialog() async {
    if (_autofillPromptChecked || !mounted) {
      return;
    }
    _autofillPromptChecked = true;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final localDataSource = di.sl<LocalDataSource>();
    final seen = await localDataSource.getAutofillPromptSeen();
    if (seen || !mounted) {
      return;
    }

    final autofillService = di.sl<AutofillService>();
    final status = await autofillService.status;
    await localDataSource.setAutofillPromptSeen(true);

    if (!mounted ||
        status == AutofillServiceStatus.enabled ||
        status == AutofillServiceStatus.unsupported) {
      return;
    }

    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enable Android Autofill'),
          insetPadding: _dialogInsetPadding(dialogContext),
          contentPadding: _dialogContentPadding(dialogContext),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          content: const Text(
            'Use this app to autofill credentials in apps and websites on Android.',
          ),
          actions: _adaptiveDialogActions(dialogContext, [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Enable now'),
            ),
          ]),
        );
      },
    );

    if (shouldEnable != true || !mounted) {
      return;
    }

    await autofillService.requestSetAutofillService();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select this app as your Android Autofill service.'),
      ),
    );
  }

  Future<void> _closeCurrentDatabaseAndSelectAnother() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Close database'),
          insetPadding: _dialogInsetPadding(dialogContext),
          contentPadding: _dialogContentPadding(dialogContext),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          content: const Text(
            'Close this database and return to file selection? Saved credentials for the current database will be removed.',
          ),
          actions: _adaptiveDialogActions(dialogContext, [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Close database'),
            ),
          ]),
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final databasePath = context.read<VaultBloc>().state.databasePath;
      await di.sl<SaveSelectedDatabasePathUseCase>()('');
      await di.sl<SaveSelectedKeyFilePathUseCase>()(null);
      await di.sl<SecureDataSource>().clearMasterPassword();
      await di.sl<AddRecentDatabasePathUseCase>()(databasePath);

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
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.transparent,
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

                      if (spec.isMobile) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            spec.horizontalPadding,
                            topInset + spec.contentTopPadding,
                            spec.horizontalPadding,
                            spec.horizontalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SyncStatusStrip(
                                state: state,
                                onRefresh: () {
                                  context.read<VaultBloc>().add(
                                    const RefreshVault(),
                                  );
                                },
                                onOpenRecycleBin: () {
                                  _showRecycleBinDialog(context);
                                },
                                onChangeDatabase:
                                    _closeCurrentDatabaseAndSelectAnother,
                              ),
                              const SizedBox(height: _VaultUiTokens.panelGap),
                              _EntriesCard(
                                entries: state.visibleEntries,
                                groups: state.groups,
                                rootGroupId: state.rootGroupId,
                                currentGroupId: state.currentGroupId,
                                expandedGroupIds: state.expandedGroupIds,
                                searchQuery: state.searchQuery,
                                isScrollablePage: true,
                              ),
                            ],
                          ),
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          spec.horizontalPadding,
                          topInset + spec.contentTopPadding,
                          spec.horizontalPadding,
                          spec.horizontalPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SyncStatusStrip(
                              state: state,
                              onRefresh: () {
                                context.read<VaultBloc>().add(
                                  const RefreshVault(),
                                );
                              },
                              onOpenRecycleBin: () {
                                _showRecycleBinDialog(context);
                              },
                              onChangeDatabase:
                                  _closeCurrentDatabaseAndSelectAnother,
                            ),
                            const SizedBox(height: _VaultUiTokens.panelGap),
                            Expanded(
                              child: _EntriesCard(
                                entries: state.visibleEntries,
                                groups: state.groups,
                                rootGroupId: state.rootGroupId,
                                currentGroupId: state.currentGroupId,
                                expandedGroupIds: state.expandedGroupIds,
                                searchQuery: state.searchQuery,
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
