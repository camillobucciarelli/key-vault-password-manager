part of '../vault_screen.dart';

class _EntriesCard extends StatefulWidget {
  const _EntriesCard({
    required this.entries,
    required this.groups,
    required this.rootGroupId,
    required this.currentGroupId,
    required this.expandedGroupIds,
    required this.searchQuery,
    this.isScrollablePage = false,
  });

  final List<VaultEntry> entries;
  final List<VaultGroup> groups;
  final String? rootGroupId;
  final String? currentGroupId;
  final List<String> expandedGroupIds;
  final String searchQuery;
  final bool isScrollablePage;

  @override
  State<_EntriesCard> createState() => _EntriesCardState();
}

class _EntriesCardState extends State<_EntriesCard> {
  String? _selectedEntryId;
  late final ScrollController _entriesScrollController;
  late final TextEditingController _searchController;

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

  VaultEntry? get _selectedEntry {
    if (_selectedEntryId == null) {
      return null;
    }

    for (final entry in widget.entries) {
      if (entry.id == _selectedEntryId) {
        return entry;
      }
    }
    return null;
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

    if (widget.entries.isEmpty) {
      if (_selectedEntryId != null) {
        _selectedEntryId = null;
      }
      return;
    }

    if (_selectedEntryId == null) {
      return;
    }

    final stillExists = widget.entries.any(
      (entry) => entry.id == _selectedEntryId,
    );
    if (!stillExists) {
      _selectedEntryId = null;
    }
  }

