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
                textInputAction: TextInputAction.done,
                onChanged: (value) => name = value,
                // Enter submits, same as the Create button.
                onFieldSubmitted: (_) {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }
                  VaultOperationScope.of(
                    context,
                  ).complete(GroupEditResult(name.trim()));
                },
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
                        subtitle: Text(formatBytes(attachment.size)),
                        trailing: PopupMenuButton<_AttachmentAction>(
                          // Vertical dots everywhere: the adaptive default
                          // is horizontal on Apple platforms.
                          icon: const Icon(AppIcons.more),
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

// T9: sync conflict dialog/sheet moved to vault_sync.part.dart (Sync-owned).
