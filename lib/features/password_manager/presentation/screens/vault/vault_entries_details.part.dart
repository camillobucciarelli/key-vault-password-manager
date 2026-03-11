part of '../vault_screen.dart';

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
          Tooltip(
            message: 'Record actions',
            ignorePointer: true,
            child: PopupMenuButton<_EntryAction>(
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
        trailing: Tooltip(
          message: _passwordVisible ? 'Hide password' : 'Show password',
          ignorePointer: true,
          child: IconButton(
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
                  Tooltip(
                    message: 'Record actions',
                    ignorePointer: true,
                    child: PopupMenuButton<_EntryAction>(
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
                            entry.otpUri == null
                                ? 'OTP unavailable'
                                : 'Show OTP',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _EntryAction.delete,
                          child: Text('Delete'),
                        ),
                      ],
                    ),
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
            const SizedBox(height: 10),
            _EntryDetailsSection(
              title: 'Metadata',
              caption: 'KDBX record timestamps.',
              child: _EntryFieldsWrap(
                children: [
                  _EntryFieldCard(
                    label: 'Created',
                    value: _formatEntryDateTime(entry.createdAt),
                    maxLines: 1,
                  ),
                  _EntryFieldCard(
                    label: 'Last modified',
                    value: _formatEntryDateTime(entry.updatedAt),
                    maxLines: 1,
                  ),
                  _EntryFieldCard(
                    label: 'Last password change',
                    value: _formatEntryDateTime(entry.lastPasswordChangedAt),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
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

    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.76),
            fontWeight: FontWeight.w600,
          ),
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
    );

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: trailing == null
          ? textColumn
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: textColumn),
                const SizedBox(width: 8),
                trailing!,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) const SizedBox(height: 8),
        ],
      ],
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
            Tooltip(
              message: isExpanded ? 'Collapse folder' : 'Expand folder',
              ignorePointer: true,
              child: IconButton(
                onPressed: hasChildren ? onToggleExpand : null,
                icon: Icon(caretIcon, size: 16),
              ),
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
            Tooltip(
              message: 'Folder actions',
              ignorePointer: true,
              child: PopupMenuButton<_FolderAction>(
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
                    PopupMenuItem(
                      value: _FolderAction.move,
                      child: Text('Move'),
                    ),
                    PopupMenuItem(
                      value: _FolderAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                ],
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
    final isPasswordWarning = _isPasswordUpdateOverdue(entry, DateTime.now());
    final warningForeground =
        ThemeData.estimateBrightnessForColor(AppColors.warning) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    final metadataTooltip =
        'Created: ${_formatEntryDateTime(entry.createdAt)}\n'
        'Last modified: ${_formatEntryDateTime(entry.updatedAt)}\n'
        'Last password change: ${_formatEntryDateTime(entry.lastPasswordChangedAt)}'
        '${isPasswordWarning ? '\nPassword warning: updated more than 3 months ago' : ''}';

    return Tooltip(
      message: metadataTooltip,
      ignorePointer: true,
      waitDuration: const Duration(milliseconds: 900),
      child: _InteractiveItemSurface(
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
                  color: isPasswordWarning
                      ? AppColors.warning.withValues(alpha: 0.78)
                      : colorScheme.secondaryContainer.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(10),
                  border: isPasswordWarning
                      ? Border.all(color: AppColors.warning, width: 1.1)
                      : null,
                ),
                child: Icon(
                  AppIcons.key,
                  size: 18,
                  color: isPasswordWarning
                      ? warningForeground
                      : colorScheme.onSecondaryContainer,
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
              Tooltip(
                message: 'Record actions',
                ignorePointer: true,
                child: PopupMenuButton<_EntryAction>(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isPasswordUpdateOverdue(VaultEntry entry, DateTime now) {
  final reference = entry.lastPasswordChangedAt ?? entry.updatedAt;
  if (reference == null) {
    return false;
  }

  final cutoff = DateTime(
    now.year,
    now.month - 3,
    now.day,
    now.hour,
    now.minute,
    now.second,
    now.millisecond,
    now.microsecond,
  );

  return reference.isBefore(cutoff);
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

  int get _periodSeconds {
    final parsed = Uri.tryParse(widget.otpUri);
    final period = int.tryParse(parsed?.queryParameters['period'] ?? '');
    if (period == null || period <= 0) {
      return 30;
    }
    return period;
  }

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
    final periodSeconds = _periodSeconds;
    final remainingRatio = (data.remainingSeconds / periodSeconds)
        .clamp(0.0, 1.0)
        .toDouble();
    final previousRatio = data.remainingSeconds == periodSeconds
        ? 1.0
        : ((data.remainingSeconds + 1) / periodSeconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final isExpiringSoon =
        data.remainingSeconds <= math.max(5, periodSeconds ~/ 5);
    final accentColor = isExpiringSoon
        ? AppColors.warning
        : colorScheme.secondary;
    final onAccentColor = isExpiringSoon
        ? (ThemeData.estimateBrightnessForColor(AppColors.warning) ==
                  Brightness.dark
              ? Colors.white
              : Colors.black87)
        : colorScheme.onSecondaryContainer;

    return Tooltip(
      message: 'Show OTP code',
      ignorePointer: true,
      child: FocusableActionDetector(
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
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: animationDuration,
                curve: Curves.easeInOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: highlighted
                        ? accentColor.withValues(alpha: 0.5)
                        : colorScheme.outlineVariant.withValues(alpha: 0.65),
                  ),
                  color: highlighted
                      ? colorScheme.secondaryContainer.withValues(alpha: 0.8)
                      : colorScheme.secondaryContainer.withValues(alpha: 0.58),
                  boxShadow: highlighted
                      ? [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.16),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.key, size: 14, color: onAccentColor),
                        const SizedBox(width: 6),
                        Text(
                          'Show OTP',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: onAccentColor,
                              ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              TweenAnimationBuilder<double>(
                                key: ValueKey<int>(data.remainingSeconds),
                                tween: Tween<double>(
                                  begin: previousRatio,
                                  end: remainingRatio,
                                ),
                                duration: const Duration(milliseconds: 940),
                                curve: Curves.linear,
                                builder: (context, animatedRatio, _) {
                                  return CircularProgressIndicator(
                                    value: animatedRatio,
                                    strokeWidth: 2.6,
                                    strokeCap: StrokeCap.round,
                                    backgroundColor: accentColor.withValues(
                                      alpha: 0.15,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      accentColor,
                                    ),
                                  );
                                },
                              ),
                              AnimatedSwitcher(
                                duration: animationDuration,
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                child: Text(
                                  '${data.remainingSeconds}',
                                  key: ValueKey<int>(data.remainingSeconds),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: onAccentColor,
                                        fontSize: 10,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
