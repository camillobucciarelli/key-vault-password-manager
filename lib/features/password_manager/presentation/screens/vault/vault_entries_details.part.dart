part of '../vault_screen.dart';

class _EntryDetailsPage extends StatelessWidget {
  const _EntryDetailsPage({
    required this.entryId,
    required this.onSelectedAction,
  });

  final String entryId;
  final ValueChanged<_EntryAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final entry = context.select((VaultBloc bloc) {
      for (final e in bloc.state.allEntries) {
        if (e.id == entryId) return e;
      }
      return null;
    });

    if (entry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom + 12;

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
              itemBuilder: (context) => const [
                _RoundedPopupItem(
                  value: _EntryAction.edit,
                  child: _MenuItemContent(icon: AppIcons.edit, label: 'Edit'),
                ),
                _RoundedPopupItem(
                  value: _EntryAction.move,
                  child: _MenuItemContent(icon: AppIcons.move, label: 'Move'),
                ),
                _RoundedPopupItem(
                  value: _EntryAction.attachments,
                  child: _MenuItemContent(
                    icon: AppIcons.attachment,
                    label: 'Attachments',
                  ),
                ),
                _RoundedPopupItem(
                  value: _EntryAction.delete,
                  child: _MenuItemContent(
                    icon: AppIcons.delete,
                    label: 'Delete',
                    isDestructive: true,
                  ),
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
            padding: EdgeInsets.fromLTRB(12, topInset + 12, 12, bottomInset),
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
    final resolvedPassword = entry.password.isEmpty
        ? ''
        : (_passwordVisible ? entry.password : '••••••••••••');
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
        padding: EdgeInsets.fromLTRB(
          14,
          14,
          14,
          MediaQuery.viewPaddingOf(context).bottom + 14,
        ),
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
                Tooltip(
                  message: 'Record info',
                  ignorePointer: true,
                  child: IconButton(
                    onPressed: () => _showRecordMetadataDialog(context, entry),
                    icon: Icon(
                      AppIcons.info,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.52),
                    ),
                  ),
                ),
                if (widget.onSelectedAction != null)
                  Tooltip(
                    message: 'Record actions',
                    ignorePointer: true,
                    child: PopupMenuButton<_EntryAction>(
                      onSelected: widget.onSelectedAction,
                      itemBuilder: (context) => const [
                        _RoundedPopupItem(
                          value: _EntryAction.edit,
                          child: _MenuItemContent(
                            icon: AppIcons.edit,
                            label: 'Edit',
                          ),
                        ),
                        _RoundedPopupItem(
                          value: _EntryAction.move,
                          child: _MenuItemContent(
                            icon: AppIcons.move,
                            label: 'Move',
                          ),
                        ),
                        _RoundedPopupItem(
                          value: _EntryAction.attachments,
                          child: _MenuItemContent(
                            icon: AppIcons.attachment,
                            label: 'Attachments',
                          ),
                        ),
                        _RoundedPopupItem(
                          value: _EntryAction.delete,
                          child: _MenuItemContent(
                            icon: AppIcons.delete,
                            label: 'Delete',
                            isDestructive: true,
                          ),
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
            if (entry.attachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              _EntryDetailsSection(
                title: 'Attachments',
                child: _AttachmentsDetailCard(
                  attachments: entry.attachments,
                  onManage: widget.onSelectedAction == null
                      ? null
                      : () {
                          widget.onSelectedAction!(_EntryAction.attachments);
                        },
                ),
              ),
            ],
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

Future<VaultDone?> _showRecordMetadataDialog(
  BuildContext context,
  VaultEntry entry,
) {
  return VaultShellRouterScope.of(context).open<VaultDone>(
    context: context,
    surface: EntrySurface<VaultDone>(
      builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final colorScheme = theme.colorScheme;

      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                AppIcons.info,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Record info'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MetadataRow(
              label: 'Created',
              value: _formatEntryDateTime(entry.createdAt),
            ),
            _MetadataRow(
              label: 'Last modified',
              value: _formatEntryDateTime(entry.updatedAt),
            ),
            _MetadataRow(
              label: 'Password changed',
              value: _formatEntryDateTime(entry.lastPasswordChangedAt),
              isLast: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => VaultOperationScope.of(
              dialogContext,
            ).complete(const VaultDone()),
            child: const Text('Close'),
          ),
        ],
      );
      },
    ),
  );
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
      ],
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
        Text(
          resolved,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: value.isEmpty
                ? colorScheme.onSurface.withValues(alpha: 0.62)
                : colorScheme.onSurface,
          ),
        ),
      ],
    );

    final content = StyledInfoContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      borderRadius: 10,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.34,
      ),
      borderColor: colorScheme.outlineVariant.withValues(alpha: 0.65),
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
        onTap: () => _showCopyFieldMenu(context, onCopy!),
        onSecondaryTap: () => _showCopyFieldMenu(context, onCopy!),
        borderRadius: BorderRadius.circular(10),
        child: content,
      ),
    );
  }
}

