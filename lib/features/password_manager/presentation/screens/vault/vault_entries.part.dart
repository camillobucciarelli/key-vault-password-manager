part of '../vault_screen.dart';

/// spec-018 FR-010/FR-001a: the ONE way a record detail is opened, from every
/// origin — the records list, the health-category list, duplicates, search.
///
/// It opens an `EntrySurface`, so the shell router decides the presentation
/// (pushed screen when narrow, the persistent detail pane when wide) and owns
/// dismissal and nesting. Callers do not choose, and do not supply their own
/// action wiring: the actions are attached here so two origins cannot offer
/// different menus for the same record, which is exactly what D9 was.
///
/// The action callback receives the hosted surface's own (descendant)
/// context, never the caller's: the caller's context can be deactivated by
/// the time an action is picked from a menu inside the surface, which made
/// every dialog opened from here (Delete, Attachments, Move) throw "Looking
/// up a deactivated widget's ancestor" once the entries list rebuilt.
Future<void> _openEntryDetailsSurface(
  BuildContext context, {
  required String entryId,
}) {
  final bloc = context.read<VaultBloc>();
  return VaultShellRouterScope.of(context).open<VaultDone>(
    context: context,
    surface: EntrySurface<VaultDone>(
      builder: (surfaceContext) => BlocProvider.value(
        value: bloc,
        child: _EntryDetailsPage(
          entryId: entryId,
          onSelectedAction: (action) => unawaited(
            _EntriesCardState._handleEntryActionOn(
              surfaceContext,
              bloc,
              entryId,
              action,
              bloc.state.groups,
            ),
          ),
        ),
      ),
    ),
  );
}

class _EntriesCard extends StatefulWidget {
  const _EntriesCard({
    required this.entries,
    required this.groups,
    required this.rootGroupId,
    required this.currentGroupId,
    required this.expandedGroupIds,
    required this.searchQuery,
    required this.selectedEntryId,
    required this.onSelectEntry,
  });

  final List<VaultEntry> entries;
  final List<VaultGroup> groups;
  final String? rootGroupId;
  final String? currentGroupId;
  final List<String> expandedGroupIds;
  final String searchQuery;

  /// spec-018 FR-001a/FR-003: selection is shell-owned. This card renders no
  /// detail of its own and keeps no selection state — it marks the row the
  /// shell says is selected and reports activations back.
  final String? selectedEntryId;
  final ValueChanged<String> onSelectEntry;

  @override
  State<_EntriesCard> createState() => _EntriesCardState();
}

class _EntriesCardState extends State<_EntriesCard> {
  late final ScrollController _entriesScrollController;
  late final TextEditingController _searchController;
  // Groups manually collapsed by the user while a search is active.
  // Cleared whenever the search query changes.
  final _searchCollapsed = <String>{};

  @override
  void initState() {
    super.initState();
    _entriesScrollController = ScrollController();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void dispose() {
    _entriesScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _EntriesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _searchController.text) {
      _searchController.value = TextEditingValue(
        text: widget.searchQuery,
        selection: TextSelection.collapsed(offset: widget.searchQuery.length),
      );
    }
    if (widget.searchQuery != oldWidget.searchQuery) {
      _searchCollapsed.clear();
    }
    // spec-018: the "selection no longer exists" cleanup that used to live
    // here moved to the shell, which is now the single owner (FR-003). A
    // second copy here is what let the highlight and the detail disagree.
  }

  void _toggleGroup(BuildContext context, String groupId, bool isSearchActive) {
    if (isSearchActive) {
      setState(() {
        if (_searchCollapsed.contains(groupId)) {
          _searchCollapsed.remove(groupId);
        } else {
          _searchCollapsed.add(groupId);
        }
      });
    } else {
      context.read<VaultBloc>().add(ToggleVaultGroupExpanded(groupId));
    }
  }

