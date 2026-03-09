part of '../vault_screen.dart';

class _EntriesCard extends StatefulWidget {
  const _EntriesCard({
    required this.entries,
    required this.groups,
    required this.searchQuery,
    required this.sortBy,
    this.keepSearchSortInline = false,
    this.isScrollablePage = false,
  });

  final List<VaultEntry> entries;
  final List<VaultGroup> groups;
  final String searchQuery;
  final VaultEntrySort sortBy;
  final bool keepSearchSortInline;
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

  Future<void> _handleCreateEntry(BuildContext context) async {
    final payload = await _showEntryDialog(context);
    if (payload != null && context.mounted) {
      context.read<VaultBloc>().add(
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

  void _onSortChanged(BuildContext context, VaultEntrySort? value) {
    if (value == null) {
      return;
    }
    context.read<VaultBloc>().add(SetVaultSort(value));
  }

  Widget _buildSortField(BuildContext context) {
    return DropdownButtonFormField<VaultEntrySort>(
      initialValue: widget.sortBy,
      isExpanded: true,
      icon: const Icon(AppIcons.chevronDown),
      decoration: const InputDecoration(labelText: 'Sort by'),
      onChanged: (value) => _onSortChanged(context, value),
      items: const [
        DropdownMenuItem(
          value: VaultEntrySort.titleAsc,
          child: Text('Title A-Z'),
        ),
        DropdownMenuItem(
          value: VaultEntrySort.titleDesc,
          child: Text('Title Z-A'),
        ),
        DropdownMenuItem(
          value: VaultEntrySort.usernameAsc,
          child: Text('Username A-Z'),
        ),
      ],
    );
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
    if (widget.entries.isEmpty) {
      final emptyState = _RecordsEmptyState(
        searchQuery: widget.searchQuery,
        onAddPressed: () => _handleCreateEntry(context),
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
      itemCount: widget.entries.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _VaultUiTokens.recordListSpacing),
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        final isSelected = showInlineDetail && _selectedEntryId == entry.id;
        return _RecordListItem(
          entry: entry,
          isSelected: isSelected,
          onOpen: () =>
              _openEntry(context, entry, showInlineDetail: showInlineDetail),
          onSelectedAction: (action) {
            _handleEntryAction(context, entry, action);
          },
        );
      },
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
          _SectionTitleWithCount(
            title: 'Records',
            count: widget.entries.length,
            onAddPressed: () => _handleCreateEntry(context),
            addLabel: 'Add record',
            addTooltip: 'Add record',
            addIcon: AppIcons.cardAdd,
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final shouldStackSearchSort =
                  !widget.keepSearchSortInline &&
                  constraints.maxWidth <
                      _VaultLayoutBreakpoints.searchSortStack;

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

              if (shouldStackSearchSort) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    _buildSortField(context),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: math.min(250, constraints.maxWidth * 0.38),
                    child: _buildSortField(context),
                  ),
                ],
              );
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
                        entry.username.isEmpty ? 'No username' : entry.username,
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
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 12),
            _EntryFieldCard(
              label: 'Title',
              value: title,
              onCopy: () {
                _copyTextToClipboard(
                  context,
                  text: title,
                  successMessage: 'Title copied.',
                );
              },
            ),
            const SizedBox(height: 8),
            _EntryFieldCard(
              label: 'Username',
              value: entry.username,
              emptyLabel: 'No username',
              onCopy: entry.username.isEmpty
                  ? null
                  : () {
                      _copyTextToClipboard(
                        context,
                        text: entry.username,
                        successMessage: 'Username copied.',
                      );
                    },
            ),
            const SizedBox(height: 8),
            _EntryFieldCard(
              label: 'Password',
              value: resolvedPassword,
              emptyLabel: 'No password',
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
                        successMessage: 'Password copied.',
                      );
                    },
            ),
            if (totpData != null) ...[
              const SizedBox(height: 8),
              _EntryFieldCard(
                label: 'OTP code (${totpData.remainingSeconds}s)',
                value: totpData.code,
                onCopy: () {
                  _copyTextToClipboard(
                    context,
                    text: totpData.code,
                    successMessage: 'OTP copied.',
                  );
                },
              ),
            ],
            const SizedBox(height: 8),
            _EntryFieldCard(
              label: 'Website',
              value: entry.url,
              emptyLabel: 'No URL',
              onCopy: entry.url.isEmpty
                  ? null
                  : () {
                      _copyTextToClipboard(
                        context,
                        text: entry.url,
                        successMessage: 'Website copied.',
                      );
                    },
            ),
            const SizedBox(height: 8),
            _EntryFieldCard(
              label: 'Notes',
              value: entry.notes,
              emptyLabel: 'No notes',
              onCopy: entry.notes.isEmpty
                  ? null
                  : () {
                      _copyTextToClipboard(
                        context,
                        text: entry.notes,
                        successMessage: 'Notes copied.',
                      );
                    },
            ),
            if (customFields.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CustomFieldsDetailCard(fields: customFields),
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
    this.trailing,
    this.onCopy,
  });

  final String label;
  final String value;
  final String emptyLabel;
  final Widget? trailing;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolved = value.isEmpty ? emptyLabel : value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(12),
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
              if (onCopy != null)
                IconButton(
                  tooltip: 'Copy $label',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCopy,
                  icon: const Icon(AppIcons.copy, size: 17),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            resolved,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: value.isEmpty
                  ? colorScheme.onSurface.withValues(alpha: 0.62)
                  : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomFieldsDetailCard extends StatelessWidget {
  const _CustomFieldsDetailCard({required this.fields});

  final List<VaultCustomField> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Custom fields',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.76),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...fields.asMap().entries.expand((entry) {
            final field = entry.value;
            final widgets = <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.key,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          field.value.isEmpty ? 'Not set' : field.value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: field.value.isEmpty
                                ? colorScheme.onSurface.withValues(alpha: 0.62)
                                : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    children: [
                      IconButton(
                        tooltip: 'Copy key',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _copyTextToClipboard(
                            context,
                            text: field.key,
                            successMessage: 'Custom key copied.',
                          );
                        },
                        icon: const Icon(AppIcons.copy, size: 16),
                      ),
                      IconButton(
                        tooltip: 'Copy value',
                        visualDensity: VisualDensity.compact,
                        onPressed: field.value.isEmpty
                            ? null
                            : () {
                                _copyTextToClipboard(
                                  context,
                                  text: field.value,
                                  successMessage: 'Custom value copied.',
                                );
                              },
                        icon: const Icon(AppIcons.copy, size: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ];

            if (entry.key < fields.length - 1) {
              widgets.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.65),
                  ),
                ),
              );
            }

            return widgets;
          }),
        ],
      ),
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
  const _RecordsEmptyState({
    required this.searchQuery,
    required this.onAddPressed,
    this.onClearSearch,
  });

  final String searchQuery;
  final Future<void> Function() onAddPressed;
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
                : 'Add a record to start storing credentials in this folder.',
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
            FilledButton.icon(
              onPressed: onAddPressed,
              style: FilledButton.styleFrom(
                animationDuration: _VaultUiTokens.buttonTransitionDuration,
              ),
              icon: const Icon(AppIcons.cardAdd),
              label: const Text('+ Add record'),
            ),
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
          duration: _VaultUiTokens.chipTransitionDuration,
          curve: Curves.easeOutCubic,
          scale: highlighted ? 1.02 : 1,
          child: InkWell(
            onTap: () async {
              await _showTotpUriDialog(context, widget.otpUri);
            },
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: _VaultUiTokens.chipTransitionDuration,
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
                visualDensity: VisualDensity.compact,
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
