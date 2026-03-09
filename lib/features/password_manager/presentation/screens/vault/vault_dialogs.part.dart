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
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String otpUri;
  final List<VaultCustomField> customFields;
}

Future<_EntryDialogPayload?> _showEntryDialog(
  BuildContext context, {
  VaultEntry? initial,
}) async {
  var title = initial?.title ?? '';
  var username = initial?.username ?? '';
  var password = initial?.password ?? '';
  var url = initial?.url ?? '';
  var notes = initial?.notes ?? '';
  var otpUri = initial?.otpUri ?? '';
  var customFieldsText =
      initial?.customFields
          .where((field) => !_isOtpFieldKey(field.key))
          .map((field) => '${field.key}=${field.value}')
          .join('\n') ??
      '';
  final formKey = GlobalKey<FormState>();
  var passwordVisible = false;

  final result = await showDialog<_EntryDialogPayload>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(initial == null ? 'Add record' : 'Edit record'),
            content: SizedBox(
              width: _dialogContentWidth(context, 500),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue: title,
                        decoration: const InputDecoration(labelText: 'Title'),
                        onChanged: (value) => title = value,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Title is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: username,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
                        onChanged: (value) => username = value,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: password,
                        obscureText: !passwordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                passwordVisible = !passwordVisible;
                              });
                            },
                            icon: Icon(
                              passwordVisible ? AppIcons.eyeOff : AppIcons.eye,
                            ),
                          ),
                        ),
                        onChanged: (value) => password = value,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: url,
                        decoration: const InputDecoration(labelText: 'URL'),
                        onChanged: (value) => url = value,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: notes,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(labelText: 'Notes'),
                        onChanged: (value) => notes = value,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        key: ValueKey('entry-otp-uri-$otpUri'),
                        initialValue: otpUri,
                        decoration: InputDecoration(
                          labelText: 'OTP URI (otpauth://...)',
                          suffixIcon: _supportsOtpQrScan()
                              ? IconButton(
                                  tooltip: 'Scan QR',
                                  onPressed: () async {
                                    final scannedOtpUri =
                                        await _scanOtpUriFromQr(context);
                                    if (scannedOtpUri == null) {
                                      return;
                                    }
                                    setState(() {
                                      otpUri = scannedOtpUri;
                                    });
                                  },
                                  icon: const Icon(AppIcons.qrCode),
                                )
                              : null,
                        ),
                        onChanged: (value) => otpUri = value,
                        validator: (value) => _validateOtpUri(value ?? ''),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: customFieldsText,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Custom fields (key=value, one per line)',
                        ),
                        onChanged: (value) => customFieldsText = value,
                        validator: (value) {
                          final parseError = _validateCustomFieldsText(
                            value ?? '',
                          );
                          return parseError;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }

                  Navigator.of(context).pop(
                    _EntryDialogPayload(
                      title: title.trim(),
                      username: username.trim(),
                      password: password,
                      url: url.trim(),
                      notes: notes.trim(),
                      otpUri: otpUri.trim(),
                      customFields: _buildCustomFields(
                        customFieldsText: customFieldsText,
                        otpUri: otpUri,
                      ),
                    ),
                  );
                },
                child: Text(initial == null ? 'Create' : 'Save'),
              ),
            ],
          );
        },
      );
    },
  );
  return result;
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
        actions: [
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
        ],
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
        content: Text(label),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
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
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selectedGroupId),
                child: const Text('Move'),
              ),
            ],
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
        actions: [
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
        ],
      );
    },
  );
}

Future<void> _showTotpDialog(BuildContext context, VaultEntry entry) async {
  if (entry.otpUri != null) {
    await _showTotpUriDialog(context, entry.otpUri!);
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('OTP'),
        content: const Text('No valid OTP URI configured for this record.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _showTotpUriDialog(BuildContext context, String otpUri) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('OTP'),
        content: _TotpDialogContent(otpUri: otpUri),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _OtpQrScannerDialog extends StatefulWidget {
  const _OtpQrScannerDialog();

  @override
  State<_OtpQrScannerDialog> createState() => _OtpQrScannerDialogState();
}

class _OtpQrScannerDialogState extends State<_OtpQrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _isHandlingCapture = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan OTP QR'),
      content: SizedBox(
        width: _dialogContentWidth(context, 320),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) async {
                if (_isHandlingCapture) {
                  return;
                }

                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue?.trim();
                  if (value == null || value.isEmpty) {
                    continue;
                  }

                  _isHandlingCapture = true;
                  if (value.startsWith('otpauth://')) {
                    if (context.mounted) {
                      Navigator.of(context).pop(value);
                    }
                    return;
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('QR does not contain a valid OTP URI.'),
                      ),
                    );
                  }
                  _isHandlingCapture = false;
                  return;
                }
              },
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _TotpDialogContent extends StatefulWidget {
  const _TotpDialogContent({required this.otpUri});

  final String otpUri;

  @override
  State<_TotpDialogContent> createState() => _TotpDialogContentState();
}

class _TotpDialogContentState extends State<_TotpDialogContent> {
  late Timer _timer;
  DateTime _nowUtc = DateTime.now().toUtc();

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
    final totpData = TotpUtils.fromOtpAuthUri(widget.otpUri, _nowUtc);
    if (totpData == null) {
      return const Text('Invalid OTP URI.');
    }