  Future<void> _handleCreateEntry(
    BuildContext context, {
    String? targetGroupId,
  }) async {
    final payload = await _showEntryDialog(context);
    if (payload != null && mounted) {
      final bloc = this.context.read<VaultBloc>();
      if (targetGroupId != null) {
        bloc.add(OpenGroup(targetGroupId));
      }
      bloc.add(
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
    }
  }

  Future<void> _handleCreateFolder(
    BuildContext context, {
    String? targetGroupId,
  }) async {
    final name = await _showGroupDialog(context);
    if (name == null || name.name.trim().isEmpty || !mounted) {
      return;
    }

    final bloc = this.context.read<VaultBloc>();
    if (targetGroupId != null) {
      bloc.add(OpenGroup(targetGroupId));
    }
    bloc.add(CreateVaultGroup(name.name.trim()));
  }

  Future<void> _handleFolderAction(
    BuildContext context, {
    required VaultGroup group,
    required _FolderAction action,
  }) async {
    switch (action) {
      case _FolderAction.addRecord:
        await _handleCreateEntry(context, targetGroupId: group.id);
        break;
      case _FolderAction.addSubfolder:
        await _handleCreateFolder(context, targetGroupId: group.id);
        break;
      case _FolderAction.rename:
        await _handleChildGroupAction(
          context,
          group: group,
          action: _ChildGroupAction.rename,
          allGroups: widget.groups,
        );
        break;
      case _FolderAction.move:
        await _handleChildGroupAction(
          context,
          group: group,
          action: _ChildGroupAction.move,
          allGroups: widget.groups,
        );
        break;
      case _FolderAction.delete:
        await _handleChildGroupAction(
          context,
          group: group,
          action: _ChildGroupAction.delete,
          allGroups: widget.groups,
        );
        break;
    }
  }

  /// spec-018 FR-005/FR-006 (D4, D5) — the record-action contract, C5.
  ///
  /// Two bugs lived in the previous shape and both are structural:
  ///
  ///  * It took a `VaultEntry` **value**, captured when the surface opened.
  ///    An edit therefore wrote fields as they were before any earlier edit
  ///    landed, so a second save silently reverted the first (D4). It now
  ///    takes an **id** and resolves the entry at confirmation time.
  ///  * It guarded on `_EntriesCardState.mounted` and dispatched through
  ///    `this.context`. When the action ran from a pushed surface and the
  ///    list rebuilt underneath, the guard was false: the user confirmed and
  ///    the event was never sent, with no error (D5). The bloc is now
  ///    captured *before* the first await — it outlives every surface — and
  ///    liveness is judged on the surface's own context.
  static Future<void> _handleEntryActionOn(
    BuildContext surfaceContext,
    VaultBloc bloc,
    String entryId,
    _EntryAction action,
    List<VaultGroup> groups,
  ) async {
    // `bloc` is passed in, already resolved, rather than read from
    // `surfaceContext`: the surface context is the ancestor of the
    // `BlocProvider.value` that hosts the detail, so a `read` here finds
    // nothing. Passing it also satisfies G5.2 by construction — the handle
    // is captured before any await and outlives every surface in the stack.
    VaultEntry? currentEntry() {
      for (final entry in bloc.state.allEntries) {
        if (entry.id == entryId) return entry;
      }
      return null;
    }

    final entry = currentEntry();
    if (entry == null) {
      // G5.7: the record went away before the action started.
      bloc.add(const ReportVaultActionAbandoned());
      return;
    }

    switch (action) {
      case _EntryAction.edit:
        final payload = await _showEntryDialog(surfaceContext, initial: entry);
        if (payload == null) {
          return;
        }
        if (currentEntry() == null) {
          bloc.add(const ReportVaultActionAbandoned());
          return;
        }
        bloc.add(
          UpdateVaultEntry(
            entryId: entryId,
            title: payload.title,
            username: payload.username,
            password: payload.password,
            url: payload.url,
            notes: payload.notes,
            customFields: payload.customFields,
          ),
        );
      case _EntryAction.move:
        final target = await _showMoveTargetDialog(surfaceContext, groups);
        if (target == null) {
          return;
        }
        if (currentEntry() == null) {
          bloc.add(const ReportVaultActionAbandoned());
          return;
        }
        bloc.add(
          MoveVaultEntry(entryId: entryId, targetGroupId: target.groupId),
        );
      case _EntryAction.attachments:
        // Re-read: the attachment list may have changed since the surface
        // opened, and showing a stale one would act on stale attachments.
        final fresh = currentEntry();
        if (fresh == null) {
          bloc.add(const ReportVaultActionAbandoned());
          return;
        }
        await _showAttachmentsDialog(surfaceContext, fresh);
      case _EntryAction.delete:
        final confirmed = await _showDeleteConfirm(
          surfaceContext,
          label: 'Move this record to recycle bin?',
        );
        if (!confirmed) {
          return;
        }
        if (currentEntry() == null) {
          bloc.add(const ReportVaultActionAbandoned());
          return;
        }
        bloc.add(DeleteVaultEntry(entryId));
    }
  }

  Future<void> _handleEntryAction(
    BuildContext context,
    String entryId,
    _EntryAction action,
  ) => _handleEntryActionOn(
    context,
    context.read<VaultBloc>(),
    entryId,
    action,
    widget.groups,
  );

  /// spec-018 FR-001a: activating a row reports the id upward. The card no
  /// longer decides how — or whether — a detail is shown; that is the
  /// shell's single decision, so push and pane cannot diverge (D1, D9).
  void _openEntry(VaultEntry entry) => widget.onSelectEntry(entry.id);

  Widget _buildEntriesList(BuildContext context) {
    final normalizedQuery = _normalizeSearchText(widget.searchQuery);
    final compactQuery = normalizedQuery.replaceAll(' ', '');
    final isSearchActive = normalizedQuery.isNotEmpty;

    final groups = widget.groups
        .where((group) => !group.isRecycleBin)
        .toList(growable: false);
    final byId = {for (final group in groups) group.id: group};
    final byParent = <String?, List<VaultGroup>>{};
    for (final group in groups) {
      byParent.putIfAbsent(group.parentId, () => <VaultGroup>[]).add(group);
    }
    for (final children in byParent.values) {
      children.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    final entriesByGroup = <String, List<VaultEntry>>{};
    for (final entry in widget.entries) {
      entriesByGroup
          .putIfAbsent(entry.groupId, () => <VaultEntry>[])
          .add(entry);
    }

    final autoExpanded = <String>{};
    bool groupMatchesQuery(VaultGroup group) {
      return isSearchActive &&
          _matchesSearchValue(group.name, normalizedQuery, compactQuery);
    }

    if (isSearchActive) {
      for (final group in groups) {
        if (!groupMatchesQuery(group)) {
          continue;
        }

        autoExpanded.add(group.id);
        var cursorId = group.parentId;
        while (cursorId != null) {
          autoExpanded.add(cursorId);
          final parent = byId[cursorId];
          cursorId = parent?.parentId;
        }
      }

      for (final entry in widget.entries) {
        var cursorId = entry.groupId;
        while (true) {
          final cursor = byId[cursorId];
          if (cursor == null) {
            break;
          }
          autoExpanded.add(cursor.id);
          final parentId = cursor.parentId;
          if (parentId == null) {
            break;
          }
          cursorId = parentId;
        }
      }
    }

    final visibleGroupMemo = <String, bool>{};
    bool groupHasVisibleContent(String groupId) {
      final cached = visibleGroupMemo[groupId];
      if (cached != null) {
        return cached;
      }

      final hasEntries =
          (entriesByGroup[groupId] ?? const <VaultEntry>[]).isNotEmpty;
      if (hasEntries) {
        visibleGroupMemo[groupId] = true;
        return true;
      }

      final group = byId[groupId];
      if (group != null && groupMatchesQuery(group)) {
        visibleGroupMemo[groupId] = true;
        return true;
      }

      final children = byParent[groupId] ?? const <VaultGroup>[];
      for (final child in children) {
        if (groupHasVisibleContent(child.id)) {
          visibleGroupMemo[groupId] = true;
          return true;
        }
      }

      visibleGroupMemo[groupId] = false;
      return false;
    }

    final rootId = widget.rootGroupId;
    final treeItems = <_EntryTreeNode>[];
    final manualExpanded = widget.expandedGroupIds.toSet();

    void appendGroup(VaultGroup group, int depth) {
      if (isSearchActive && !groupHasVisibleContent(group.id)) {
        return;
      }

      final isExpanded =
          (manualExpanded.contains(group.id) ||
              autoExpanded.contains(group.id)) &&
          !_searchCollapsed.contains(group.id);
      final isCurrent = widget.currentGroupId == group.id;
      final children = byParent[group.id] ?? const <VaultGroup>[];
      final records = entriesByGroup[group.id] ?? const <VaultEntry>[];

      treeItems.add(
        _EntryTreeNode.group(
          group: group,
          depth: depth,
          isExpanded: isExpanded,
          isCurrent: isCurrent,
          isRoot: group.id == rootId,
          childGroupsCount: children.length,
          recordsCount: records.length,
        ),
      );

      if (!isExpanded) {
        return;
      }

      for (final child in children) {
        appendGroup(child, depth + 1);
      }

      for (final entry in records) {
        final isSelected = widget.selectedEntryId == entry.id;
        treeItems.add(
          _EntryTreeNode.entry(
            entry: entry,
            depth: depth + 1,
            isSelected: isSelected,
          ),
        );
      }
    }

    final rootGroup = rootId == null ? null : byId[rootId];
    if (rootGroup != null) {
      appendGroup(rootGroup, 0);
    } else {
      final fallbackRootChildren = byParent[null] ?? const <VaultGroup>[];
      for (final group in fallbackRootChildren) {
        appendGroup(group, 0);
      }
    }

    if (treeItems.isEmpty && widget.entries.isNotEmpty) {
      for (final entry in widget.entries) {
        treeItems.add(
          _EntryTreeNode.entry(
            entry: entry,
            depth: 0,
            isSelected: widget.selectedEntryId == entry.id,
          ),
        );
      }
    }

    if (treeItems.isEmpty) {
      final emptyState = _RecordsEmptyState(
        searchQuery: widget.searchQuery,
        onClearSearch: widget.searchQuery.isNotEmpty
            ? () {
                context.read<VaultBloc>().add(const ClearVaultSearchQuery());
              }
            : null,
      );

      return LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.maxHeight > 32
              ? constraints.maxHeight - 32
              : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(child: emptyState),
            ),
          );
        },
      );
    }

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom + 12;
    final list = ListView.separated(
      controller: _entriesScrollController,
      padding: EdgeInsets.only(bottom: bottomInset),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: treeItems.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _VaultUiTokens.recordListSpacing),
      itemBuilder: (context, index) {
        final node = treeItems[index];
        return node.when(
          group:
              (
                group,
                depth,
                isExpanded,
                isCurrent,
                isRoot,
                childGroupsCount,
                recordsCount,
              ) {
                return Padding(
                  padding: EdgeInsets.only(left: depth * 14.0),
                  child: _FolderListItem(
                    group: group,
                    isExpanded: isExpanded,
                    isCurrent: isCurrent,
                    isRoot: isRoot,
                    childGroupsCount: childGroupsCount,
                    recordsCount: recordsCount,
                    onOpen: () =>
                        _toggleGroup(context, group.id, isSearchActive),
                    onToggleExpand: () =>
                        _toggleGroup(context, group.id, isSearchActive),
                    onSelectedAction: (action) async {
                      await _handleFolderAction(
                        context,
                        group: group,
                        action: action,
                      );
                    },
                  ),
                );
              },
          entry: (entry, depth, isSelected) {
            return Padding(
              padding: EdgeInsets.only(left: depth * 14.0),
              child: _RecordListItem(
                entry: entry,
                isSelected: isSelected,
                onOpen: () => _openEntry(entry),
                onSelectedAction: (action) {
                  _handleEntryAction(context, entry.id, action);
                },
              ),
            );
          },
        );
      },
    );

    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        FocusScope.of(context).unfocus();
        return false;
      },
      child: Scrollbar(controller: _entriesScrollController, child: list),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(_VaultUiTokens.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final searchField = TextFormField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search records and folders',
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: widget.searchQuery.isNotEmpty
                      ? Tooltip(
                          message: 'Clear search',
                          ignorePointer: true,
                          child: IconButton(
                            onPressed: () {
                              context.read<VaultBloc>().add(
                                const ClearVaultSearchQuery(),
                              );
                            },
                            icon: const Icon(AppIcons.close),
                          ),
                        )
                      : null,
                ),
                onChanged: (value) {
                  context.read<VaultBloc>().add(UpdateVaultSearchQuery(value));
                },
              );

              return searchField;
            },
          ),
          const SizedBox(height: 10),
          // spec-018 D1/FR-001a: this used to branch on the card's OWN
          // constraints and render a second, router-unaware detail beside
          // the list. That second mechanism is why selection, dismissal and
          // nesting drifted apart on wide windows. The card now renders the
          // list and nothing else; the shell owns the detail.
          Expanded(child: _buildEntriesList(context)),
        ],
      ),
    );

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_VaultUiTokens.cardRadius),
      ),
      child: content,
    );
  }
}

