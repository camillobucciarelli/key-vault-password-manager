part of '../vault_screen.dart';

bool _syncErrorNeedsReconnectAction(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('authorization expired') ||
      normalized.contains('authorization needs to be renewed') ||
      normalized.contains('authorization is outdated') ||
      normalized.contains('reconnect google drive') ||
      normalized.contains('google account not connected');
}

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
  static const Duration backgroundLockTimeout = Duration(seconds: 30);
}

class VaultScreen extends StatelessWidget {
  const VaultScreen({
    super.key,
    required this.databasePath,
    // spec-006 T16: the lock/privacy overlays are only reachable via a real
    // inactivity timer firing or a >=30s background/resume cycle — neither
    // is practical to drive deterministically from a widget test. These
    // test-only seeds let goldens render the overlays directly, matching
    // the `debugEntryDetailNowOverride` / `debugLockOverlayNowOverride`
    // clock-seam convention already used elsewhere in this file family.
    @visibleForTesting this.debugInitiallyLocked = false,
    @visibleForTesting this.debugInitiallyBackground = false,
  });

  final String databasePath;
  final bool debugInitiallyLocked;
  final bool debugInitiallyBackground;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<VaultBloc>(param1: databasePath)..add(const InitializeVault()),
      child: _VaultView(
        debugInitiallyLocked: debugInitiallyLocked,
        debugInitiallyBackground: debugInitiallyBackground,
      ),
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
  const _VaultView({
    this.debugInitiallyLocked = false,
    this.debugInitiallyBackground = false,
  });

  final bool debugInitiallyLocked;
  final bool debugInitiallyBackground;

  @override
  State<_VaultView> createState() => _VaultViewState();
}

