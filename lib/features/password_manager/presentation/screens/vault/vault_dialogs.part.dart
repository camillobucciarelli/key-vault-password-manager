part of '../vault_screen.dart';

class _EntryDialogPayload {
  const _EntryDialogPayload({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    required this.otpUri,
    required this.customFields,
    required this.attachmentPaths,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String otpUri;
  final List<VaultCustomField> customFields;
  final List<String> attachmentPaths;
}

class _CustomFieldFormRow {
  _CustomFieldFormRow({
    required this.id,
    required this.key,
    required this.value,
  });

  final int id;
  String key;
  String value;
}

Future<_EntryDialogPayload?> _showEntryDialog(
  BuildContext context, {
  VaultEntry? initial,
}) async {
  return showDialog<_EntryDialogPayload>(
    context: context,
    builder: (_) => _EntryDialog(initial: initial),
  );
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({this.initial});

  final VaultEntry? initial;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _passwordController;
  late String _title;
  late String _username;
  late String _password;
  late String _url;
  late String _notes;
  late String _otpUri;
  var _passwordVisible = false;
  var _nextCustomFieldId = 0;
  late List<_CustomFieldFormRow> _customFieldRows;
  final List<String> _attachmentPaths = [];

  @override
  void initState() {
    super.initState();
    _title = widget.initial?.title ?? '';
    _username = widget.initial?.username ?? '';
    _password = widget.initial?.password ?? '';
    _url = widget.initial?.url ?? '';
    _notes = widget.initial?.notes ?? '';
    _otpUri = widget.initial?.otpUri ?? '';
    _passwordController = TextEditingController(text: _password);

    _customFieldRows =
        widget.initial?.customFields
            .where((field) => !_isOtpFieldKey(field.key))
            .map(
              (field) =>
                  _buildCustomFieldRow(key: field.key, value: field.value),
            )
            .toList(growable: true) ??
        <_CustomFieldFormRow>[];
    if (_customFieldRows.isEmpty) {
      _customFieldRows = [_buildCustomFieldRow()];
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  _CustomFieldFormRow _buildCustomFieldRow({
    String key = '',
    String value = '',
  }) {
    return _CustomFieldFormRow(
      id: _nextCustomFieldId++,
      key: key,
      value: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strength = _evaluatePasswordStrength(_password);
    final colorScheme = Theme.of(context).colorScheme;
    final strengthColor = switch (strength.level) {
      _PasswordStrengthLevel.weak => colorScheme.error,
      _PasswordStrengthLevel.fair => colorScheme.tertiary,
      _PasswordStrengthLevel.good => colorScheme.primary,
      _PasswordStrengthLevel.strong => AppColors.success,
    };

    return AlertDialog(
      title: Text(widget.initial == null ? 'Add record' : 'Edit record'),
      insetPadding: _dialogInsetPadding(context),
      contentPadding: _dialogContentPadding(context),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      content: SizedBox(
        width: _dialogContentWidth(context, 500),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                TextFormField(
                  initialValue: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (value) => _title = value,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Title is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                  onChanged: (value) => _username = value,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: !_passwordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _passwordVisible = !_passwordVisible;
                              });
                            },
                            icon: Icon(
                              _passwordVisible ? AppIcons.eyeOff : AppIcons.eye,
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _password = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      width: 48,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () async {
                          final generatedPassword =
                              await _showPasswordGeneratorDialog(context);
                          if (generatedPassword == null) {
                            return;
                          }
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _passwordController.text = generatedPassword;
                            _password = generatedPassword;
                          });
                        },
                        child: const Icon(
                          AppIcons.magic,
                          semanticLabel: 'Generate secure password',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: strength.score,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(8),
                      valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Security: ${strength.label}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: strengthColor),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: _url,
                  decoration: const InputDecoration(labelText: 'URL'),
                  onChanged: (value) => _url = value,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: _notes,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  onChanged: (value) => _notes = value,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey('entry-otp-uri-$_otpUri'),
                  initialValue: _otpUri,
                  decoration: InputDecoration(
                    labelText: 'OTP URI (otpauth://...)',
                    suffixIcon: _supportsOtpQrScan()
                        ? Tooltip(
                            message: 'Scan QR',
                            ignorePointer: true,
                            child: IconButton(
                              onPressed: () async {
                                final scannedOtpUri = await _scanOtpUriFromQr(
                                  context,
                                );
                                if (scannedOtpUri == null) {
                                  return;
                                }
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _otpUri = scannedOtpUri;
                                });
                              },
                              icon: const Icon(AppIcons.qrCode),
                            ),
                          )
                        : null,
                  ),
                  onChanged: (value) => _otpUri = value,
                  validator: (value) => _validateOtpUri(value ?? ''),
                ),
                const SizedBox(height: 10),
                FormField<void>(
                  validator: (_) {
                    for (final value in _attachmentPaths) {
                      if (value.trim().isEmpty) {
                        return 'One attachment path is invalid.';
                      }
                    }
                    return null;
                  },
                  builder: (fieldState) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Attachments',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final result = await FilePicker.platform
                                    .pickFiles(allowMultiple: false);
                                final filePath = result?.files.single.path;
                                if (filePath == null || filePath.isEmpty) {
                                  return;
                                }
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _attachmentPaths.add(filePath);
                                });
                                fieldState.didChange(null);
                              },
                              icon: const Icon(AppIcons.add, size: 16),
                              label: const Text('Add'),
                            ),
                          ],
                        ),
                        if (_attachmentPaths.isEmpty)
                          Text(
                            'No attachments selected.',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          ..._attachmentPaths.map((filePath) {
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(AppIcons.attachment),
                              title: Text(
                                path.basename(filePath),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                filePath,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Tooltip(
                                message: 'Remove attachment',
                                ignorePointer: true,
                                child: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _attachmentPaths.remove(filePath);
                                    });
                                    fieldState.didChange(null);
                                  },
                                  icon: const Icon(AppIcons.close),
                                ),
                              ),
                            );
                          }),
                        if (fieldState.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              fieldState.errorText!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                FormField<void>(
                  validator: (_) => _validateCustomFieldRows(_customFieldRows),
                  builder: (fieldState) {
                    final textTheme = Theme.of(context).textTheme;
                    final colorScheme = Theme.of(context).colorScheme;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Custom fields',
                                style: textTheme.labelLarge,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _customFieldRows.add(_buildCustomFieldRow());
                                });
                                fieldState.didChange(null);
                              },
                              icon: const Icon(AppIcons.add, size: 16),
                              label: const Text('Add field'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._customFieldRows.map((row) {
                          return Padding(
                            key: ValueKey('entry-custom-field-row-${row.id}'),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    initialValue: row.key,
                                    decoration: const InputDecoration(
                                      labelText: 'Key',
                                    ),
                                    onChanged: (value) {
                                      row.key = value;
                                      fieldState.didChange(null);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    initialValue: row.value,
                                    decoration: const InputDecoration(
                                      labelText: 'Value',
                                    ),
                                    onChanged: (value) {
                                      row.value = value;
                                      fieldState.didChange(null);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Remove field',
                                  ignorePointer: true,
                                  child: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _customFieldRows.removeWhere(
                                          (candidate) => candidate.id == row.id,
                                        );
                                      });
                                      fieldState.didChange(null);
                                    },
                                    icon: const Icon(AppIcons.deleteSweep),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (fieldState.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              fieldState.errorText!,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: _adaptiveDialogActions(context, [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _EntryDialogPayload(
                title: _title.trim(),
                username: _username.trim(),
                password: _passwordController.text,
                url: _url.trim(),
                notes: _notes.trim(),
                otpUri: _otpUri.trim(),
                customFields: _buildCustomFields(
                  customFieldRows: _customFieldRows,
                  otpUri: _otpUri,
                ),
                attachmentPaths: List<String>.unmodifiable(_attachmentPaths),
              ),
            );
          },
          child: Text(widget.initial == null ? 'Create' : 'Save'),
        ),
      ]),
    );
  }
}