class _EntryTreeNode {
  const _EntryTreeNode._({
    required this.group,
    required this.entry,
    required this.depth,
    required this.isExpanded,
    required this.isCurrent,
    required this.isRoot,
    required this.childGroupsCount,
    required this.recordsCount,
    required this.isSelected,
  });

  factory _EntryTreeNode.group({
    required VaultGroup group,
    required int depth,
    required bool isExpanded,
    required bool isCurrent,
    required bool isRoot,
    required int childGroupsCount,
    required int recordsCount,
  }) {
    return _EntryTreeNode._(
      group: group,
      entry: null,
      depth: depth,
      isExpanded: isExpanded,
      isCurrent: isCurrent,
      isRoot: isRoot,
      childGroupsCount: childGroupsCount,
      recordsCount: recordsCount,
      isSelected: false,
    );
  }

  factory _EntryTreeNode.entry({
    required VaultEntry entry,
    required int depth,
    required bool isSelected,
  }) {
    return _EntryTreeNode._(
      group: null,
      entry: entry,
      depth: depth,
      isExpanded: false,
      isCurrent: false,
      isRoot: false,
      childGroupsCount: 0,
      recordsCount: 0,
      isSelected: isSelected,
    );
  }

  final VaultGroup? group;
  final VaultEntry? entry;
  final int depth;
  final bool isExpanded;
  final bool isCurrent;
  final bool isRoot;
  final int childGroupsCount;
  final int recordsCount;
  final bool isSelected;

