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
              context.read<VaultBloc>().add(OpenGroup(group.id));
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

    return Scrollbar(child: list);
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
                key: ValueKey('vault-search-${widget.searchQuery}'),
                initialValue: widget.searchQuery,
                decoration: InputDecoration(
                  labelText: 'Search records',
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: widget.searchQuery.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            context.read<VaultBloc>().add(
                              const ClearVaultSearchQuery(),
                            );
                          },
                          icon: const Icon(AppIcons.close),
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

class _EntryDetailsPage extends StatelessWidget {
  const _EntryDetailsPage({
    required this.entry,
    required this.onSelectedAction,
  });

  final VaultEntry entry;
  final ValueChanged<_EntryAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(entry.title.isEmpty ? '(Untitled)' : entry.title),
        actions: [
          PopupMenuButton<_EntryAction>(
            tooltip: 'Record actions',
            onSelected: onSelectedAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _EntryAction.edit,
                child: Text('Edit'),
              ),
              const PopupMenuItem(
                value: _EntryAction.move,
                child: Text('Move'),
              ),
              const PopupMenuItem(
                value: _EntryAction.attachments,
                child: Text('Attachments'),
              ),
              PopupMenuItem(
                value: _EntryAction.showTotp,
                child: Text(
                  entry.otpUri == null ? 'OTP unavailable' : 'Show OTP',
                ),
              ),
              const PopupMenuItem(
                value: _EntryAction.delete,
                child: Text('Delete'),
              ),
            ],
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
          Padding(
            padding: EdgeInsets.fromLTRB(12, topInset + 12, 12, 12),
            child: _EntryDetailPanel(entry: entry),
          ),
        ],
      ),
    );
  }
}

class _EntryDetailPanel extends StatefulWidget {
  const _EntryDetailPanel({required this.entry, this.onSelectedAction});

  final VaultEntry entry;
  final ValueChanged<_EntryAction>? onSelectedAction;

  @override
  State<_EntryDetailPanel> createState() => _EntryDetailPanelState();
}

