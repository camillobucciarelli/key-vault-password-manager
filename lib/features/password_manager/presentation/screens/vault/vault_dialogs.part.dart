part of '../vault_screen.dart';

// spec-004: the entry editor dialog (_EntryDialog/_showEntryDialog), the
// OTP QR scanner and its camera-denied fallback moved to
// vault_entry_editor.part.dart. This file keeps the other, out-of-scope
// dialogs: folder create/rename, delete confirm, move target, attachments
// manager, Drive link, sync conflict.

Future<GroupEditResult?> _showGroupDialog(
  BuildContext context, {
  String? initialName,
  String title = 'Create folder',
  String actionLabel = 'Create',
}) async {
  var name = initialName ?? '';
  final formKey = GlobalKey<FormState>();
  final result = await VaultShellRouterScope.of(context).open<GroupEditResult>(
    context: context,
    surface: GroupEditSurface<GroupEditResult>(
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          insetPadding: _dialogInsetPadding(context),
          contentPadding: _dialogContentPadding(context),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          content: SizedBox(
            width: _dialogContentWidth(context, 380),
            child: Form(
              key: formKey,
              child: TextFormField(
                initialValue: initialName ?? '',
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Folder name'),
                onChanged: (value) => name = value,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Folder name is required.';
                  }
                  return null;
                },
              ),
            ),
          ),
          actions: _adaptiveDialogActions(context, [
            TextButton(
              onPressed: () => VaultOperationScope.of(context).cancel(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                VaultOperationScope.of(
                  context,
                ).complete(GroupEditResult(name.trim()));
              },
              child: Text(actionLabel),
            ),
          ]),
        );
      },
    ),
  );
  return result;
}

Future<bool> _showDeleteConfirm(
  BuildContext context, {
  required String label,
  String actionLabel = 'Delete',
}) async {
  final confirmed = await _showConfirmation(
    context,
    title: 'Confirm delete',
    body: label,
    confirmLabel: actionLabel,
  );
  return confirmed == ConfirmDecision.confirm;
}

Future<MoveTargetResult?> _showMoveTargetDialog(
  BuildContext context,
  List<VaultGroup> groups, {
  String? currentGroupId,
}) async {
  String selectedGroupId;
  final options = groups
      .where((group) => group.id != currentGroupId)
      .toList(growable: false);

  if (options.isEmpty) {
    return null;
  }
  selectedGroupId = options.first.id;

  return VaultShellRouterScope.of(context).open<MoveTargetResult>(
    context: context,
    surface: MoveTargetSurface<MoveTargetResult>(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Move to folder'),
              insetPadding: _dialogInsetPadding(context),
              contentPadding: _dialogContentPadding(context),
              actionsOverflowDirection: VerticalDirection.down,
              actionsOverflowButtonSpacing: 8,
              content: DropdownButtonFormField<String>(
                initialValue: selectedGroupId,
                isExpanded: true,
                icon: const Icon(AppIcons.chevronDown),
                items: options
                    .map(
                      (group) => DropdownMenuItem(
                        value: group.id,
                        child: Text(group.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    selectedGroupId = value;
                  });
                },
              ),
              actions: _adaptiveDialogActions(context, [
                TextButton(
                  onPressed: () => VaultOperationScope.of(context).cancel(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => VaultOperationScope.of(
                    context,
                  ).complete(MoveTargetResult(selectedGroupId)),
                  child: const Text('Move'),
                ),
              ]),
            );
          },
        );
      },
    ),
  );
}

enum _AttachmentAction { export, remove }