  T when<T>({
    required T Function(
      VaultGroup group,
      int depth,
      bool isExpanded,
      bool isCurrent,
      bool isRoot,
      int childGroupsCount,
      int recordsCount,
    )
    group,
    required T Function(VaultEntry entry, int depth, bool isSelected) entry,
  }) {
    final resolvedGroup = this.group;
    if (resolvedGroup != null) {
      return group(
        resolvedGroup,
        depth,
        isExpanded,
        isCurrent,
        isRoot,
        childGroupsCount,
        recordsCount,
      );
    }

    return entry(this.entry!, depth, isSelected);
  }
}

enum _EntryAction { edit, move, attachments, delete }

enum _FolderAction { addRecord, addSubfolder, rename, move, delete }

bool _matchesSearchValue(
  String value,
  String normalizedQuery,
  String compactQuery,
) {
  final normalizedValue = _normalizeSearchText(value);
  if (normalizedValue.contains(normalizedQuery)) {
    return true;
  }

  if (compactQuery.isEmpty) {
    return false;
  }

  final compactValue = normalizedValue.replaceAll(' ', '');
  return compactValue.contains(compactQuery);
}

String _normalizeSearchText(String value) {
  final lowered = value.toLowerCase();
  final folded = _foldAccents(lowered);
  final normalized = folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  return normalized;
}