bool _supportsOtpQrScan() {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}

Future<String?> _scanOtpUriFromQr(BuildContext context) async {
  if (!_supportsOtpQrScan()) {
    return null;
  }

  return showDialog<String>(
    context: context,
    builder: (_) => const _OtpQrScannerDialog(),
  );
}

Future<String?> _showGroupDialog(
  BuildContext context, {
  String? initialName,
  String title = 'Create folder',
  String actionLabel = 'Create',
}) async {
  var name = initialName ?? '';
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) {
                return;
              }
              Navigator.of(context).pop(name.trim());
            },
            child: Text(actionLabel),
          ),
        ]),
      );
    },
  );
  return result;
}

Future<bool> _showDeleteConfirm(
  BuildContext context, {
  required String label,
  String actionLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Confirm delete'),
        insetPadding: _dialogInsetPadding(context),
        contentPadding: _dialogContentPadding(context),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        content: Text(label),
        actions: _adaptiveDialogActions(context, [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ]),
      );
    },
  );
  return confirmed ?? false;
}

Future<String?> _showMoveTargetDialog(
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

  return showDialog<String>(
    context: context,
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
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selectedGroupId),
                child: const Text('Move'),
              ),
            ]),
          );
        },
      );
    },
  );
}

enum _AttachmentAction { export, remove }