class _EntryDetailPanelState extends State<_EntryDetailPanel> {
  bool _passwordVisible = false;
  Timer? _otpTimer;
  DateTime _nowUtc = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _configureOtpTicker();
  }

  @override
  void didUpdateWidget(covariant _EntryDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.otpUri != widget.entry.otpUri) {
      _configureOtpTicker();
    }
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    super.dispose();
  }

  void _configureOtpTicker() {
    _otpTimer?.cancel();
    if (widget.entry.otpUri == null) {
      _otpTimer = null;
      return;
    }

    _otpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nowUtc = DateTime.now().toUtc();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entry = widget.entry;
    final title = entry.title.isEmpty ? '(Untitled)' : entry.title;
    final customFields = entry.customFields
        .where((field) => !_isOtpFieldKey(field.key))
        .toList(growable: false);
    final totpData = entry.otpUri == null
        ? null
        : TotpUtils.fromOtpAuthUri(entry.otpUri!, _nowUtc);
    final resolvedPassword = _passwordVisible
        ? (entry.password.isEmpty ? 'Not set' : entry.password)
        : (entry.password.isEmpty ? 'Not set' : '••••••••••••');
    final standardFields = <Widget>[
      _EntryFieldCard(
        label: 'Username',
        value: entry.username,
        emptyLabel: 'Username not set',
        maxLines: 1,
        onCopy: entry.username.isEmpty
            ? null
            : () {
                _copyTextToClipboard(
                  context,
                  text: entry.username,
                  successMessage: 'Copied username.',
                );
              },
      ),
      _EntryFieldCard(
        label: 'Password',
        value: resolvedPassword,
        emptyLabel: 'Password not set',
        maxLines: 1,
        trailing: IconButton(
          tooltip: _passwordVisible ? 'Hide password' : 'Show password',
          onPressed: entry.password.isEmpty
              ? null
              : () {
                  setState(() {
                    _passwordVisible = !_passwordVisible;
                  });
                },
          icon: Icon(
            _passwordVisible ? AppIcons.eyeOff : AppIcons.eye,
            size: 18,
          ),
        ),
        onCopy: entry.password.isEmpty
            ? null
            : () {
                _copyTextToClipboard(
                  context,
                  text: entry.password,
                  successMessage: 'Copied password.',
                );
              },
      ),
      _EntryFieldCard(
        label: 'URL',
        value: entry.url,
        emptyLabel: 'URL not set',
        maxLines: 1,
        onCopy: entry.url.isEmpty
            ? null
            : () {
                _copyTextToClipboard(
                  context,
                  text: entry.url,
                  successMessage: 'Copied URL.',
                );
              },
      ),
      _EntryFieldCard(
        label: 'Notes',
        value: entry.notes,
        emptyLabel: 'Notes not set',
        maxLines: 4,
        onCopy: entry.notes.isEmpty
            ? null
            : () {
                _copyTextToClipboard(
                  context,
                  text: entry.notes,
                  successMessage: 'Copied notes.',
                );
              },
      ),
    ];

    if (totpData != null) {
      standardFields.insert(
        3,
        _EntryFieldCard(
          label: 'One-time code (${totpData.remainingSeconds}s)',
          value: totpData.code,
          maxLines: 1,
          onCopy: () {
            _copyTextToClipboard(
              context,
              text: totpData.code,
              successMessage: 'Copied one-time code.',
            );
          },
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(_VaultUiTokens.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    AppIcons.key,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.username.isEmpty
                            ? 'Username not set'
                            : entry.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onSelectedAction != null)
                  PopupMenuButton<_EntryAction>(
                    tooltip: 'Record actions',
                    onSelected: widget.onSelectedAction,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _EntryAction.edit,
                        child: Text('Edit'),
                      ),
                      const PopupMenuItem(
                        value: _EntryAction.move,
                        child: Text('Move'),
                      ),
                      const PopupMenuItem(
                        value: _EntryAction.attachments,
                        child: Text('Attachments'),
                      ),
                      PopupMenuItem(
                        value: _EntryAction.showTotp,
                        child: Text(
                          entry.otpUri == null ? 'OTP unavailable' : 'Show OTP',
                        ),
                      ),
                      const PopupMenuItem(
                        value: _EntryAction.delete,
                        child: Text('Delete'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 10),
            Text(
              _copyHintLabel(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.66),
              ),
            ),
            const SizedBox(height: 6),
            _EntryFieldsWrap(children: standardFields),
            if (customFields.isNotEmpty) ...[
              const SizedBox(height: 10),
              _EntryDetailsSection(
                title: 'Custom fields',
                caption: 'Stored separately from standard record fields.',
                child: _CustomFieldsDetailCard(fields: customFields),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntryFieldCard extends StatelessWidget {
  const _EntryFieldCard({
    required this.label,
    required this.value,
    this.emptyLabel = 'Not set',
    this.maxLines = 3,
    this.trailing,
    this.onCopy,
  });

  final String label;
  final String value;
  final String emptyLabel;
  final int? maxLines;
  final Widget? trailing;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolved = value.isEmpty ? emptyLabel : value;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.76),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              trailing ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            resolved,
            maxLines: maxLines,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: value.isEmpty
                  ? colorScheme.onSurface.withValues(alpha: 0.62)
                  : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );

    if (onCopy == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _useLongPressCopy() ? null : onCopy,
        onLongPress: _useLongPressCopy() ? onCopy : null,
        borderRadius: BorderRadius.circular(10),
        child: content,
      ),
    );
  }
}

class _EntryDetailsSection extends StatelessWidget {
  const _EntryDetailsSection({
    required this.title,
    required this.child,
    this.caption,
  });

  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.66),
            ),
          ),
        ],
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _EntryFieldsWrap extends StatelessWidget {
  const _EntryFieldsWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final useTwoColumns = constraints.maxWidth >= 520;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _CustomFieldsDetailCard extends StatelessWidget {
  const _CustomFieldsDetailCard({required this.fields});

  final List<VaultCustomField> fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          _EntryFieldCard(
            label: fields[i].key,
            value: fields[i].value,
            emptyLabel: 'Value not set',
            maxLines: null,
            onCopy: fields[i].value.isEmpty
                ? null
                : () {
                    _copyTextToClipboard(
                      context,
                      text: fields[i].value,
                      successMessage: 'Copied ${fields[i].key}.',
                    );
                  },
          ),
          if (i < fields.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _EntryDetailEmptyState extends StatelessWidget {
  const _EntryDetailEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.66),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.64),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.key,
              size: 52,
              color: colorScheme.onSurface.withValues(alpha: 0.34),
            ),
            const SizedBox(height: 12),
            Text(
              'No item selected',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a record from the list to view all details and copy fields.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.64),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderListItem extends StatelessWidget {
  const _FolderListItem({
    required this.group,
    required this.isExpanded,
    required this.isCurrent,
    required this.isRoot,
    required this.childGroupsCount,
    required this.recordsCount,
    required this.onOpen,
    required this.onToggleExpand,
    required this.onSelectedAction,
  });

  final VaultGroup group;
  final bool isExpanded;
  final bool isCurrent;
  final bool isRoot;
  final int childGroupsCount;
  final int recordsCount;
  final VoidCallback onOpen;
  final VoidCallback onToggleExpand;
  final ValueChanged<_FolderAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final itemAnimationDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : _VaultUiTokens.itemTransitionDuration;
    final hasChildren = childGroupsCount > 0;
    final caretIcon = isExpanded ? AppIcons.chevronDown : AppIcons.chevronRight;

    return _InteractiveItemSurface(
      radius: _VaultUiTokens.recordItemRadius,
      minHeight: _VaultUiTokens.recordItemHeight,
      onTap: onOpen,
      baseColor: isCurrent
          ? colorScheme.primaryContainer.withValues(alpha: 0.62)
          : colorScheme.surface.withValues(alpha: 0.74),
      hoveredColor: isCurrent
          ? colorScheme.primaryContainer.withValues(alpha: 0.72)
          : colorScheme.surface.withValues(alpha: 0.85),
      baseBorderColor: isCurrent
          ? colorScheme.primary.withValues(alpha: 0.62)
          : colorScheme.outlineVariant.withValues(alpha: 0.7),
      hoveredBorderColor: colorScheme.primary.withValues(alpha: 0.42),
      child: Padding(
        padding: const EdgeInsets.only(left: 6, right: 6, top: 8, bottom: 8),
        child: Row(
          children: [
            AnimatedContainer(
              duration: itemAnimationDuration,
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                color: isCurrent
                    ? colorScheme.primary.withValues(alpha: 0.92)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: isExpanded ? 'Collapse folder' : 'Expand folder',
              onPressed: hasChildren ? onToggleExpand : null,
              icon: Icon(caretIcon, size: 16),
            ),
            Container(
              width: _VaultUiTokens.folderIconContainerSize,
              height: _VaultUiTokens.folderIconContainerSize,
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.54),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isExpanded ? AppIcons.folderOpen : AppIcons.folder,
                size: 18,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isCurrent
                                    ? colorScheme.onPrimaryContainer
                                    : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$childGroupsCount folders • $recordsCount records',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isCurrent
                          ? colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            if (isRoot) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.36),
                  ),
                ),
                child: Text(
                  'ROOT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
            PopupMenuButton<_FolderAction>(
              tooltip: 'Folder actions',
              onSelected: onSelectedAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _FolderAction.addRecord,
                  child: const Text('Add record'),
                ),
                PopupMenuItem(
                  value: _FolderAction.addSubfolder,
                  child: const Text('Add subfolder'),
                ),
                if (!isRoot) ...const [
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: _FolderAction.rename,
                    child: Text('Rename'),
                  ),
                  PopupMenuItem(value: _FolderAction.move, child: Text('Move')),
                  PopupMenuItem(
                    value: _FolderAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordListItem extends StatelessWidget {
  const _RecordListItem({
    required this.entry,
    required this.onOpen,
    required this.onSelectedAction,
    this.isSelected = false,
  });

  final VaultEntry entry;
  final VoidCallback onOpen;
  final ValueChanged<_EntryAction> onSelectedAction;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _InteractiveItemSurface(
      radius: _VaultUiTokens.recordItemRadius,
      minHeight: _VaultUiTokens.recordItemHeight,
      onTap: onOpen,
      baseColor: isSelected
          ? colorScheme.secondaryContainer.withValues(alpha: 0.52)
          : colorScheme.surface.withValues(alpha: 0.74),
      hoveredColor: isSelected
          ? colorScheme.secondaryContainer.withValues(alpha: 0.68)
          : colorScheme.surface.withValues(alpha: 0.85),
      baseBorderColor: isSelected
          ? colorScheme.secondary.withValues(alpha: 0.44)
          : colorScheme.outlineVariant.withValues(alpha: 0.7),
      hoveredBorderColor: colorScheme.secondary.withValues(alpha: 0.33),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 8, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _VaultUiTokens.folderIconContainerSize,
              height: _VaultUiTokens.folderIconContainerSize,
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                AppIcons.key,
                size: 18,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title.isEmpty ? '(Untitled)' : entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.onSecondaryContainer
                          : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.username.isEmpty
                        ? (entry.url.isEmpty ? 'No username' : entry.url)
                        : entry.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? colorScheme.onSecondaryContainer.withValues(
                              alpha: 0.82,
                            )
                          : null,
                    ),
                  ),
                  if (entry.otpUri != null) ...[
                    const SizedBox(height: 7),
                    _TotpChip(otpUri: entry.otpUri!),
                  ],
                ],
              ),
            ),
            PopupMenuButton<_EntryAction>(
              tooltip: 'Record actions',
              onSelected: onSelectedAction,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _EntryAction.edit,
                  child: Text('Edit'),
                ),
                const PopupMenuItem(
                  value: _EntryAction.move,
                  child: Text('Move'),
                ),
                const PopupMenuItem(
                  value: _EntryAction.attachments,
                  child: Text('Attachments'),
                ),
                PopupMenuItem(
                  value: _EntryAction.showTotp,
                  child: Text(
                    entry.otpUri == null ? 'OTP unavailable' : 'Show OTP',
                  ),
                ),
                const PopupMenuItem(
                  value: _EntryAction.delete,
                  child: Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsEmptyState extends StatelessWidget {
  const _RecordsEmptyState({required this.searchQuery, this.onClearSearch});

  final String searchQuery;
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSearchActive = searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSearchActive ? AppIcons.searchOff : AppIcons.key,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isSearchActive ? 'No records found' : 'No records yet',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            isSearchActive
                ? 'Try a different keyword or clear the search.'
                : 'Use the folder menu to add records or subfolders.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (isSearchActive && onClearSearch != null)
            OutlinedButton.icon(
              onPressed: onClearSearch,
              style: OutlinedButton.styleFrom(
                animationDuration: _VaultUiTokens.buttonTransitionDuration,
              ),
              icon: const Icon(AppIcons.close),
              label: const Text('Clear search'),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _TotpChip extends StatefulWidget {
  const _TotpChip({required this.otpUri});

  final String otpUri;

  @override
  State<_TotpChip> createState() => _TotpChipState();
}

class _TotpChipState extends State<_TotpChip> {
  late Timer _timer;
  DateTime _nowUtc = DateTime.now().toUtc();
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nowUtc = DateTime.now().toUtc();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = TotpUtils.fromOtpAuthUri(widget.otpUri, _nowUtc);
    if (data == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final animationDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : _VaultUiTokens.chipTransitionDuration;
    final highlighted = _isHovered || _isFocused;

    return FocusableActionDetector(
      onShowFocusHighlight: (value) {
        if (_isFocused != value) {
          setState(() {
            _isFocused = value;
          });
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() {
            _isHovered = true;
          });
        },
        onExit: (_) {
          setState(() {
            _isHovered = false;
          });
        },
        child: AnimatedScale(
          duration: animationDuration,
          curve: Curves.easeOutCubic,
          scale: highlighted ? 1.02 : 1,
          child: InkWell(
            onTap: () async {
              await _showTotpUriDialog(context, widget.otpUri);
            },
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: animationDuration,
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: highlighted
                      ? colorScheme.secondary.withValues(alpha: 0.35)
                      : colorScheme.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
              child: Chip(
                side: BorderSide.none,
                backgroundColor: highlighted
                    ? colorScheme.secondaryContainer.withValues(alpha: 0.75)
                    : colorScheme.secondaryContainer.withValues(alpha: 0.55),
                label: Text('Show OTP (${data.remainingSeconds}s)'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