enum _EntryFieldMenuAction { copy }

Future<void> _showCopyFieldMenu(
  BuildContext context,
  VoidCallback onCopy,
) async {
  final fieldRenderObject = context.findRenderObject();
  if (fieldRenderObject is! RenderBox) {
    return;
  }
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) {
    return;
  }

  final fieldTopLeft = fieldRenderObject.localToGlobal(Offset.zero);
  final fieldRect = Rect.fromLTWH(
    fieldTopLeft.dx,
    fieldTopLeft.dy,
    fieldRenderObject.size.width,
    fieldRenderObject.size.height,
  );
  final selectedAction = await showMenu<_EntryFieldMenuAction>(
    context: context,
    position: RelativeRect.fromRect(fieldRect, Offset.zero & overlay.size),
    items: const [
      _RoundedPopupItem<_EntryFieldMenuAction>(
        value: _EntryFieldMenuAction.copy,
        child: Row(
          children: [
            Icon(AppIcons.copy, size: 16),
            SizedBox(width: 8),
            Text('Copy'),
          ],
        ),
      ),
    ],
  );

  if (selectedAction == _EntryFieldMenuAction.copy) {
    onCopy();
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

class _AttachmentsDetailCard extends StatelessWidget {
  const _AttachmentsDetailCard({required this.attachments, this.onManage});

  final List<VaultAttachment> attachments;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StyledInfoContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: 10,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.34,
      ),
      borderColor: colorScheme.outlineVariant.withValues(alpha: 0.65),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < attachments.length; i++) ...[
            _AttachmentDetailRow(attachment: attachments[i]),
            if (i < attachments.length - 1)
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
          ],
          if (onManage != null) ...[
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onManage,
                icon: const Icon(AppIcons.attachment, size: 16),
                label: const Text('Manage'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentDetailRow extends StatelessWidget {
  const _AttachmentDetailRow({required this.attachment});

  final VaultAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            AppIcons.attachment,
            size: 16,
            color: colorScheme.onSurface.withValues(alpha: 0.62),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatBytes(attachment.size),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
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
                  const _RoundedPopupItem(
                    value: _FolderAction.addRecord,
                    child: _MenuItemContent(
                      icon: AppIcons.cardAdd,
                      label: 'Add record',
                    ),
                  ),
                  const _RoundedPopupItem(
                    value: _FolderAction.addSubfolder,
                    child: _MenuItemContent(
                      icon: AppIcons.folderAdd,
                      label: 'Add subfolder',
                    ),
                  ),
                  const PopupMenuDivider(),
                  const _RoundedPopupItem(
                    value: _FolderAction.rename,
                    child: _MenuItemContent(
                      icon: AppIcons.edit,
                      label: 'Rename',
                    ),
                  ),
                  if (!isRoot) ...[
                    const _RoundedPopupItem(
                      value: _FolderAction.move,
                      child: _MenuItemContent(
                        icon: AppIcons.move,
                        label: 'Move',
                      ),
                    ),
                    const _RoundedPopupItem(
                      value: _FolderAction.delete,
                      child: _MenuItemContent(
                        icon: AppIcons.delete,
                        label: 'Delete',
                        isDestructive: true,
                      ),
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
                ],
              ),
            ),
            Tooltip(
              message: 'Record actions',
              ignorePointer: true,
              child: PopupMenuButton<_EntryAction>(
                onSelected: onSelectedAction,
                itemBuilder: (context) => const [
                  _RoundedPopupItem(
                    value: _EntryAction.edit,
                    child: _MenuItemContent(icon: AppIcons.edit, label: 'Edit'),
                  ),
                  _RoundedPopupItem(
                    value: _EntryAction.move,
                    child: _MenuItemContent(icon: AppIcons.move, label: 'Move'),
                  ),
                  _RoundedPopupItem(
                    value: _EntryAction.attachments,
                    child: _MenuItemContent(
                      icon: AppIcons.attachment,
                      label: 'Attachments',
                    ),
                  ),
                  _RoundedPopupItem(
                    value: _EntryAction.delete,
                    child: _MenuItemContent(
                      icon: AppIcons.delete,
                      label: 'Delete',
                      isDestructive: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

class _PrivacyOverlay extends StatelessWidget {
  const _PrivacyOverlay();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      child: Center(
        child: Icon(
          AppIcons.lock,
          size: 48,
          color: colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}

class _LockOverlay extends StatefulWidget {
  const _LockOverlay({required this.databasePath, required this.onUnlocked});

  final String databasePath;
  final VoidCallback onUnlocked;

  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  bool _biometricAvailable = false;
  bool _showPasswordFallback = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBiometric());
  }

  Future<void> _initBiometric() async {
    final available = await di.sl<BiometricDataSource>().isBiometricAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available) {
      await _triggerBiometric();
    } else {
      setState(() => _showPasswordFallback = true);
    }
  }

  Future<void> _triggerBiometric() async {
    if (_isAuthenticating || !mounted) return;
    setState(() => _isAuthenticating = true);
    final ok = await di.sl<BiometricDataSource>().authenticate(
      reason: 'Unlock vault',
    );
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _isAuthenticating = false;
      _showPasswordFallback = true;
    });
  }

  Future<void> _usePassword() async {
    await di.sl<VaultSessionCoordinator>().lockVault(
      currentDatabasePath: widget.databasePath,
    );
    if (!mounted) return;
    AppNavigation.pushFadeReplacement(
      context,
      DatabaseUnlockScreen(databasePath: widget.databasePath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.lock,
              size: 52,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            if (_biometricAvailable && !_showPasswordFallback)
              FilledButton.icon(
                onPressed: _isAuthenticating ? null : _triggerBiometric,
                icon: Icon(AppIcons.fingerprint),
                label: const Text('Unlock with biometrics'),
              ),
            if (_showPasswordFallback) ...[
              if (_biometricAvailable)
                FilledButton.icon(
                  onPressed: _isAuthenticating ? null : _triggerBiometric,
                  icon: Icon(AppIcons.fingerprint),
                  label: const Text('Unlock with biometrics'),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _usePassword,
                child: const Text('Use password'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuItemContent extends StatelessWidget {
  const _MenuItemContent({
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isDestructive ? colorScheme.error : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Text(label, style: color != null ? TextStyle(color: color) : null),
      ],
    );
  }
}

/// [PopupMenuItem] with rounded hover/splash ink instead of a full-width
/// rectangle. Replaces the default [InkWell] with one that has [borderRadius].
class _RoundedPopupItem<T> extends PopupMenuItem<T> {
  const _RoundedPopupItem({
    super.key,
    super.value,
    super.enabled,
    required super.child,
  }) : super(padding: EdgeInsets.zero);

  @override
  PopupMenuItemState<T, PopupMenuItem<T>> createState() =>
      _RoundedPopupItemState<T>();
}

class _RoundedPopupItemState<T>
    extends PopupMenuItemState<T, _RoundedPopupItem<T>> {
  static const _kRadius = 10.0;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        enabled: widget.enabled,
        button: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(_kRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(_kRadius),
              onTap: widget.enabled ? handleTap : null,
              canRequestFocus: widget.enabled,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: buildChild(),
              ),
            ),
          ),
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
            isSearchActive ? 'No records or folders found' : 'No records yet',
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