Future<void> _showAttachmentsDialog(
  BuildContext context,
  VaultEntry entry,
) async {
  await showDialog<void>(
    context: context,
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
                              final directory = await FilePicker.platform
                                  .getDirectoryPath();
                              if (directory != null && dialogContext.mounted) {
                                dialogContext.read<VaultBloc>().add(
                                  ExportVaultAttachment(
                                    entryId: entry.id,
                                    attachmentKey: attachment.key,
                                    destinationDirectory: directory,
                                  ),
                                );
                                Navigator.of(dialogContext).pop();
                              }
                              break;
                            case _AttachmentAction.remove:
                              final confirmed = await _showDeleteConfirm(
                                dialogContext,
                                label: 'Remove attachment ${attachment.name}?',
                                actionLabel: 'Remove',
                              );
                              if (confirmed && dialogContext.mounted) {
                                dialogContext.read<VaultBloc>().add(
                                  RemoveVaultAttachment(
                                    entryId: entry.id,
                                    attachmentKey: attachment.key,
                                  ),
                                );
                                Navigator.of(dialogContext).pop();
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
              final result = await FilePicker.platform.pickFiles(
                allowMultiple: false,
                withData: false,
              );
              final path = result?.files.single.path;
              if (path != null && dialogContext.mounted) {
                dialogContext.read<VaultBloc>().add(
                  AddVaultAttachment(entryId: entry.id, filePath: path),
                );
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Add attachment'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ]),
      );
    },
  );
}

class _LinkDatabaseChoice {
  const _LinkDatabaseChoice._({this.remoteFileId, this.remoteFileName});

  final String? remoteFileId;
  final String? remoteFileName;

  factory _LinkDatabaseChoice.existing(String remoteFileId) {
    return _LinkDatabaseChoice._(remoteFileId: remoteFileId);
  }

  factory _LinkDatabaseChoice.newFile(String remoteFileName) {
    return _LinkDatabaseChoice._(remoteFileName: remoteFileName);
  }
}

Future<_LinkDatabaseChoice?> _showLinkDatabaseDialog(
  BuildContext context,
) async {
  final vaultBloc = context.read<VaultBloc>();
  final localDatabaseName = path.basename(vaultBloc.state.databasePath);
  final suggestedRemoteFileName =
      localDatabaseName.toLowerCase().endsWith('.kdbx')
      ? localDatabaseName
      : '$localDatabaseName.kdbx';
  final fileSearchController = TextEditingController();
  var useExisting = false;
  String? selectedExistingId;

  final result = await showDialog<_LinkDatabaseChoice?>(
    context: context,
    builder: (dialogContext) {
      return BlocProvider.value(
        value: vaultBloc,
        child: StatefulBuilder(
          builder: (dialogInnerContext, setState) {
            final state = dialogInnerContext.watch<VaultBloc>().state;
            final remoteFiles = state.remoteDriveFiles;
            final compactWidth =
                MediaQuery.sizeOf(dialogInnerContext).width < 380;
            final searchQuery = fileSearchController.text.trim();
            final isSearchingFiles = searchQuery.isNotEmpty;

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
                                compactWidth ? 'Create new' : 'Create new file',
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
                              controller: fileSearchController,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(AppIcons.search),
                                labelText: 'Search .kdbx file',
                                hintText: 'Type file name',
                              ),
                              onChanged: (value) {
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
                                                    ? Icons.radio_button_checked
                                                    : Icons
                                                          .radio_button_unchecked,
                                              ),
                                              title: Text(
                                                file.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              selected: isSelected,
                                              onTap: () {
                                                setState(() {
                                                  selectedExistingId = file.id;
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
                  onPressed: () => Navigator.of(dialogContext).pop(null),
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
                            Navigator.of(dialogContext).pop(
                              _LinkDatabaseChoice.existing(selectedExistingId!),
                            );
                            return;
                          }

                          Navigator.of(dialogContext).pop(
                            _LinkDatabaseChoice.newFile(
                              suggestedRemoteFileName,
                            ),
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
  );
  fileSearchController.dispose();
  return result;
}

Future<void> _showSyncConflictDialog(
  BuildContext context,
  SyncConflict conflict,
) async {
  final resolution = await showDialog<SyncConflictResolution>(
    context: context,
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
                Navigator.of(dialogContext).pop(SyncConflictResolution.cancel),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(SyncConflictResolution.useRemote),
            child: const Text('Use remote'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(SyncConflictResolution.keepLocal),
            child: const Text('Keep local'),
          ),
        ]),
      );
    },
  );

  if (!context.mounted) {
    return;
  }

  context.read<VaultBloc>().add(const ClearVaultSyncFeedback());

  if (resolution == null || resolution == SyncConflictResolution.cancel) {
    return;
  }

  context.read<VaultBloc>().add(SyncCurrentDatabaseNow(resolution: resolution));
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
