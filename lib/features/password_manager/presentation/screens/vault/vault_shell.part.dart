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

/// Padding metrics for the vault pane. spec-018 T047: this used to also
/// publish `isMobile` / `isCompact` / `isTablet` — three more width
/// comparisons, against a fourth threshold, that **nothing read**. They are
/// deleted rather than kept in step, because a spare notion of "is this wide?"
/// lying around is how the shell, the list and the router drifted apart in
/// the first place (D2). Layout decisions come from `VaultLayoutClass`; this
/// type now only carries padding.
class _VaultLayoutSpec {
  const _VaultLayoutSpec({
    required this.horizontalPadding,
    required this.contentTopPadding,
  });

  final double horizontalPadding;
  final double contentTopPadding;

  static _VaultLayoutSpec fromWidth(double width) {
    return _VaultLayoutSpec(
      horizontalPadding: width < _VaultLayoutBreakpoints.compactPhone
          ? 12.0
          : 16.0,
      contentTopPadding: width < _VaultLayoutBreakpoints.tabletMax ? 8 : 12,
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
  // Resolved once, at construction, and held for this State's lifetime.
  // `dispose()` must not reach back into the service locator: a widget's
  // teardown has to stay valid even while the DI graph is being torn down or
  // rebuilt around it (test teardown does exactly that today, and a future
  // "change database" flow that re-registered the graph would do it in
  // production). Reading `di.sl<T>()` at destruction time makes teardown
  // depend on a global still being registered, which is an ordering
  // assumption a `dispose()` cannot enforce.
  late final OtpAuthDeepLinkCoordinator _otpAuthCoordinator;
  VaultDestination _selectedDestination = VaultDestination.vault;
  Widget? _activePane;
  // spec-018 FR-003: the ONE owner of "which record is being looked at".
  // Previously `_EntriesCardState` kept a private copy for its own inline
  // split while the router published a pane from a different rule, so the
  // highlighted row and the visible detail could disagree (D3, D8). An id
  // only — never a `VaultEntry`, never a secret (Constitution I).
  String? _selectedEntryId;
  // True while a detail session is live, so selecting the same row twice is
  // a no-op instead of stacking a second session.
  bool _hasDetailSession = false;
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
  // spec-016 US3: one capture confirmation at a time, and one pull per
  // foregrounding — the app is launched again for every save request.
  bool _isAndroidAutofillSaveDialogOpen = false;
  bool _androidAutofillCapturePulled = false;
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
    // FR-002e: the folder column yields to the generator column, so the shell
    // must rebuild when the editor opens or closes it.
    _router.generatorColumnOpen.addListener(_onGeneratorColumnChanged);
    WidgetsBinding.instance.addObserver(this);
    _otpAuthCoordinator = di.sl<OtpAuthDeepLinkCoordinator>();
    _otpAuthSubscription = _otpAuthCoordinator.events.listen(
      _handleOtpAuthEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowAutofillOnboardingDialog();
      _loadInactivityTimeout();
    });
  }

  void _onGeneratorColumnChanged() {
    if (!mounted || _isDisposing) {
      return;
    }
    // Deferred rather than immediate: the editor clears this flag from its own
    // `dispose`, which runs while the element tree is locked, and a synchronous
    // `setState` there throws. The flag only selects a layout — never the
    // outcome of a pending write — so a frame's delay costs nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposing) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _isDisposing = true;
    _router.generatorColumnOpen.removeListener(_onGeneratorColumnChanged);
    _router.dispose();
    _inactivityTimer?.cancel();
    _otpAuthSubscription?.cancel();
    _otpAuthCoordinator.markVaultUnavailable();
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
    setState(() {
      _selectedDestination = destination;
      // spec-018 FR-003: leaving the Vault destination ends the detail
      // session, so the selection must go with it.
      _selectedEntryId = null;
      _hasDetailSession = false;
    });
  }