    return SizedBox(
      width: _dialogContentWidth(context, 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            totpData.code,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontFeatures: const []),
          ),
          const SizedBox(height: 8),
          Text('Expires in ${totpData.remainingSeconds}s'),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              animationDuration: _VaultUiTokens.buttonTransitionDuration,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: totpData.code));
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('OTP copied.')));
            },
            icon: const Icon(AppIcons.copy),
            label: const Text('Copy code'),
          ),
        ],
      ),
    );
  }
}

class _LinkDatabaseChoice {
  const _LinkDatabaseChoice._({
    this.remoteFileId,
    this.remoteFileName,
    this.remoteFolderId,
  });

  final String? remoteFileId;
  final String? remoteFileName;
  final String? remoteFolderId;

  factory _LinkDatabaseChoice.existing(String remoteFileId) {
    return _LinkDatabaseChoice._(remoteFileId: remoteFileId);
  }

  factory _LinkDatabaseChoice.newFile({
    String? remoteFileName,
    String? remoteFolderId,
  }) {
    return _LinkDatabaseChoice._(
      remoteFileName: remoteFileName,
      remoteFolderId: remoteFolderId,
    );
  }
}

Future<_LinkDatabaseChoice?> _showLinkDatabaseDialog(
  BuildContext context,
) async {
  final vaultBloc = context.read<VaultBloc>();
  final folderSearchController = TextEditingController();
  var useExisting = false;
  var remoteFileName = '';
  String? selectedExistingId;
  String? selectedFolderId;

  final result = await showDialog<_LinkDatabaseChoice?>(
    context: context,
    builder: (dialogContext) {
      return BlocProvider.value(
        value: vaultBloc,
        child: StatefulBuilder(
          builder: (dialogInnerContext, setState) {
            final state = dialogInnerContext.watch<VaultBloc>().state;
            final remoteFiles = state.remoteDriveFiles;
            final remoteFolders = state.remoteDriveFolders;
            final compactWidth =
                MediaQuery.sizeOf(dialogInnerContext).width < 380;

            final folderOptions = <DriveRemoteFolder>[
              const DriveRemoteFolder(id: 'root', name: 'My Drive (root)'),
              ...remoteFolders,
            ];

            if (selectedExistingId == null && remoteFiles.isNotEmpty) {
              selectedExistingId = remoteFiles.first.id;
            }
            if (selectedFolderId == null && folderOptions.isNotEmpty) {
              selectedFolderId = folderOptions.first.id;
            } else if (selectedFolderId != null &&
                !folderOptions.any((folder) => folder.id == selectedFolderId)) {
              selectedFolderId = folderOptions.first.id;
            }

            return AlertDialog(
              title: const Text('Step 2/2: Link database to Drive'),
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
                            TextField(
                              onChanged: (value) {
                                remoteFileName = value;
                              },
                              decoration: const InputDecoration(
                                labelText: 'File name (optional)',
                                hintText: 'my-vault.kdbx',
                                helperText:
                                    'If empty, default .kdbx name is used.',
                                helperMaxLines: 2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Save in Drive folder',
                              style: Theme.of(
                                dialogInnerContext,
                              ).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: folderSearchController,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(AppIcons.search),
                                labelText: 'Search folder',
                                hintText: 'Type folder name',
                              ),
                              onChanged: (value) {
                                vaultBloc.add(
                                  LoadDriveRemoteFolders(query: value),
                                );
                              },
                            ),
                            if (state.isLoadingRemoteDriveFolders)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: CircularProgressIndicator(),
                              )
                            else
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (remoteFolders.isEmpty &&
                                      folderSearchController.text
                                          .trim()
                                          .isNotEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 12),
                                      child: Text('No matching folders found.'),
                                    ),
                                  DropdownButton<String>(
                                    isExpanded: true,
                                    icon: const Icon(AppIcons.chevronDown),
                                    value: selectedFolderId,
                                    items: folderOptions
                                        .map(
                                          (folder) => DropdownMenuItem<String>(
                                            value: folder.id,
                                            child: Text(
                                              folder.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      setState(() {
                                        selectedFolderId = value;
                                      });
                                    },
                                  ),
                                ],
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
                            state.isLoadingRemoteDriveFiles
                                ? const Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: CircularProgressIndicator(),
                                  )
                                : remoteFiles.isEmpty
                                ? const Text(
                                    'No .kdbx files found. Switch to "Create new file" to continue.',
                                  )
                                : DropdownButton<String>(
                                    isExpanded: true,
                                    icon: const Icon(AppIcons.chevronDown),
                                    value: selectedExistingId,
                                    items: remoteFiles
                                        .map(
                                          (file) => DropdownMenuItem<String>(
                                            value: file.id,
                                            child: Text(
                                              file.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      setState(() {
                                        selectedExistingId = value;
                                      });
                                    },
                                  ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (useExisting) {
                      if (selectedExistingId == null ||
                          selectedExistingId!.isEmpty) {
                        return;
                      }
                      Navigator.of(
                        dialogContext,
                      ).pop(_LinkDatabaseChoice.existing(selectedExistingId!));
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _LinkDatabaseChoice.newFile(
                        remoteFileName: remoteFileName.trim(),
                        remoteFolderId:
                            selectedFolderId == null ||
                                selectedFolderId == 'root'
                            ? null
                            : selectedFolderId,
                      ),
                    );
                  },
                  child: const Text('Link'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
  folderSearchController.dispose();
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
        content: Text(
          'The local database and Drive file "${conflict.driveFileName}" both changed. Choose what to keep.',
        ),
        actions: [
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
        ],
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