class _VaultViewState extends State<_VaultView> with WidgetsBindingObserver {
  late final VaultShellRouter _router;
  VaultDestination _selectedDestination = VaultDestination.vault;
  Widget? _activePane;
  DateTime? _backgroundedAt;
  bool _isBackground = false;
  bool _isLocked = false;
  // spec-006 T4: when the lock overlay engaged, so it can render "locked
  // for <duration>" (FR-3). Cleared on unlock.
  DateTime? _lockedAt;
  Timer? _inactivityTimer;
  StreamSubscription<OtpAuthDeepLinkEvent>? _otpAuthSubscription;
  final List<OtpAuthDeepLinkEvent> _otpAuthEventQueue = [];
  int? _inactivityTimeoutSeconds;
  bool _otpAuthVaultMarkedAvailable = false;
  bool _isHandlingOtpAuth = false;
  String? _activeAppleAutofillAssociationDialogId;
  // Guards against `_router.dispose()` (below) synchronously cancelling any
  // open session and calling back into `onPaneChanged` -> `setState` while
  // *this* State's own `dispose()` is still running. `mounted` alone does
  // not catch this: `State.mounted` only reflects whether `_element` has
  // been cleared, which happens *after* `dispose()` returns, so it is still
  // `true` for the whole duration of `dispose()` even though the Element's
  // lifecycle has already moved past "active" — calling `setState` in that
  // window trips a framework assertion. Found while adding spec-004's entry
  // detail/editor/generator golden tests (the first tests that ever tear
  // down `VaultScreen` while a pane/sheet session is open); the same crash
  // would hit a real user who closes/backgrounds the app with an entry,
  // editor, or generator open.
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    _isLocked = widget.debugInitiallyLocked;
    _isBackground = widget.debugInitiallyBackground;
    if (_isLocked) {
      _lockedAt = debugLockOverlayNowOverride();
    }
    _router = VaultShellRouter(
      onPaneChanged: (pane) {
        if (mounted && !_isDisposing) {
          setState(() => _activePane = pane);
        }
      },
    );
    WidgetsBinding.instance.addObserver(this);
    _otpAuthSubscription = di.sl<OtpAuthDeepLinkCoordinator>().events.listen(
      _handleOtpAuthEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowAutofillOnboardingDialog();
      _loadInactivityTimeout();
    });
  }

  @override
  void dispose() {
    _isDisposing = true;
    _router.dispose();
    _inactivityTimer?.cancel();
    _otpAuthSubscription?.cancel();
    di.sl<OtpAuthDeepLinkCoordinator>().markVaultUnavailable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _selectDestination(VaultDestination destination) async {
    if (destination == _selectedDestination) {
      return;
    }
    if (!await _router.cancelForDestinationChange() || !mounted) {
      return;
    }
    setState(() => _selectedDestination = destination);
  }

  void _markOtpAuthVaultAvailableIfReady(VaultState state) {
    if (_otpAuthVaultMarkedAvailable ||
        state.isLoading ||
        state.rootGroupId == null) {
      return;
    }
    _otpAuthVaultMarkedAvailable = true;
    di.sl<OtpAuthDeepLinkCoordinator>().markVaultAvailable();
  }

  Future<void> _handleOtpAuthEvent(OtpAuthDeepLinkEvent event) async {
    if (!mounted) {
      return;
    }
    final errorMessage = event.errorMessage;
    if (errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
      return;
    }

    final otpAuth = event.otpAuth;
    if (otpAuth == null) {
      return;
    }

    if (_isHandlingOtpAuth) {
      _otpAuthEventQueue.add(event);
      return;
    }

    _isHandlingOtpAuth = true;
    try {
      final shouldAdd = await _router.confirm(
        context: context,
        title: 'Add OTP account?',
        body:
            'An OTP account for ${otpAuth.title} was received. Review it before saving to this vault.',
        cancelLabel: 'Not now',
        confirmLabel: 'Review',
      );

      if (shouldAdd != ConfirmDecision.confirm || !mounted) {
        return;
      }

      final payload = await _showEntryDialog(
        context,
        initialOtpAuth: otpAuth,
        router: _router,
      );
      if (payload == null || !mounted) {
        return;
      }

      context.read<VaultBloc>().add(
        CreateVaultEntry(
          title: payload.title,
          username: payload.username,
          password: payload.password,
          url: payload.url,
          notes: payload.notes,
          customFields: payload.customFields,
          attachmentPaths: payload.attachmentPaths,
        ),
      );
    } finally {
      _isHandlingOtpAuth = false;
      if (mounted && _otpAuthEventQueue.isNotEmpty) {
        final next = _otpAuthEventQueue.removeAt(0);
        unawaited(_handleOtpAuthEvent(next));
      }
    }
  }

  Future<void> _loadInactivityTimeout() async {
    if (!mounted) return;
    final databasePath = context.read<VaultBloc>().state.databasePath;
    final seconds = await di
        .sl<VaultSessionCoordinator>()
        .getInactivityLockTimeoutForPath(databasePath: databasePath);
    if (!mounted) return;
    setState(() => _inactivityTimeoutSeconds = seconds);
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    final seconds = _inactivityTimeoutSeconds;
    if (seconds == null || _isLocked || _isBackground) return;
    _inactivityTimer = Timer(
      Duration(seconds: seconds),
      _triggerInactivityLock,
    );
  }

  void _triggerInactivityLock() {
    if (!mounted || _isLocked) return;
    setState(() {
      _isLocked = true;
      _lockedAt = debugLockOverlayNowOverride();
    });
  }

  void _dismissLock() {
    if (!mounted) return;
    setState(() {
      _isLocked = false;
      _lockedAt = null;
    });
    _resetInactivityTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        _backgroundedAt ??= debugLockOverlayNowOverride();
        _inactivityTimer?.cancel();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= debugLockOverlayNowOverride();
        _inactivityTimer?.cancel();
        if (!_isLocked && mounted) {
          setState(() => _isBackground = true);
        }
        break;
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onAppResumed() {
    if (!mounted) return;

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;

    final elapsed = backgroundedAt != null
        ? DateTime.now().difference(backgroundedAt)
        : Duration.zero;
    final shouldLock = elapsed >= _VaultUiTokens.backgroundLockTimeout;

    setState(() {
      _isBackground = false;
      if (shouldLock) {
        _isLocked = true;
        _lockedAt = debugLockOverlayNowOverride();
      }
    });

    if (!shouldLock) {
      _resetInactivityTimer();
    }
  }

  void _maybeShowAutofillOnboardingDialog() {
    // Autofill v1 onboarding is intentionally disabled. Milestone 1 keeps the
    // Flutter shell clean while native Android/Apple/Desktop v2 integrations are
    // rebuilt against the new domain contracts.
  }

  Future<void> _closeCurrentDatabaseAndSelectAnother(
    BuildContext shellContext,
  ) async {
    final confirmed = await _showConfirmation(
      shellContext,
      title: 'Close database',
      body:
          'Close this database and return to file selection? Saved credentials for the current database will be removed.',
      confirmLabel: 'Close database',
    );

    if (confirmed != ConfirmDecision.confirm || !mounted) {
      return;
    }

    try {
      final databasePath = context.read<VaultBloc>().state.databasePath;
      await di.sl<VaultSessionCoordinator>().changeDatabase(
        currentDatabasePath: databasePath,
      );

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

  void _maybeShowAppleAutofillAssociationDialog(VaultState state) {
    if (state.pendingAppleAutofillAssociations.isEmpty ||
        state.isSaving ||
        state.isLoading) {
      return;
    }

    final pending = state.pendingAppleAutofillAssociations.first;
    if (_activeAppleAutofillAssociationDialogId == pending.id) {
      return;
    }
    if (_activeAppleAutofillAssociationDialogId != null) {
      return;
    }

    _activeAppleAutofillAssociationDialogId = pending.id;
    unawaited(
      _showAppleAutofillAssociationDialog(
        state: state,
        id: pending.id,
        entryId: pending.entryId,
        displayService: pending.displayService,
        serviceIdentifierValue: pending.serviceIdentifierValue,
      ),
    );
  }

  Future<void> _showAppleAutofillAssociationDialog({
    required VaultState state,
    required String id,
    required String entryId,
    required String displayService,
    required String serviceIdentifierValue,
  }) async {
    try {
      final entry = _findVaultEntryById(state, entryId);
      final target = _appleAutofillAssociationTargetLabel(
        displayService: displayService,
        serviceIdentifierValue: serviceIdentifierValue,
      );

      // spec-006 T7/FR-5: restyled into a `KvBottomSheet` with Target /
      // Entry / Username rows (screen 7) instead of the generic
      // title/body `AlertDialog` `_router.confirm` builds — same
      // `ConfirmationSurface` presentation (always a sheet), same
      // Confirm/Reject decision the pending-association flow already acts
      // on below, unchanged.
      final shouldLink = await _router.open<ConfirmDecision>(
        context: context,
        surface: ConfirmationSurface<ConfirmDecision>(
          builder: (surfaceContext) => _LinkAutofillCredentialSheet(
            target: target,
            entryTitle: entry == null
                ? null
                : (entry.title.isEmpty ? '(Untitled)' : entry.title),
            username: entry == null
                ? null
                : (entry.username.isEmpty ? 'No username' : entry.username),
            onReject: () => VaultOperationScope.of(
              surfaceContext,
            ).complete(ConfirmDecision.cancel),
            onLink: () => VaultOperationScope.of(
              surfaceContext,
            ).complete(ConfirmDecision.confirm),
          ),
        ),
      );

      if (!mounted || shouldLink == null) {
        return;
      }

      context.read<VaultBloc>().add(
        shouldLink == ConfirmDecision.confirm
            ? ConfirmAppleAutofillPendingAssociation(id)
            : RejectAppleAutofillPendingAssociation(id),
      );
    } finally {
      if (_activeAppleAutofillAssociationDialogId == id) {
        _activeAppleAutofillAssociationDialogId = null;
      }
    }
  }

  VaultEntry? _findVaultEntryById(VaultState state, String entryId) {
    for (final entry in state.allEntries) {
      if (entry.id == entryId) {
        return entry;
      }
    }
    return null;
  }

  String _appleAutofillAssociationTargetLabel({
    required String displayService,
    required String serviceIdentifierValue,
  }) {
    final display = displayService.trim();
    if (display.isNotEmpty) {
      return display;
    }

    final serviceIdentifier = serviceIdentifierValue.trim();
    if (serviceIdentifier.isNotEmpty) {
      return serviceIdentifier;
    }

    return 'Unknown service';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return VaultShellRouterScope(
      router: _router,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppBackgrounds.gradient(context),
              ),
            ),
            BlocListener<VaultBloc, VaultState>(
              listener: (context, state) {
                _markOtpAuthVaultAvailableIfReady(state);
                if (state.errorMessage != null &&
                    state.errorMessage!.isNotEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
                  context.read<VaultBloc>().add(const ClearVaultError());
                }
                if (state.infoMessage != null &&
                    state.infoMessage!.isNotEmpty) {
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
                  final needsReconnectAction = _syncErrorNeedsReconnectAction(
                    state.syncError!,
                  );
                  _showSyncSnackBar(
                    context,
                    state.syncError!,
                    status: state.syncStatus,
                    action: needsReconnectAction
                        ? SnackBarAction(
                            label: 'Reconnect',
                            onPressed: () {
                              context.read<VaultBloc>().add(
                                const ConnectGoogleDrive(),
                              );
                            },
                          )
                        : null,
                  );
                  context.read<VaultBloc>().add(const ClearVaultSyncFeedback());
                }
                if (state.pendingSyncConflict != null) {
                  _showSyncConflictDialog(context, state.pendingSyncConflict!);
                }
                _maybeShowAppleAutofillAssociationDialog(state);
              },
              child: BlocSelector<VaultBloc, VaultState, bool>(
                selector: (state) => state.isLoading,
                builder: (context, isLoading) {
                  if (isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return Stack(
                    children: [
                      Listener(
                        onPointerDown: (_) => _resetInactivityTimer(),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final spec = _VaultLayoutSpec.fromWidth(
                              constraints.maxWidth,
                            );

                            final vaultPane = Padding(
                              padding: EdgeInsets.fromLTRB(
                                spec.horizontalPadding,
                                topInset + spec.contentTopPadding,
                                spec.horizontalPadding,
                                spec.horizontalPadding,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _VaultSyncStatusStrip(
                                    onOpenRecycleBin: () {
                                      _showRecycleBinDialog(context);
                                    },
                                    onOpenDuplicates: () {
                                      _showDuplicatesDialog(context);
                                    },
                                    onChangeDatabase: () =>
                                        _closeCurrentDatabaseAndSelectAnother(
                                          context,
                                        ),
                                  ),
                                  const SizedBox(
                                    height: _VaultUiTokens.panelGap,
                                  ),
                                  // 009 / B005: browser-generated pending
                                  // secret awaiting the app's confirm/save.
                                  const _PendingGenerationBanner(),
                                  const Expanded(
                                    child: _VaultEntriesCardSection(),
                                  ),
                                ],
                              ),
                            );

                            return _VaultNavigationLayout(
                              width: constraints.maxWidth,
                              selectedDestination: _selectedDestination,
                              activePane: _activePane,
                              vaultPane: vaultPane,
                              onSelectDestination: _selectDestination,
                              onBackFromPane: _router.requestCancelCurrentPane,
                              onCloseDatabase: () =>
                                  _closeCurrentDatabaseAndSelectAnother(
                                    context,
                                  ),
                            );
                          },
                        ),
                      ),
                      BlocSelector<VaultBloc, VaultState, bool>(
                        selector: (state) => state.isSaving,
                        builder: (context, isSaving) {
                          if (!isSaving) {
                            return const SizedBox.shrink();
                          }

                          return const _SavingOverlay();
                        },
                      ),
                      if (_isBackground && !_isLocked) const PrivacyOverlay(),
                      if (_isLocked)
                        _LockOverlay(
                          databasePath: context
                              .read<VaultBloc>()
                              .state
                              .databasePath,
                          lockedAt: _lockedAt ?? debugLockOverlayNowOverride(),
                          onUnlocked: _dismissLock,
                          onCloseDatabase: () =>
                              _closeCurrentDatabaseAndSelectAnother(context),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _syncStatusStripBuildWhen(VaultState previous, VaultState current) {
  return previous.databasePath != current.databasePath ||
      previous.isDriveConnected != current.isDriveConnected ||
      previous.isDriveLinked != current.isDriveLinked ||
      previous.linkedDriveFileName != current.linkedDriveFileName ||
      previous.syncStatus != current.syncStatus ||
      previous.lastSyncAt != current.lastSyncAt ||
      previous.autoSyncEnabled != current.autoSyncEnabled ||
      previous.isSyncing != current.isSyncing ||
      previous.isOffline != current.isOffline ||
      previous.duplicateGroupCount != current.duplicateGroupCount;
}

bool _entriesCardBuildWhen(VaultState previous, VaultState current) {
  return previous.visibleEntries != current.visibleEntries ||
      previous.groups != current.groups ||
      previous.rootGroupId != current.rootGroupId ||
      previous.currentGroupId != current.currentGroupId ||
      previous.expandedGroupIds != current.expandedGroupIds ||
      previous.searchQuery != current.searchQuery;
}

class _VaultSyncStatusStrip extends StatelessWidget {
  const _VaultSyncStatusStrip({
    required this.onOpenRecycleBin,
    required this.onOpenDuplicates,
    required this.onChangeDatabase,
  });

  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenDuplicates;
  final Future<void> Function() onChangeDatabase;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: _syncStatusStripBuildWhen,
      builder: (context, state) {
        return _SyncStatusStrip(
          state: state,
          onRefresh: () {
            context.read<VaultBloc>().add(const RefreshVault());
          },
          onOpenRecycleBin: onOpenRecycleBin,
          onOpenDuplicates: onOpenDuplicates,
          onChangeDatabase: onChangeDatabase,
        );
      },
    );
  }
}

class _VaultEntriesCardSection extends StatelessWidget {
  const _VaultEntriesCardSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: _entriesCardBuildWhen,
      builder: (context, state) {
        return _EntriesCard(
          entries: state.visibleEntries,
          groups: state.groups,
          rootGroupId: state.rootGroupId,
          currentGroupId: state.currentGroupId,
          expandedGroupIds: state.expandedGroupIds,
          searchQuery: state.searchQuery,
        );
      },
    );
  }
}

enum VaultDestination { vault, health, sync, settings }

extension on VaultDestination {
  String get label => switch (this) {
    VaultDestination.vault => 'Vault',
    VaultDestination.health => 'Health',
    VaultDestination.sync => 'Sync',
    VaultDestination.settings => 'Settings',
  };

  AppGlyph get glyph => switch (this) {
    VaultDestination.vault => AppGlyph.folder,
    VaultDestination.health => AppGlyph.shieldCheck,
    VaultDestination.sync => AppGlyph.cloud,
    VaultDestination.settings => AppGlyph.settings,
  };
}

class _VaultNavigationLayout extends StatelessWidget {
  const _VaultNavigationLayout({
    required this.width,
    required this.selectedDestination,
    required this.activePane,
    required this.vaultPane,
    required this.onSelectDestination,
    required this.onBackFromPane,
    required this.onCloseDatabase,
  });

  final double width;
  final VaultDestination selectedDestination;
  final Widget? activePane;
  final Widget vaultPane;
  final ValueChanged<VaultDestination> onSelectDestination;
  final Future<bool> Function() onBackFromPane;
  final Future<void> Function() onCloseDatabase;

  @override
  Widget build(BuildContext context) {
    if (width < Breakpoints.mobile) {
      return Column(
        children: [
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey('vault-mobile-body'),
              child: activePane == null
                  ? _destinationBody()
                  : _VaultPaneHost(pane: activePane!, onBack: onBackFromPane),
            ),
          ),
          _VaultTabBar(
            selected: selectedDestination,
            onSelected: onSelectDestination,
          ),
        ],
      );
    }

    final railWidth = selectedDestination == VaultDestination.vault
        ? 76.0
        : 72.0;
    return Row(
      children: [
        SizedBox(
          key: const ValueKey('vault-rail'),
          width: railWidth,
          child: _VaultRail(
            selected: selectedDestination,
            onSelected: onSelectDestination,
          ),
        ),
        const _VaultVerticalDivider(),
        Expanded(child: _railBody(context, railWidth)),
      ],
    );
  }

  Widget _destinationBody() => switch (selectedDestination) {
    VaultDestination.vault => vaultPane,
    // spec-005: Health/Sync/Settings get first-class screens instead of a
    // placeholder button (FR-4/FR-1/FR-8). Padding/topInset match the
    // Vault pane so all four destinations align under the same header.
    VaultDestination.health => const _VaultDestinationScaffold(
      child: _VaultHealthDestination(),
    ),
    VaultDestination.sync => const _VaultDestinationScaffold(
      child: _VaultSyncDestination(),
    ),
    // spec-006 T1: was aliased to `_VaultBackupsDestination` as a spec-005
    // stopgap ("Settings" didn't have its own screen yet). Backups & import
    // is now reached from a row inside the real Settings destination.
    VaultDestination.settings => _VaultDestinationScaffold(
      child: _VaultSettingsDestination(onCloseDatabase: onCloseDatabase),
    ),
  };

  Widget _railBody(BuildContext context, double railWidth) {
    if (selectedDestination != VaultDestination.vault) {
      return KeyedSubtree(
        key: ValueKey('vault-${selectedDestination.name}-root'),
        child: _destinationBody(),
      );
    }
    if (width < 708) {
      return KeyedSubtree(
        key: const ValueKey('vault-single-pane'),
        child: activePane == null
            ? vaultPane
            : _VaultPaneHost(pane: activePane!, onBack: onBackFromPane),
      );
    }

    final available = width - railWidth - 1;
    final withFolders = width >= Breakpoints.tablet;
    final afterFolders = available - (withFolders ? 237 : 0);
    final listWidth = (afterFolders - 301).clamp(330.0, 352.0);
    return Row(
      children: [
        if (withFolders) ...[
          const SizedBox(
            key: ValueKey('vault-folder-pane'),
            width: 236,
            child: _VaultFolderPane(),
          ),
          const _VaultVerticalDivider(),
        ],
        SizedBox(
          key: const ValueKey('vault-list-pane'),
          width: listWidth,
          child: vaultPane,
        ),
        const _VaultVerticalDivider(),
        Expanded(
          key: const ValueKey('vault-detail-pane'),
          child: activePane == null
              ? const _EntryDetailEmptyState()
              : _VaultPaneHost(pane: activePane!, onBack: onBackFromPane),
        ),
      ],
    );
  }
}

class _VaultVerticalDivider extends StatelessWidget {
  const _VaultVerticalDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 1,
    child: ColoredBox(
      color: Theme.of(context).extension<KeyVaultColors>()!.divider,
    ),
  );
}

class _VaultTabBar extends StatelessWidget {
  const _VaultTabBar({required this.selected, required this.onSelected});

  final VaultDestination selected;
  final ValueChanged<VaultDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return ColoredBox(
      key: const ValueKey('vault-tab-bar'),
      color: colors.surface,
      child: SizedBox(
        height: 82,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 22),
          child: Row(
            children: [
              for (final destination in VaultDestination.values)
                Expanded(
                  child: Semantics(
                    selected: destination == selected,
                    button: true,
                    label: destination.label,
                    child: InkWell(
                      onTap: () => onSelected(destination),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          KvIcon(
                            glyph: destination.glyph,
                            size: 23,
                            color: destination == selected
                                ? colors.linkText
                                : colors.textSecondary,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            destination.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: destination == selected
                                  ? colors.linkText
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultRail extends StatelessWidget {
  const _VaultRail({required this.selected, required this.onSelected});

  final VaultDestination selected;
  final ValueChanged<VaultDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    Widget button(VaultDestination destination) => Semantics(
      selected: destination == selected,
      button: true,
      label: destination.label,
      child: SizedBox.square(
        dimension: 36,
        child: IconButton(
          tooltip: destination.label,
          padding: EdgeInsets.zero,
          onPressed: () => onSelected(destination),
          icon: KvIcon(
            glyph: destination.glyph,
            size: 22,
            color: destination == selected
                ? colors.linkText
                : colors.textSecondary,
          ),
        ),
      ),
    );

    return ColoredBox(
      color: colors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.actionFill,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: KvIcon(
                  glyph: AppGlyph.key,
                  size: 21,
                  color: colors.actionText,
                ),
              ),
              const SizedBox(height: 20),
              button(VaultDestination.vault),
              const SizedBox(height: 14),
              button(VaultDestination.health),
              const SizedBox(height: 14),
              button(VaultDestination.sync),
              const Spacer(),
              button(VaultDestination.settings),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultPaneHost extends StatelessWidget {
  const _VaultPaneHost({required this.pane, required this.onBack});

  final Widget pane;
  final Future<bool> Function() onBack;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          key: const ValueKey('vault-pane-back'),
          tooltip: 'Back',
          onPressed: onBack,
          icon: const KvIcon(glyph: AppGlyph.back),
        ),
      ),
      Expanded(child: pane),
    ],
  );
}

/// spec-005: thin wrapper giving the Health/Sync/Settings destination
/// screens the same top inset as the Vault pane (status bar clearance);
/// each screen manages its own horizontal padding/scrolling.
class _VaultDestinationScaffold extends StatelessWidget {
  const _VaultDestinationScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: topInset > 0 ? topInset : 8),
      child: child,
    );
  }
}

class _VaultFolderPane extends StatelessWidget {
  const _VaultFolderPane();

  @override
  Widget build(BuildContext context) => BlocBuilder<VaultBloc, VaultState>(
    buildWhen: (previous, current) =>
        previous.groups != current.groups ||
        previous.currentGroupId != current.currentGroupId,
    builder: (context, state) => ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Folders', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final group in state.groups.where((group) => !group.isRecycleBin))
          ListTile(
            selected: group.id == state.currentGroupId,
            leading: const KvIcon(glyph: AppGlyph.folder, size: 18),
            title: Text(group.name),
            onTap: () => context.read<VaultBloc>().add(OpenGroup(group.id)),
          ),
      ],
    ),
  );
}