  /// spec-018 FR-001a: the records list reports a selection; the shell
  /// decides how it is presented. One entry point, so push and pane can
  /// never diverge again.
  Future<void> _selectEntry(BuildContext context, String entryId) async {
    if (_selectedEntryId == entryId && _hasDetailSession) {
      return;
    }
    // Close whatever detail (and anything stacked on it) is open before
    // opening the next one, so two records can never be shown at once
    // (FR-001). This also runs the editor's discard guard, so switching rows
    // mid-edit asks before throwing the edit away rather than silently
    // dropping it — the same protection a destination change already had.
    if (_hasDetailSession && !await _router.cancelForDestinationChange()) {
      return;
    }
    // Both guards are needed: `mounted`/`_isDisposing` for this State, and
    // `context.mounted` for the caller's context, which is the one handed to
    // the router below and belongs to the vault pane, not to this State.
    if (!mounted || _isDisposing || !context.mounted) {
      return;
    }
    setState(() {
      _selectedEntryId = entryId;
      _hasDetailSession = true;
    });
    await _openEntryDetailsSurface(context, entryId: entryId);
    // The session ended — by back, escape, completion, or the record being
    // deleted. FR-003/G4.4: whatever ended it clears the selection, so the
    // highlight can never outlive the detail it points at.
    if (!mounted || _isDisposing || _selectedEntryId != entryId) {
      return;
    }
    setState(() {
      _selectedEntryId = null;
      _hasDetailSession = false;
    });
  }

  /// spec-018 FR-002a/FR-002e: the layout class for this frame.
  ///
  /// It is the window width's class, with one adjustment: while the editor is
  /// showing its generator as a column, the folder column is dropped to make
  /// room. Below `VaultLayoutWidths.foldersAndGenerator` (1232) the two
  /// cannot coexist — at the 1024 design baseline they never do — and the
  /// design's rule is explicit that the folder column is what yields, never
  /// the records list, which is the screen's navigation spine.
  VaultLayoutClass _effectiveLayout(BuildContext context) {
    final layout = VaultLayoutClass.fromWidth(MediaQuery.sizeOf(context).width);
    if (layout == VaultLayoutClass.wideWithFolders &&
        _router.generatorColumnOpen.value &&
        MediaQuery.sizeOf(context).width <
            VaultLayoutWidths.foldersAndGenerator) {
      return VaultLayoutClass.wide;
    }
    return layout;
  }