Future<VaultDone?> _showAttachmentsDialog(
  BuildContext context,
  VaultEntry entry,
) async {
  return VaultShellRouterScope.of(context).open<VaultDone>(
    context: context,
    surface: AttachmentsSurface<VaultDone>(
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Attachments'),
          insetPadding: _dialogInsetPadding(dialogContext),
          contentPadding: _dialogContentPadding(dialogContext),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          content: SizedBox(
            width: _dialogContentWidth(dialogContext, 520),
            child: entry.attachments.isEmpty
                ? const Text('No attachments for this record.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final attachment = entry.attachments[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(AppIcons.attachment),
                        title: Text(attachment.name),
                        subtitle: Text(_formatBytes(attachment.size)),
                        trailing: PopupMenuButton<_AttachmentAction>(
                          onSelected: (action) async {
                            if (!dialogContext.mounted) {
                              return;
                            }

                            switch (action) {
                              case _AttachmentAction.export:
                                final directory =
                                    await FilePicker.getDirectoryPath();
                                if (directory != null &&
                                    dialogContext.mounted) {
                                  dialogContext.read<VaultBloc>().add(
                                    ExportVaultAttachment(
                                      entryId: entry.id,
                                      attachmentKey: attachment.key,
                                      destinationDirectory: directory,
                                    ),
                                  );
                                  VaultOperationScope.of(
                                    dialogContext,
                                  ).complete(const VaultDone());
                                }
                                break;
                              case _AttachmentAction.remove:
                                final confirmed = await _showDeleteConfirm(
                                  dialogContext,
                                  label:
                                      'Remove attachment ${attachment.name}?',
                                  actionLabel: 'Remove',
                                );
                                if (confirmed && dialogContext.mounted) {
                                  dialogContext.read<VaultBloc>().add(
                                    RemoveVaultAttachment(
                                      entryId: entry.id,
                                      attachmentKey: attachment.key,
                                    ),
                                  );
                                  VaultOperationScope.of(
                                    dialogContext,
                                  ).complete(const VaultDone());
                                }
                                break;
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _AttachmentAction.export,
                              child: Text('Export'),
                            ),
                            PopupMenuItem(
                              value: _AttachmentAction.remove,
                              child: Text('Remove'),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemCount: entry.attachments.length,
                  ),
          ),
          actions: _adaptiveDialogActions(dialogContext, [
            TextButton(
              onPressed: () async {
                final result = await FilePicker.pickFiles(
                  allowMultiple: false,
                  withData: false,
                );
                final path = result?.files.single.path;
                if (path != null && dialogContext.mounted) {
                  dialogContext.read<VaultBloc>().add(
                    AddVaultAttachment(entryId: entry.id, filePath: path),
                  );
                  VaultOperationScope.of(
                    dialogContext,
                  ).complete(const VaultDone());
                }
              },
              child: const Text('Add attachment'),
            ),
            FilledButton(
              onPressed: () => VaultOperationScope.of(
                dialogContext,
              ).complete(const VaultDone()),
              child: const Text('Close'),
            ),
          ]),
        );
      },
    ),
  );
}

Future<void> _showSyncConflictDialog(
  BuildContext context,
  SyncConflict conflict,
) async {
  final resolution = await VaultShellRouterScope.of(context)
      .open<SyncConflictRouteResult>(
        context: context,
        surface: SyncConflictSurface<SyncConflictRouteResult>(
          builder: (dialogContext) => _SyncConflictSheet(conflict: conflict),
        ),
      );

  if (!context.mounted) {
    return;
  }

  context.read<VaultBloc>().add(const ClearVaultSyncFeedback());

  if (resolution == null ||
      resolution.resolution == SyncConflictResolution.cancel) {
    return;
  }

  context.read<VaultBloc>().add(
    SyncCurrentDatabaseNow(resolution: resolution.resolution),
  );
}

/// T9: two version cards radius 20 padding 14/16 with a 40 square, checksum
/// mono 11, `remoteModifiedTime`; Keep local / Use remote / Cancel with
/// which-side labels. `SyncConflictResolution` semantics unchanged.
class _SyncConflictSheet extends StatelessWidget {
  const _SyncConflictSheet({required this.conflict});

  final SyncConflict conflict;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
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
            'Both versions changed',
            style: AppTextStyles.sheetTitleLarge.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This device and "${conflict.driveFileName}" on Drive were both '
            'edited since the last sync. Pick which one to keep — the '
            'other is not deleted, it stays as a Drive revision.',
            style: AppTextStyles.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          _VersionCard(
            label: 'This device',
            meta: _shortChecksum(conflict.localChecksum),
            background: colors.attentionTint,
            foreground: colors.attentionText,
          ),
          const SizedBox(height: 9),
          _VersionCard(
            label: 'Drive',
            meta: _shortChecksum(conflict.remoteChecksum),
            secondaryMeta: conflict.remoteModifiedTime == null
                ? null
                : 'Modified ${_formatSyncDateTime(conflict.remoteModifiedTime!)}',
            background: colors.surface,
            foreground: colors.textSecondary,
          ),
          const SizedBox(height: 10),
          // Material ancestor of its own: `ListTile` (inside
          // `ExpansionTile`) paints ink/background on the nearest
          // Material, and the sheet's own rounded-top DecoratedBox would
          // otherwise hide it (Flutter's own debug assertion catches this).
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Technical details',
                style: AppTextStyles.secondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              children: [
                _syncConflictDetailRow(
                  'Local checksum',
                  _shortChecksum(conflict.localChecksum),
                ),
                _syncConflictDetailRow(
                  'Remote checksum',
                  _shortChecksum(conflict.remoteChecksum),
                ),
                _syncConflictDetailRow(
                  'Previous local checksum',
                  _shortChecksumOrDash(conflict.previousLocalChecksum),
                ),
                _syncConflictDetailRow(
                  'Previous remote checksum',
                  _shortChecksumOrDash(conflict.previousRemoteChecksum),
                ),
                _syncConflictDetailRow(
                  'Remote modified',
                  conflict.remoteModifiedTime == null
                      ? '-'
                      : _formatSyncDateTime(conflict.remoteModifiedTime!),
                ),
                _syncConflictDetailRow(
                  'Local changed',
                  _boolLabel(conflict.localChanged),
                ),
                _syncConflictDetailRow(
                  'Remote changed',
                  _boolLabel(conflict.remoteChanged),
                ),
                _syncConflictDetailRow(
                  'First sync no baseline',
                  _boolLabel(conflict.firstSyncWithoutBaseline),
                ),
                _syncConflictDetailRow(
                  'Remote checksum source',
                  conflict.remoteChecksumComputedFromDownload == true
                      ? 'download-fallback'
                      : 'metadata-md5',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          KvPillButton(
            label: 'Keep local',
            onPressed: () => VaultOperationScope.of(context).complete(
              const SyncConflictRouteResult(SyncConflictResolution.keepLocal),
            ),
          ),
          const SizedBox(height: 9),
          KvSecondaryPillButton(
            label: 'Use remote',
            onPressed: () => VaultOperationScope.of(context).complete(
              const SyncConflictRouteResult(SyncConflictResolution.useRemote),
            ),
          ),
          const SizedBox(height: 9),
          Center(
            child: TextButton(
              onPressed: () => VaultOperationScope.of(context).complete(
                const SyncConflictRouteResult(SyncConflictResolution.cancel),
              ),
              child: Text(
                'Cancel',
                style: AppTextStyles.body.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.label,
    required this.meta,
    required this.background,
    required this.foreground,
    this.secondaryMeta,
  });

  final String label;
  final String meta;
  final String? secondaryMeta;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.ground,
              borderRadius: BorderRadius.circular(AppRadii.iconSquare),
            ),
            alignment: Alignment.center,
            child: KvIcon(
              glyph: label == 'This device' ? AppGlyph.desktop : AppGlyph.cloud,
              size: 18,
              color: foreground,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.rowTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (secondaryMeta != null)
                  Text(
                    secondaryMeta!,
                    style: AppTextStyles.meta.copyWith(color: foreground),
                  ),
                Text(
                  meta,
                  style: AppTextStyles.secret.copyWith(
                    fontSize: 11,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _syncConflictDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 168, child: Text('$label:')),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

String _shortChecksum(String checksum) {
  if (checksum.length <= 12) {
    return checksum;
  }
  return '${checksum.substring(0, 12)}...';
}

String _shortChecksumOrDash(String? checksum) {
  if (checksum == null || checksum.isEmpty) {
    return '-';
  }
  return _shortChecksum(checksum);
}

String _boolLabel(bool? value) {
  if (value == null) {
    return '-';
  }
  return value ? 'true' : 'false';
}
