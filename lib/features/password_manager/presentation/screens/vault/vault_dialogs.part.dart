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

Future<DriveLinkResult?> _showLinkDatabaseDialog(BuildContext context) async {
  final vaultBloc = context.read<VaultBloc>();
  final localDatabaseName = path.basename(vaultBloc.state.databasePath);
  final suggestedRemoteFileName =
      localDatabaseName.toLowerCase().endsWith('.kdbx')
      ? localDatabaseName
      : '$localDatabaseName.kdbx';
  var searchQuery = '';
  var useExisting = false;
  String? selectedExistingId;

  final result = await VaultShellRouterScope.of(context).open<DriveLinkResult>(
    context: context,
    surface: SyncLinkSurface<DriveLinkResult>(
      builder: (dialogContext) {
        return BlocProvider.value(
          value: vaultBloc,
          child: StatefulBuilder(
            builder: (dialogInnerContext, setState) {
              final state = dialogInnerContext.watch<VaultBloc>().state;
              final remoteFiles = state.remoteDriveFiles;
              final compactWidth =
                  MediaQuery.sizeOf(dialogInnerContext).width < 380;
              final isSearchingFiles = searchQuery.trim().isNotEmpty;

              if (selectedExistingId == null && remoteFiles.isNotEmpty) {
                selectedExistingId = remoteFiles.first.id;
              } else if (selectedExistingId != null &&
                  !remoteFiles.any((file) => file.id == selectedExistingId)) {
                selectedExistingId = remoteFiles.isEmpty
                    ? null
                    : remoteFiles.first.id;
              }

              final canSubmit =
                  !useExisting || (selectedExistingId?.isNotEmpty ?? false);

              return AlertDialog(
                title: const Text('Link database to Drive'),
                insetPadding: _dialogInsetPadding(dialogInnerContext),
                contentPadding: _dialogContentPadding(dialogInnerContext),
                actionsOverflowDirection: VerticalDirection.down,
                actionsOverflowButtonSpacing: 8,
                content: SizedBox(
                  width: _dialogContentWidth(dialogInnerContext, 460),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose where this database should sync in Google Drive.',
                          style: Theme.of(
                            dialogInnerContext,
                          ).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SegmentedButton<bool>(
                            segments: [
                              ButtonSegment<bool>(
                                value: false,
                                label: Text(
                                  compactWidth
                                      ? 'Create new'
                                      : 'Create new file',
                                ),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                label: Text(
                                  compactWidth
                                      ? 'Use existing'
                                      : 'Use existing file',
                                ),
                              ),
                            ],
                            selected: {useExisting},
                            onSelectionChanged: (selection) {
                              setState(() {
                                useExisting = selection.first;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!useExisting)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'A new file will be created in My Drive root.',
                                style: Theme.of(
                                  dialogInnerContext,
                                ).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 10),
                              SelectableText(
                                suggestedRemoteFileName,
                                style: Theme.of(
                                  dialogInnerContext,
                                ).textTheme.titleSmall,
                              ),
                            ],
                          ),
                        if (useExisting)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Choose an existing .kdbx file',
                                style: Theme.of(
                                  dialogInnerContext,
                                ).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(AppIcons.search),
                                  labelText: 'Search .kdbx file',
                                  hintText: 'Type file name',
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    searchQuery = value;
                                  });
                                  vaultBloc.add(
                                    LoadDriveRemoteFiles(query: value),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              state.isLoadingRemoteDriveFiles
                                  ? const Padding(
                                      padding: EdgeInsets.only(top: 12),
                                      child: CircularProgressIndicator(),
                                    )
                                  : remoteFiles.isEmpty
                                  ? Text(
                                      isSearchingFiles
                                          ? 'No matching .kdbx files found.'
                                          : 'No .kdbx files found. Switch to "Create new file" to continue.',
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isSearchingFiles
                                              ? 'Search results (${remoteFiles.length})'
                                              : 'Recent .kdbx files (${remoteFiles.length})',
                                          style: Theme.of(
                                            dialogInnerContext,
                                          ).textTheme.labelMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          constraints: const BoxConstraints(
                                            maxHeight: 220,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Theme.of(
                                                dialogInnerContext,
                                              ).colorScheme.outlineVariant,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: ListView.separated(
                                            shrinkWrap: true,
                                            itemCount: remoteFiles.length,
                                            separatorBuilder: (_, _) => Divider(
                                              height: 1,
                                              color: Theme.of(
                                                dialogInnerContext,
                                              ).colorScheme.outlineVariant,
                                            ),
                                            itemBuilder: (context, index) {
                                              final file = remoteFiles[index];
                                              final isSelected =
                                                  selectedExistingId == file.id;
                                              return ListTile(
                                                dense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                leading: Icon(
                                                  isSelected
                                                      ? Icons
                                                            .radio_button_checked
                                                      : Icons
                                                            .radio_button_unchecked,
                                                ),
                                                title: Text(
                                                  file.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                selected: isSelected,
                                                onTap: () {
                                                  setState(() {
                                                    selectedExistingId =
                                                        file.id;
                                                  });
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                actions: _adaptiveDialogActions(dialogContext, [
                  TextButton(
                    onPressed: () =>
                        VaultOperationScope.of(dialogContext).cancel(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: canSubmit
                        ? () {
                            if (useExisting) {
                              if (selectedExistingId == null ||
                                  selectedExistingId!.isEmpty) {
                                return;
                              }
                              VaultOperationScope.of(dialogContext).complete(
                                DriveLinkResult.existing(selectedExistingId!),
                              );
                              return;
                            }

                            VaultOperationScope.of(dialogContext).complete(
                              DriveLinkResult.newFile(suggestedRemoteFileName),
                            );
                          }
                        : null,
                    child: const Text('Link'),
                  ),
                ]),
              );
            },
          ),
        );
      },
    ),
  );
  return result;
}

Future<void> _showSyncConflictDialog(
  BuildContext context,
  SyncConflict conflict,
) async {
  final resolution = await VaultShellRouterScope.of(context)
      .open<SyncConflictRouteResult>(
        context: context,
        surface: SyncConflictSurface<SyncConflictRouteResult>(
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Sync conflict detected'),
              insetPadding: _dialogInsetPadding(dialogContext),
              contentPadding: _dialogContentPadding(dialogContext),
              actionsOverflowDirection: VerticalDirection.down,
              actionsOverflowButtonSpacing: 8,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The local database and Drive file "${conflict.driveFileName}" both changed. Choose what to keep.',
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text('Technical details'),
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
                ],
              ),
              actions: _adaptiveDialogActions(dialogContext, [
                TextButton(
                  onPressed: () =>
                      VaultOperationScope.of(dialogContext).complete(
                        const SyncConflictRouteResult(
                          SyncConflictResolution.cancel,
                        ),
                      ),
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      VaultOperationScope.of(dialogContext).complete(
                        const SyncConflictRouteResult(
                          SyncConflictResolution.useRemote,
                        ),
                      ),
                  child: const Text('Use remote'),
                ),
                FilledButton(
                  onPressed: () =>
                      VaultOperationScope.of(dialogContext).complete(
                        const SyncConflictRouteResult(
                          SyncConflictResolution.keepLocal,
                        ),
                      ),
                  child: const Text('Keep local'),
                ),
              ]),
            );
          },
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