  /// FR-014: a selection that has left the visible list is not a selection.
  ///
  /// Deletion does not come through here — a deleted record ends its own
  /// session from inside the detail (FR-007), which resolves the await in
  /// [_selectEntry]. This covers the case the detail cannot see: the record
  /// still exists but a search or folder change filtered it out of the list.
  void _dropSelectionIfNotVisible(Set<String> visibleEntryIds) {
    final selected = _selectedEntryId;
    if (selected == null || visibleEntryIds.contains(selected)) {
      return;
    }
    // Called from a build; cancelling a session mutates the router and can
    // publish a new pane, so defer it out of the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposing || _selectedEntryId != selected) {
        return;
      }
      unawaited(_router.cancelForDestinationChange());
    });
  }

  void _markOtpAuthVaultAvailableIfReady(VaultState state) {
    if (_otpAuthVaultMarkedAvailable ||
        state.isLoading ||
        state.rootGroupId == null) {
      return;
    }
    _otpAuthVaultMarkedAvailable = true;
    _otpAuthCoordinator.markVaultAvailable();
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
        // spec-011 FR-2: process termination drops the in-memory session
        // secret. Keystore contents are untouched in Slice 1.
        di.sl<VaultSessionCoordinator>().handleAppDetached();
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
    // A save request brings the app forward with a new capture waiting.
    _androidAutofillCapturePulled = false;
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

  void _maybePullAndroidAutofillCapture(
    BuildContext context,
    VaultState state,
  ) {
    if (_androidAutofillCapturePulled ||
        state.isLoading ||
        state.rootGroupId == null) {
      return;
    }
    _androidAutofillCapturePulled = true;
    context.read<VaultBloc>().add(const CheckAndroidAutofillCapture());
  }

  void _maybeShowAndroidAutofillSaveDialog(
    BuildContext context,
    VaultState state,
  ) {
    final pending = state.pendingAndroidAutofillSave;
    if (pending == null || _isAndroidAutofillSaveDialogOpen || state.isSaving) {
      return;
    }
    _isAndroidAutofillSaveDialogOpen = true;
    unawaited(_showAndroidAutofillSaveDialog(context, pending));
  }

  /// FR-008: says which of the two things is about to happen before anything
  /// is written, and names the entry when it is an update.
  Future<void> _showAndroidAutofillSaveDialog(
    BuildContext context,
    AndroidAutofillPendingSave pending,
  ) async {
    final bloc = context.read<VaultBloc>();
    final isUpdate = pending.kind == AndroidAutofillSaveKind.update;
    final username = pending.capture.username.trim();
    final target = pending.capture.association ?? 'this app';
    try {
      // Name the username in both cases: which account is being written is the
      // thing the user needs to check before saying yes.
      final account = username.isEmpty ? 'this account' : username;
      final decision = await _router.confirm(
        context: context,
        title: isUpdate ? 'Update this password?' : 'Save to your vault?',
        body: isUpdate
            // "history" is the KDBX record, not a screen in this app: there is
            // no history UI, so promising one sends the user looking for it.
            ? 'The password for $account in "${pending.displayTitle}" will be '
                  'replaced. The previous one is kept in the entry\'s KDBX '
                  'history, readable by any KeePass client.'
            : 'A new entry will be created for $account on $target.',
        cancelLabel: 'Not now',
        confirmLabel: isUpdate ? 'Update' : 'Save',
      );
      if (decision == ConfirmDecision.confirm) {
        bloc.add(const ConfirmAndroidAutofillCapture());
      } else if (decision == ConfirmDecision.cancel) {
        // An explicit no is remembered, so the same submission is not
        // offered again (FR-011).
        bloc.add(const DeclineAndroidAutofillCapture());
      } else {
        bloc.add(const CancelAndroidAutofillCapture());
      }
    } finally {
      _isAndroidAutofillSaveDialogOpen = false;
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
                  final needsReconnectAction = state.driveReconnectRequired;
                  _showSyncSnackBar(
                    context,
                    state.syncError!,
                    status: state.syncStatus,
                    action: needsReconnectAction
                        ? SnackBarAction(
                            label: 'Reconnect',
                            onPressed: () {
                              final bloc = context.read<VaultBloc>();
                              unawaited(
                                di
                                    .sl<GoogleDriveReconnectCoordinator>()
                                    .reconnect(
                                      owner: this,
                                      bloc: bloc,
                                      continuation:
                                          GoogleDriveReconnectContinuation
                                              .resumeSync,
                                      isOwnerActive: () => context.mounted,
                                    ),
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
                _maybePullAndroidAutofillCapture(context, state);
                _maybeShowAndroidAutofillSaveDialog(context, state);
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
                                  // spec-019 FR-013 / C-03-12: the database
                                  // status card used to sit here, inside the
                                  // records list, at every width. Its actions
                                  // did not go away — they moved to the header
                                  // below and to the folder column (FR-015).
                                  if (!_effectiveLayout(context)
                                      .hasFolderPane) ...[
                                    _VaultListHeader(
                                      onAddRecord: () =>
                                          _createRecordInCurrentFolder(context),
                                      onOpenSort: () =>
                                          _showSortSheet(context),
                                      onOpenRecycleBin: () {
                                        unawaited(
                                          _showRecycleBinDialog(context),
                                        );
                                      },
                                      onOpenDuplicates: () {
                                        unawaited(
                                          _showDuplicatesDialog(context),
                                        );
                                      },
                                      onChangeDatabase: () =>
                                          _closeCurrentDatabaseAndSelectAnother(
                                            context,
                                          ),
                                    ),
                                    const SizedBox(
                                      height: _VaultUiTokens.panelGap,
                                    ),
                                    // spec-019 FR-005 + plan Risks: the chip
                                    // row stands in wherever the folder column
                                    // does not fit — the phone, and the
                                    // 704-940 band whose artboard the design
                                    // still owes. That band had no folder
                                    // affordance at all once the list stopped
                                    // carrying folders, which would have
                                    // stranded every folder between 704 and
                                    // 940.
                                    const _VaultFolderChipRow(),
                                    const SizedBox(
                                      height: _VaultUiTokens.panelGap,
                                    ),
                                  ],
                                  // 009 / B005: browser-generated pending
                                  // secret awaiting the app's confirm/save.
                                  const _PendingGenerationBanner(),
                                  Expanded(
                                    child: _VaultEntriesCardSection(
                                      layout: _effectiveLayout(context),
                                      onAddRecord: () =>
                                          _createRecordInCurrentFolder(context),
                                      selectedEntryId: _selectedEntryId,
                                      onSelectEntry: (entryId) => unawaited(
                                        _selectEntry(context, entryId),
                                      ),
                                      onVisibleEntriesChanged:
                                          _dropSelectionIfNotVisible,
                                    ),
                                  ),
                                ],
                              ),
                            );

                            return _VaultNavigationLayout(
                              width: constraints.maxWidth,
                              // spec-018 FR-002a: one classification, from
                              // the window width, computed here and passed
                              // down. No descendant re-derives it.
                              layout: _effectiveLayout(context),
                              selectedDestination: _selectedDestination,
                              activePane: _activePane,
                              vaultPane: vaultPane,
                              onSelectDestination: _selectDestination,
                              onBackFromPane: _router.requestCancelCurrentPane,
                              onCloseDatabase: () =>
                                  _closeCurrentDatabaseAndSelectAnother(
                                    context,
                                  ),
                              onOpenRecycleBin: () {
                                unawaited(_showRecycleBinDialog(context));
                              },
                              onOpenDuplicates: () {
                                unawaited(_showDuplicatesDialog(context));
                              },
                              onChangeDatabase: () =>
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
      previous.currentGroupId != current.currentGroupId ||
      previous.folderDescendantIds != current.folderDescendantIds ||
      previous.sortBy != current.sortBy ||
      previous.searchQuery != current.searchQuery;
}

class _VaultEntriesCardSection extends StatelessWidget {
  const _VaultEntriesCardSection({
    required this.layout,
    required this.selectedEntryId,
    required this.onSelectEntry,
    required this.onVisibleEntriesChanged,
    required this.onAddRecord,
  });

  /// spec-018 FR-002a: the shell's single classification, passed down. The
  /// card uses it only to decide whether the sort control and the add
  /// affordance belong to its own header or to the list header above it — the
  /// two must never both render them (FR-014).
  final VaultLayoutClass layout;
  final VoidCallback onAddRecord;

  /// spec-018 FR-003: shell-owned, passed in. The card holds no selection
  /// state of its own.
  final String? selectedEntryId;
  final ValueChanged<String> onSelectEntry;
  final ValueChanged<Set<String>> onVisibleEntriesChanged;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: _entriesCardBuildWhen,
      builder: (context, state) {
        onVisibleEntriesChanged(
          state.visibleEntries.map((entry) => entry.id).toSet(),
        );
        // spec-019 FR-006i/FR-006j: the subtree of the selected folder,
        // minus the folder itself — what is left is exactly the set of
        // records on loan from a subfolder.
        final currentGroupId = state.currentGroupId;
        final subfolderIds = currentGroupId == null
            ? const <String>{}
            : (state.descendantIds(currentGroupId)..remove(currentGroupId));

        return _EntriesCard(
          showSortControl: layout.hasFolderPane,
          onAddRecord: onAddRecord,
          entries: state.visibleEntries,
          groups: state.groups,
          currentGroupId: currentGroupId,
          searchQuery: state.searchQuery,
          sortBy: state.sortBy,
          subfolderIds: subfolderIds,
          selectedEntryId: selectedEntryId,
          onSelectEntry: onSelectEntry,
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

  /// spec-019 FR-017 / DQ-4 — `ICONS.md` is normative and the artboards are
  /// hand-drawn approximations of it. Vault is a `lock`, not a folder: the
  /// destination is the vault, and folders are one thing inside it. Sync is
  /// `refresh-cw`, the act, not `cloud`, the place.
  AppGlyph get glyph => switch (this) {
    VaultDestination.vault => AppGlyph.lock,
    VaultDestination.health => AppGlyph.shieldCheck,
    VaultDestination.sync => AppGlyph.sync,
    VaultDestination.settings => AppGlyph.settings,
  };
}

class _VaultNavigationLayout extends StatelessWidget {
  const _VaultNavigationLayout({
    required this.width,
    required this.selectedDestination,
    required this.activePane,
    required this.vaultPane,
    required this.layout,
    required this.onSelectDestination,
    required this.onBackFromPane,
    required this.onCloseDatabase,
    required this.onOpenRecycleBin,
    required this.onOpenDuplicates,
    required this.onChangeDatabase,
  });

  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenDuplicates;
  final Future<void> Function() onChangeDatabase;

  final double width;

  /// spec-018 FR-002a: computed once by the shell from the window width and
  /// passed in. Nothing below this widget re-measures to pick a layout.
  final VaultLayoutClass layout;
  final VaultDestination selectedDestination;
  final Widget? activePane;
  final Widget vaultPane;
  final ValueChanged<VaultDestination> onSelectDestination;
  final Future<bool> Function() onBackFromPane;
  final Future<void> Function() onCloseDatabase;

  @override
  Widget build(BuildContext context) {
    if (layout.hasTabBar) {
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

    // spec-018 FR-002b: one rail width. The vault variant's `76` was drift
    // in a single artboard, corrected to the design's stated 72 — see the
    // spec's design-decisions section.
    const railWidth = VaultColumns.rail;
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
    // spec-018 FR-002d: below the derived pane threshold the rail is shown
    // but the detail still pushes, because the design's own columns do not
    // fit. This replaced a bare `708`, which was this same arithmetic done
    // with the pre-correction rail width of 76.
    if (!layout.hasDetailPane) {
      return KeyedSubtree(
        key: const ValueKey('vault-single-pane'),
        child: activePane == null
            ? vaultPane
            : _VaultPaneHost(pane: activePane!, onBack: onBackFromPane),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // The normative widths are minimums, not fixed sizes: on a wide
        // window the surplus is split between the columns (capped) instead
        // of all landing in the detail pane while titles truncate.
        final base =
            (layout.hasFolderPane
                ? VaultColumns.folders + VaultColumns.divider
                : 0) +
            VaultColumns.list +
            VaultColumns.detailMin +
            VaultColumns.divider;
        final extra = (constraints.maxWidth - base).clamp(0.0, double.infinity);
        final folderWidth = (VaultColumns.folders + extra * 0.15).clamp(
          VaultColumns.folders,
          VaultColumns.foldersMax,
        );
        final listWidth = (VaultColumns.list + extra * 0.30).clamp(
          VaultColumns.list,
          VaultColumns.listMax,
        );
        return Row(
      children: [
        if (layout.hasFolderPane) ...[
          SizedBox(
            key: const ValueKey('vault-folder-pane'),
            width: folderWidth,
            child: const _VaultFolderColumn(),
          ),
          const _VaultVerticalDivider(),
        ],
        SizedBox(
          key: const ValueKey('vault-list-pane'),
          width: listWidth,
          child: vaultPane,
        ),
        const _VaultVerticalDivider(),
        // FR-002c: the detail pane is persistent — always present, showing
        // the empty state when nothing is selected, never a pane that only
        // materialises once a surface opens.
        Expanded(
          key: const ValueKey('vault-detail-pane'),
          child: activePane == null
              ? const _EntryDetailEmptyState()
              : _VaultPaneHost(pane: activePane!, onBack: onBackFromPane),
        ),
      ],
        );
      },
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
                          // FR-018: same treatment as the rail — one selected
                          // recipe for the chrome, whichever shape it takes.
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: destination == selected
                                  ? AppColors.accent200
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                AppRadii.iconSquare,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              child: KvIcon(
                                glyph: destination.glyph,
                                size: 23,
                                color: destination == selected
                                    ? AppColors.accent800
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            destination.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: destination == selected
                                  ? AppColors.accent800
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
    Widget button(VaultDestination destination) {
      final isSelected = destination == selected;
      return Semantics(
        selected: isSelected,
        button: true,
        label: destination.label,
        child: SizedBox.square(
          dimension: 36,
          child: DecoratedBox(
            // spec-019 FR-018 / C-03-14: the selected destination is a filled
            // tile, not a recoloured glyph. The `Semantics(selected:)` above
            // stays exactly as it was — the fill is in addition to it, never
            // instead of it (Constitution V).
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accent200 : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.iconSquare),
            ),
            child: IconButton(
              tooltip: destination.label,
              padding: EdgeInsets.zero,
              onPressed: () => onSelected(destination),
              icon: KvIcon(
                glyph: destination.glyph,
                size: 22,
                color: isSelected ? AppColors.accent800 : colors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: colors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              // The mark carries its own colour; a filled tile behind it
              // fought the ring (orange on orange), so the rail shows the
              // mark alone at the size the tile used to occupy.
              const SizedBox(
                width: 38,
                height: 38,
                child: Center(child: _VaultAppMark(size: 30)),
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

/// Marks the subtree as living inside [_VaultPaneHost].
///
/// The host draws the back affordance for whatever it hosts, so a pane must
/// not draw a second one. Asking "am I in a pane?" structurally is the fix
/// for deriving it from the window width: the presentation is chosen when the
/// surface opens, so a resize made the width answer disagree with the tree
/// that was actually mounted — and both back buttons appeared at once.
class _VaultPaneScope extends InheritedWidget {
  const _VaultPaneScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_VaultPaneScope>() != null;

  @override
  bool updateShouldNotify(_VaultPaneScope oldWidget) => false;
}

class _VaultPaneHost extends StatelessWidget {
  const _VaultPaneHost({required this.pane, required this.onBack});

  final Widget pane;
  final Future<bool> Function() onBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            // PIXEL_SPEC §2: icon buttons are 36 px circles on the surface
            // ramp with a 17-19 px glyph, never a bare Material button.
            child: SizedBox.square(
              dimension: 36,
              child: IconButton(
                key: const ValueKey('vault-pane-back'),
                tooltip: 'Back',
                onPressed: onBack,
                style: IconButton.styleFrom(
                  backgroundColor: colors.surface,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                icon: KvIcon(
                  glyph: AppGlyph.back,
                  size: 19,
                  color: colors.iconNeutral,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: _VaultPaneScope(child: pane)),
      ],
    );
  }
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

/// spec-019 T035 / FR-014 — the vault's screen header, wherever there is no
/// folder column to carry the database's name.
///
/// `Vault`, then the record count and the database file name, then — from the
/// right — the add affordance, the sort affordance, and the database actions
/// the status card used to carry (FR-015). Each target is 44 px.
class _VaultListHeader extends StatelessWidget {
  const _VaultListHeader({
    required this.onAddRecord,
    required this.onOpenSort,
    required this.onOpenRecycleBin,
    required this.onOpenDuplicates,
    required this.onChangeDatabase,
  });

  final VoidCallback onAddRecord;
  final VoidCallback onOpenSort;
  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenDuplicates;
  final Future<void> Function() onChangeDatabase;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: (previous, current) =>
          previous.visibleEntries.length != current.visibleEntries.length ||
          previous.databasePath != current.databasePath ||
          _databaseActionsBuildWhen(previous, current),
      builder: (context, state) {
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vault',
                    style: AppTextStyles.screenTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${state.visibleEntries.length} items · '
                    '${path.basename(state.databasePath)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.meta.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _VaultDatabaseActions(
              state: state,
              onOpenRecycleBin: onOpenRecycleBin,
              onOpenDuplicates: onOpenDuplicates,
              onChangeDatabase: onChangeDatabase,
            ),
            _VaultHeaderIconButton(
              tooltip: 'Sort records',
              glyph: AppGlyph.sort,
              onPressed: onOpenSort,
            ),
            _VaultHeaderIconButton(
              tooltip: 'Add record',
              glyph: AppGlyph.add,
              filled: true,
              onPressed: onAddRecord,
            ),
          ],
        );
      },
    );
  }
}

class _VaultHeaderIconButton extends StatelessWidget {
  const _VaultHeaderIconButton({
    required this.tooltip,
    required this.glyph,
    required this.onPressed,
    this.filled = false,
    this.fillSize = 36,
  });

  final String tooltip;
  final AppGlyph glyph;
  final VoidCallback onPressed;

  /// Diameter of the visible filled circle; the 44 px target is unchanged.
  final double fillSize;

  /// spec-019 C-03-01: the add affordance is an `accent-300` filled button,
  /// not a bare glyph — it is the header's one primary action and the design
  /// gives it the only fill in the row. The 44 px target is the button's, not
  /// the fill's: the visible circle is 36 (PIXEL_SPEC §2).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: filled
            ? IconButton.styleFrom(
                backgroundColor: AppColors.accent300,
                fixedSize: Size.square(fillSize),
                shape: const CircleBorder(),
              )
            : null,
        icon: KvIcon(
          glyph: glyph,
          size: 19,
          color: filled ? AppColors.accent900 : colors.textPrimary,
        ),
      ),
    );
  }
}

/// spec-019 FR-015 — the database-level actions the status card carried.
///
/// Not re-implemented: this is the card's own primary button and its own
/// overflow, moved. The sheet behind the overflow is `_VaultSettingsSheet`,
/// unchanged, so `Lock vault`, `Change database`, `Database settings`,
/// `Recycle bin` and `Manage duplicates` keep both their wording and their
/// interaction count.
class _VaultDatabaseActions extends StatelessWidget {
  const _VaultDatabaseActions({
    required this.state,
    required this.onOpenRecycleBin,
    required this.onOpenDuplicates,
    required this.onChangeDatabase,
  });

  final VaultState state;
  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenDuplicates;
  final Future<void> Function() onChangeDatabase;

  @override
  Widget build(BuildContext context) {
    final isDriveSyncReady = state.isDriveConnected && state.isDriveLinked;
    final isSyncInProgress =
        state.syncStatus == DatabaseSyncStatus.syncing || state.isSyncing;
    final isBusy = isDriveSyncReady && isSyncInProgress;
    // Verbatim from the status card (Constitution VI).
    final tooltip = isBusy
        ? 'Sync in progress'
        : isDriveSyncReady
        ? 'Sync database'
        : 'Refresh vault';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            onPressed: isBusy
                ? null
                : () {
                    final bloc = context.read<VaultBloc>();
                    bloc.add(
                      isDriveSyncReady
                          ? const SyncCurrentDatabaseNow()
                          : const RefreshVault(),
                    );
                  },
            icon: _SyncStripActionIcon(
              icon: isDriveSyncReady ? AppIcons.sync : AppIcons.refresh,
              highlighted: isDriveSyncReady,
              spinning: isSyncInProgress,
            ),
          ),
        ),
        _SyncStripMenuButton(
          state: state,
          canConfigureAndroidAutofill: false,
          canConfigureBrowserAutofill: BrowserSetupScreen.shouldShow,
          onOpenRecycleBin: onOpenRecycleBin,
          onOpenDuplicates: onOpenDuplicates,
          onChangeDatabase: onChangeDatabase,
        ),
      ],
    );
  }
}

bool _databaseActionsBuildWhen(VaultState previous, VaultState current) {
  return previous.isDriveConnected != current.isDriveConnected ||
      previous.isDriveLinked != current.isDriveLinked ||
      previous.linkedDriveFileName != current.linkedDriveFileName ||
      previous.syncStatus != current.syncStatus ||
      previous.lastSyncAt != current.lastSyncAt ||
      previous.autoSyncEnabled != current.autoSyncEnabled ||
      previous.isSyncing != current.isSyncing ||
      previous.isOffline != current.isOffline ||
      previous.duplicateGroupCount != current.duplicateGroupCount;
}

/// spec-019 T051 / FR-016 — the KeyVault mark, as artwork.
///
/// The rail used to show `AppGlyph.key`, a Lucide glyph standing in for the
/// app's own mark (C-SH-03). The mark is a real asset and this renders it,
/// tinted to the tile's foreground so it works on both themes.
class _VaultAppMark extends StatelessWidget {
  const _VaultAppMark({required this.size});

  /// The full-colour mark (verbatim copy of the design master
  /// `specs/_design/keyvault-mark-foreground.svg`), rendered untinted so the
  /// rail shows the app's actual identity, not a silhouette.
  static const String assetPath = 'assets/logo/keyvault-mark-color.svg';

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      semanticsLabel: 'KeyVault',
    );
  }
}