  Future<void> _handleCreateEntry(
    BuildContext context, {
    String? targetGroupId,
  }) async {
    final payload = await _showEntryDialog(context);
    if (payload != null && context.mounted) {
      final bloc = context.read<VaultBloc>();
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
    if (name == null || name.trim().isEmpty || !context.mounted) {
      return;
    }

    final bloc = context.read<VaultBloc>();
    if (targetGroupId != null) {
      bloc.add(OpenGroup(targetGroupId));
    }
    bloc.add(CreateVaultGroup(name.trim()));
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

  Future<void> _handleEntryAction(
    BuildContext context,
    VaultEntry entry,
    _EntryAction action,
  ) async {
    switch (action) {
      case _EntryAction.edit:
        final payload = await _showEntryDialog(context, initial: entry);
        if (payload != null && context.mounted) {
          context.read<VaultBloc>().add(
            UpdateVaultEntry(
              entryId: entry.id,
              title: payload.title,
              username: payload.username,
              password: payload.password,
              url: payload.url,
              notes: payload.notes,
              customFields: payload.customFields,
            ),
          );
        }
        break;
      case _EntryAction.move:
        final target = await _showMoveTargetDialog(context, widget.groups);
        if (target != null && context.mounted) {
          context.read<VaultBloc>().add(
            MoveVaultEntry(entryId: entry.id, targetGroupId: target),
          );
        }
        break;
      case _EntryAction.attachments:
        await _showAttachmentsDialog(context, entry);
        break;
      case _EntryAction.showTotp:
        await _showTotpDialog(context, entry);
        break;
      case _EntryAction.delete:
        final confirmed = await _showDeleteConfirm(
          context,
          label: 'Move this record to recycle bin?',
        );
        if (confirmed && context.mounted) {
          context.read<VaultBloc>().add(DeleteVaultEntry(entry.id));
        }
        break;
    }
  }

  Future<void> _openEntry(
    BuildContext context,
    VaultEntry entry, {
    required bool showInlineDetail,
  }) async {
    if (showInlineDetail) {
      setState(() {
        _selectedEntryId = entry.id;
      });
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _EntryDetailsPage(
          entry: entry,
          onSelectedAction: (action) async {
            await _handleEntryAction(context, entry, action);
          },
        ),
      ),
    );
  }

  Widget _buildEntriesList(
    BuildContext context, {
    required bool showInlineDetail,
  }) {
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
    if (widget.searchQuery.trim().isNotEmpty) {
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
    final treeItems = <Widget>[];
    final manualExpanded = widget.expandedGroupIds.toSet();

    void appendGroup(VaultGroup group, int depth) {
      if (widget.searchQuery.trim().isNotEmpty &&
          !groupHasVisibleContent(group.id)) {
        return;
      }

      final isExpanded =
          manualExpanded.contains(group.id) || autoExpanded.contains(group.id);
      final isCurrent = widget.currentGroupId == group.id;
      final children = byParent[group.id] ?? const <VaultGroup>[];
      final records = entriesByGroup[group.id] ?? const <VaultEntry>[];

      treeItems.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 14.0),
          child: _FolderListItem(
            group: group,
            isExpanded: isExpanded,
            isCurrent: isCurrent,
            isRoot: group.id == rootId,
            childGroupsCount: children.length,
            recordsCount: records.length,
            onOpen: () {
              context.read<VaultBloc>().add(ToggleVaultGroupExpanded(group.id));
            },
            onToggleExpand: () {
              context.read<VaultBloc>().add(ToggleVaultGroupExpanded(group.id));
            },
            onSelectedAction: (action) async {
              await _handleFolderAction(context, group: group, action: action);
            },
          ),
        ),
      );

      if (!isExpanded) {
        return;
      }

      for (final child in children) {
        appendGroup(child, depth + 1);
      }

      for (final entry in records) {
        final isSelected = showInlineDetail && _selectedEntryId == entry.id;
        treeItems.add(
          Padding(
            padding: EdgeInsets.only(left: (depth + 1) * 14.0),
            child: _RecordListItem(
              entry: entry,
              isSelected: isSelected,
              onOpen: () => _openEntry(
                context,
                entry,
                showInlineDetail: showInlineDetail,
              ),
              onSelectedAction: (action) {
                _handleEntryAction(context, entry, action);
              },
            ),
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
        final isSelected = showInlineDetail && _selectedEntryId == entry.id;
        treeItems.add(
          _RecordListItem(
            entry: entry,
            isSelected: isSelected,
            onOpen: () =>
                _openEntry(context, entry, showInlineDetail: showInlineDetail),
            onSelectedAction: (action) {
              _handleEntryAction(context, entry, action);
            },
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

      if (widget.isScrollablePage) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: emptyState,
        );
      }

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

    final list = ListView.separated(
      controller: widget.isScrollablePage ? null : _entriesScrollController,
      padding: EdgeInsets.zero,
      shrinkWrap: widget.isScrollablePage,
      physics: widget.isScrollablePage
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: treeItems.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _VaultUiTokens.recordListSpacing),
      itemBuilder: (context, index) => treeItems[index],
    );

    if (widget.isScrollablePage) {
      return list;
    }

    return Scrollbar(controller: _entriesScrollController, child: list);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                  labelText: 'Search records',
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
          if (widget.isScrollablePage)
            _buildEntriesList(context, showInlineDetail: false)
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showInlineDetail =
                      constraints.maxWidth >= Breakpoints.mobile;
                  if (!showInlineDetail) {
                    return _buildEntriesList(context, showInlineDetail: false);
                  }

                  final selected = _selectedEntry;
                  return Row(
                    children: [
                      SizedBox(
                        width: math.max(260, constraints.maxWidth * 0.42),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.58,
                                ),
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _buildEntriesList(
                              context,
                              showInlineDetail: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: selected == null
                            ? const _EntryDetailEmptyState()
                            : _EntryDetailPanel(
                                entry: selected,
                                onSelectedAction: (action) {
                                  _handleEntryAction(context, selected, action);
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
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

enum _EntryAction { edit, move, attachments, showTotp, delete }

enum _FolderAction { addRecord, addSubfolder, rename, move, delete }

Future<void> _copyTextToClipboard(
  BuildContext context, {
  required String text,
  required String successMessage,
}) async {
  if (text.isEmpty) {
    return;
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(successMessage)));
}

bool _useLongPressCopy() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return false;
  }
}

String _copyHintLabel() {
  return _useLongPressCopy()
      ? 'Long press a field to copy'
      : 'Click a field to copy';
}
