part of '../vault_screen.dart';

// FR-5 / T10-T12/T20: Duplicates destination — group cards (screen 10),
// merge-preview sheet with exactly the four `MergePreview` flags (screen
// 11), no-duplicates empty state (screen 12). Replaces the old dialog-based
// `_DuplicatesDialog`/`_showMergeReviewDialog` with first-class surfaces.

Future<VaultDone?> _showDuplicatesDialog(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  bloc.add(const LoadDuplicates());

  return VaultShellRouterScope.of(context).open<VaultDone>(
    context: context,
    surface: DuplicatesSurface<VaultDone>(
      builder: (dialogContext) {
        return BlocProvider.value(
          value: bloc,
          child: const _DuplicatesScreen(),
        );
      },
    ),
  );
}

class _DuplicatesScreen extends StatelessWidget {
  const _DuplicatesScreen();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => VaultOperationScope.of(
                      context,
                    ).complete(const VaultDone()),
                    icon: KvIcon(
                      glyph: AppGlyph.back,
                      size: 19,
                      color: colors.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: BlocBuilder<VaultBloc, VaultState>(
                      buildWhen: (p, n) =>
                          p.duplicateGroups != n.duplicateGroups,
                      builder: (context, state) {
                        final entryCount = state.duplicateGroups.fold<int>(
                          0,
                          (sum, group) => sum + group.entries.length,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Manage duplicates',
                              style: AppTextStyles.panelTitleLarge.copyWith(
                                fontSize: 19,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              '${state.duplicateGroups.length} groups · $entryCount records',
                              style: AppTextStyles.meta.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Check again',
                    onPressed: () =>
                        context.read<VaultBloc>().add(const LoadDuplicates()),
                    icon: KvIcon(
                      glyph: AppGlyph.refresh,
                      size: 18,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<VaultBloc, VaultState>(
                buildWhen: (p, n) =>
                    p.isDuplicatesLoading != n.isDuplicatesLoading ||
                    p.duplicateGroups != n.duplicateGroups ||
                    p.isSaving != n.isSaving,
                builder: (context, state) {
                  if (state.isDuplicatesLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.duplicateGroups.isEmpty) {
                    return const _DuplicatesEmptyState();
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: state.duplicateGroups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _DuplicateGroupCard(
                      group: state.duplicateGroups[index],
                      isBusy: state.isSaving,
                    ),
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

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({required this.group, required this.isBusy});

  final DuplicateGroup group;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final primary = group.entries.first;
    final secondaries = group.entries.skip(1).toList(growable: false);
    final service = di.sl<VaultDuplicateService>();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              KvLetterAvatar(letter: group.sharedUrl, size: 34, fontSize: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.sharedUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.rowTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      group.sharedUsername.isEmpty
                          ? '${group.entries.length} records'
                          : '${group.sharedUsername} · ${group.entries.length} records',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.secondary.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DuplicateEntryRow(entry: primary, tagLabel: 'Keep'),
          for (final secondary in secondaries) ...[
            const SizedBox(height: 7),
            _DuplicateEntryRow(entry: secondary, tagLabel: 'Merge'),
            Builder(
              builder: (context) {
                final preview = service.previewMerge(primary, secondary);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (preview.hasAnythingToCopy) ...[
                      const SizedBox(height: 8),
                      _CopyNoticeStrip(colors: colors),
                    ],
                    const SizedBox(height: 8),
                    KvPillButton(
                      label: 'Merge and move duplicate',
                      compact: true,
                      onPressed: isBusy
                          ? null
                          : () => _handleMerge(context, primary, secondary),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleMerge(
    BuildContext context,
    VaultEntry primary,
    VaultEntry secondary,
  ) async {
    final service = di.sl<VaultDuplicateService>();
    final preview = service.previewMerge(primary, secondary);
    final confirmed = await _showMergePreviewSheet(context, preview);
    if (confirmed == ConfirmDecision.confirm && context.mounted) {
      context.read<VaultBloc>().add(
        MergeDuplicateEntries(primaryId: primary.id, secondaryId: secondary.id),
      );
    }
  }
}

class _CopyNoticeStrip extends StatelessWidget {
  const _CopyNoticeStrip({required this.colors});

  final KeyVaultColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.attentionTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          KvIcon(glyph: AppGlyph.info, size: 15, color: colors.attentionText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Some data will be copied',
              style: AppTextStyles.meta.copyWith(
                fontSize: 12,
                color: colors.attentionText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateEntryRow extends StatelessWidget {
  const _DuplicateEntryRow({required this.entry, required this.tagLabel});

  final VaultEntry entry;
  final String tagLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final modifiedAt = entry.updatedAt ?? entry.createdAt;
    final meta = <String>[
      if (modifiedAt != null) 'Modified ${_formatEntryDateTime(modifiedAt)}',
      ..._extraDataDescriptors(entry),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surfaceNested,
        borderRadius: BorderRadius.circular(AppRadii.rowNested),
      ),
      child: Row(
        children: [
          KvTag(
            label: tagLabel,
            variant: tagLabel == 'Keep'
                ? KvTagVariant.positive
                : KvTagVariant.neutral,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title.isEmpty ? '(Untitled)' : entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.rowTitle.copyWith(
                    fontSize: 13.5,
                    color: colors.textPrimary,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.meta.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _extraDataDescriptors(VaultEntry entry) {
    final has = <String>[
      if (entry.notes.trim().isNotEmpty) 'notes',
      if (entry.otpUri != null && entry.otpUri!.isNotEmpty) 'OTP',
    ];
    final descriptors = <String>[];
    if (has.isNotEmpty) {
      descriptors.add('has ${has.join(', ')}');
    }
    if (entry.attachments.isNotEmpty) {
      descriptors.add(
        entry.attachments.length == 1
            ? '1 attachment'
            : '${entry.attachments.length} attachments',
      );
    }
    return descriptors;
  }
}

/// FR-5/AC5/T11/T20: exactly the four `MergePreview` flags — no more, no
/// fewer. `customFieldKeysToCopy` (a list) collapses into a single row.
Future<ConfirmDecision?> _showMergePreviewSheet(
  BuildContext context,
  MergePreview preview,
) {
  return VaultShellRouterScope.of(context).open<ConfirmDecision>(
    context: context,
    surface: MergePreviewSurface<ConfirmDecision>(
      builder: (sheetContext) => _MergePreviewSheet(preview: preview),
    ),
  );
}

class _MergePreviewSheet extends StatelessWidget {
  const _MergePreviewSheet({required this.preview});

  final MergePreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final primaryLabel = preview.primary.title.isEmpty
        ? 'Untitled'
        : preview.primary.title;
    final secondaryLabel = preview.secondary.title.isEmpty
        ? 'Untitled'
        : preview.secondary.title;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'What the merge does',
            style: AppTextStyles.sheetTitle.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Keeps $primaryLabel and moves $secondaryLabel to the recycle '
            "bin, after copying what's missing.",
            style: AppTextStyles.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          // Exactly four rows — one per `MergePreview` flag (T20 counts
          // these via the `merge-flag-row-*` key prefix, since the row
          // widget itself is private to this library).
          _MergePreviewFlagRow(
            key: const ValueKey('merge-flag-row-notes'),
            active: preview.willCopyNotes,
            label: preview.willCopyNotes
                ? 'Notes — will be copied'
                : 'Notes — kept item already has some',
          ),
          const SizedBox(height: 8),
          _MergePreviewFlagRow(
            key: const ValueKey('merge-flag-row-attachments'),
            active: preview.willCopyAttachments,
            label: preview.willCopyAttachments
                ? 'Attachments — missing ones will be copied'
                : 'Attachments — nothing missing to copy',
          ),
          const SizedBox(height: 8),
          _MergePreviewFlagRow(
            key: const ValueKey('merge-flag-row-customFields'),
            active: preview.customFieldKeysToCopy.isNotEmpty,
            label: preview.customFieldKeysToCopy.isEmpty
                ? 'Custom fields — nothing missing to copy'
                : 'Custom fields — ${preview.customFieldKeysToCopy.join(', ')}',
          ),
          const SizedBox(height: 8),
          _MergePreviewFlagRow(
            key: const ValueKey('merge-flag-row-otp'),
            active: preview.willCopyOtp,
            label: preview.willCopyOtp
                ? 'One-time code — will be copied'
                : 'One-time code — kept item already has one',
          ),
          const SizedBox(height: 14),
          Text(
            'Passwords are never merged: the kept record keeps its own.',
            style: AppTextStyles.secondary.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          KvPillButton(
            label: 'Merge and move duplicate',
            onPressed: () => VaultOperationScope.of(
              context,
            ).complete(ConfirmDecision.confirm),
          ),
          const SizedBox(height: 9),
          KvSecondaryPillButton(
            label: 'Cancel',
            onPressed: () => VaultOperationScope.of(
              context,
            ).complete(ConfirmDecision.cancel),
          ),
        ],
      ),
    );
  }
}

class _MergePreviewFlagRow extends StatelessWidget {
  const _MergePreviewFlagRow({
    super.key,
    required this.active,
    required this.label,
  });

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Opacity(
      opacity: active ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadii.row),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: active ? colors.positiveTint : Colors.transparent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: KvIcon(
                glyph: active ? AppGlyph.check : AppGlyph.close,
                size: 16,
                color: active ? colors.positiveText : colors.textTertiary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicatesEmptyState extends StatelessWidget {
  const _DuplicatesEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: colors.positiveTint,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: KvIcon(
                glyph: AppGlyph.check,
                size: 34,
                color: colors.positiveText,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No duplicates found',
              style: AppTextStyles.screenTitle.copyWith(
                fontSize: 24,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No two records share the same site and username. KDBX Vault Manager '
              'checks again every time you open the vault.',
              style: AppTextStyles.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            KvSecondaryPillButton(
              label: 'Check again',
              expand: false,
              onPressed: () =>
                  context.read<VaultBloc>().add(const LoadDuplicates()),
            ),
          ],
        ),
      ),
    );
  }
}