String _foldAccents(String value) {
  return value
      .replaceAll(RegExp(r'[àáâãäåāăą]'), 'a')
      .replaceAll(RegExp(r'[çćĉċč]'), 'c')
      .replaceAll(RegExp(r'[ďđ]'), 'd')
      .replaceAll(RegExp(r'[èéêëēĕėęě]'), 'e')
      .replaceAll(RegExp(r'[ĝğġģ]'), 'g')
      .replaceAll(RegExp(r'[ĥħ]'), 'h')
      .replaceAll(RegExp(r'[ìíîïĩīĭįı]'), 'i')
      .replaceAll(RegExp(r'[ĵ]'), 'j')
      .replaceAll(RegExp(r'[ķ]'), 'k')
      .replaceAll(RegExp(r'[ĺļľŀł]'), 'l')
      .replaceAll(RegExp(r'[ñńņňŉŋ]'), 'n')
      .replaceAll(RegExp(r'[òóôõöøōŏő]'), 'o')
      .replaceAll(RegExp(r'[ŕŗř]'), 'r')
      .replaceAll(RegExp(r'[śŝşš]'), 's')
      .replaceAll(RegExp(r'[ţťŧ]'), 't')
      .replaceAll(RegExp(r'[ùúûüũūŭůűų]'), 'u')
      .replaceAll(RegExp(r'[ŵ]'), 'w')
      .replaceAll(RegExp(r'[ýÿŷ]'), 'y')
      .replaceAll(RegExp(r'[źżž]'), 'z');
}

OverlayEntry? _activeCopyToastEntry;
Timer? _activeCopyToastTimer;

void _showCenteredCopyToast(BuildContext context, String message) {
  _hideCenteredCopyToast();

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    return;
  }

  _activeCopyToastEntry = OverlayEntry(
    builder: (overlayContext) {
      final theme = Theme.of(overlayContext);
      final colorScheme = theme.colorScheme;
      final reduceMotion =
          MediaQuery.maybeOf(overlayContext)?.disableAnimations ?? false;

      return Positioned.fill(
        child: IgnorePointer(
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (animationContext, scale, child) {
                  final opacity = reduceMotion
                      ? 1.0
                      : ((scale - 0.92) / 0.08).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withValues(
                        alpha: 0.96,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.58,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.14,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              AppIcons.check,
                              size: 15,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(_activeCopyToastEntry!);
  _activeCopyToastTimer = Timer(const Duration(milliseconds: 1600), () {
    _hideCenteredCopyToast();
  });
}

void _hideCenteredCopyToast() {
  _activeCopyToastTimer?.cancel();
  _activeCopyToastTimer = null;
  _activeCopyToastEntry?.remove();
  _activeCopyToastEntry = null;
}
