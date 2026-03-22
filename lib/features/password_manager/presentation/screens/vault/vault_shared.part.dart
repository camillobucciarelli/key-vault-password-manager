part of '../vault_screen.dart';

String? _validateCustomFieldRows(List<_CustomFieldFormRow> rows) {
  final seen = <String>{};
  for (final row in rows) {
    final key = row.key.trim();
    final value = row.value.trim();
    if (key.isEmpty && value.isEmpty) {
      continue;
    }

    if (key.isEmpty) {
      return 'Custom field key cannot be empty.';
    }

    final normalized = key.toLowerCase();
    if (seen.contains(normalized)) {
      return 'Custom field keys must be unique.';
    }
    seen.add(normalized);
  }

  return null;
}

String? _validateOtpUri(String otpUri) {
  final trimmed = otpUri.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || !trimmed.startsWith('otpauth://')) {
    return 'OTP URI must start with otpauth://';
  }

  return null;
}

bool _isOtpFieldKey(String key) {
  final normalized = key.toLowerCase().trim();
  return normalized == 'otp' ||
      normalized == 'totp' ||
      normalized == 'otpauth' ||
      normalized.contains('otp');
}

List<VaultCustomField> _buildCustomFields({
  required List<_CustomFieldFormRow> customFieldRows,
  required String otpUri,
}) {
  final fields = customFieldRows
      .map(
        (row) => VaultCustomField(key: row.key.trim(), value: row.value.trim()),
      )
      .where((field) => field.key.isNotEmpty)
      .where((field) => !_isOtpFieldKey(field.key))
      .toList(growable: true);

  final trimmedOtpUri = otpUri.trim();
  if (trimmedOtpUri.isNotEmpty) {
    fields.add(VaultCustomField(key: 'otp', value: trimmedOtpUri));
  }

  return fields;
}

double _dialogContentWidth(BuildContext context, double preferredWidth) {
  final viewport = MediaQuery.sizeOf(context).width;
  final availableWidth = viewport - 56;
  if (availableWidth < 280) {
    return viewport - 24;
  }
  return math.min(preferredWidth, availableWidth);
}

double _dialogContentHeight(BuildContext context, double preferredHeight) {
  final viewport = MediaQuery.sizeOf(context).height;
  final availableHeight = viewport - 140;
  return math.min(preferredHeight, availableHeight);
}

bool _isVeryCompactDialogWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 340;
}

EdgeInsets _dialogInsetPadding(BuildContext context) {
  if (_isVeryCompactDialogWidth(context)) {
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 20);
  }
  return const EdgeInsets.symmetric(horizontal: 20, vertical: 24);
}

EdgeInsets _dialogContentPadding(BuildContext context) {
  if (_isVeryCompactDialogWidth(context)) {
    return const EdgeInsets.fromLTRB(12, 10, 12, 6);
  }
  return const EdgeInsets.fromLTRB(20, 18, 20, 12);
}

List<Widget> _adaptiveDialogActions(
  BuildContext context,
  List<Widget> actions,
) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 360) {
    return actions;
  }

  return actions
      .map((action) => SizedBox(width: double.infinity, child: action))
      .toList(growable: false);
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _syncStatusLabel(DatabaseSyncStatus status) {
  return switch (status) {
    DatabaseSyncStatus.idle => 'Idle',
    DatabaseSyncStatus.syncing => 'Syncing',
    DatabaseSyncStatus.success => 'Synced',
    DatabaseSyncStatus.error => 'Error',
    DatabaseSyncStatus.conflict => 'Conflict',
    DatabaseSyncStatus.disconnected => 'Disconnected',
  };
}

Color _syncStatusColor(DatabaseSyncStatus status, ColorScheme colorScheme) {
  return switch (status) {
    DatabaseSyncStatus.idle => colorScheme.outline,
    DatabaseSyncStatus.syncing => colorScheme.primary,
    DatabaseSyncStatus.success => AppColors.success,
    DatabaseSyncStatus.error => colorScheme.error,
    DatabaseSyncStatus.conflict => AppColors.warning,
    DatabaseSyncStatus.disconnected => colorScheme.outline,
  };
}

void _showSyncSnackBar(
  BuildContext context,
  String message, {
  required DatabaseSyncStatus status,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  final background = switch (status) {
    DatabaseSyncStatus.success => AppColors.success,
    DatabaseSyncStatus.conflict => AppColors.warning,
    DatabaseSyncStatus.error => theme.colorScheme.error,
    DatabaseSyncStatus.syncing => theme.colorScheme.primary,
    DatabaseSyncStatus.idle => theme.colorScheme.surfaceContainerHighest,
    DatabaseSyncStatus.disconnected =>
      theme.colorScheme.surfaceContainerHighest,
  };
  final useLightForeground =
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;

  final foreground = switch (status) {
    DatabaseSyncStatus.error => theme.colorScheme.onError,
    DatabaseSyncStatus.syncing =>
      useLightForeground ? Colors.white : Colors.black87,
    DatabaseSyncStatus.success =>
      useLightForeground ? Colors.white : Colors.black87,
    DatabaseSyncStatus.conflict =>
      useLightForeground ? Colors.white : Colors.black87,
    DatabaseSyncStatus.idle => theme.colorScheme.onSurface,
    DatabaseSyncStatus.disconnected => theme.colorScheme.onSurface,
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: foreground)),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        closeIconColor: foreground,
        action: action,
      ),
    );
}

Future<void> _startDriveLinkFlow(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  final state = bloc.state;
  if (!state.isDriveConnected) {
    bloc.add(const ConnectGoogleDrive());
    return;
  }

  bloc.add(const LoadDriveRemoteFiles());
  final choice = await _showLinkDatabaseDialog(context);
  if (choice == null || !context.mounted) {
    return;
  }

  bloc.add(
    LinkCurrentDatabaseToDrive(
      remoteFileId: choice.remoteFileId,
      remoteFileName: choice.remoteFileName,
    ),
  );
}

String _formatSyncDateTime(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$d-$m-$y $hh:$mm';
}

String _formatEntryDateTime(DateTime? value) {
  if (value == null) {
    return 'Not available';
  }
  return _formatSyncDateTime(value);
}

String _csvSourceFormatLabel(VaultCsvSourceFormat format) {
  return switch (format) {
    VaultCsvSourceFormat.bitwarden => 'Bitwarden',
    VaultCsvSourceFormat.onePassword => '1Password',
    VaultCsvSourceFormat.lastPass => 'LastPass',
    VaultCsvSourceFormat.chrome => 'Chrome',
    VaultCsvSourceFormat.applePasswords => 'Apple Passwords',
    VaultCsvSourceFormat.generic => 'Generic CSV',
  };
}

Future<void> _startCsvImportFlow(BuildContext context) async {
  final picked = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    type: FileType.custom,
    allowedExtensions: const ['csv'],
    withData: false,
  );
  final filePath = picked?.files.single.path;
  if (filePath == null || !context.mounted) {
    return;
  }

  final importService = di.sl<VaultCsvImportService>();
  final messenger = ScaffoldMessenger.of(context);

  VaultCsvParseResult preview;
  try {
    preview = await importService.parseFile(filePath);
  } catch (e) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    return;
  }

  if (!context.mounted) {
    return;
  }

  final avoidDuplicatesChoice = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final formatLabel = _csvSourceFormatLabel(preview.format);
      final skipped = preview.skippedRows;
      final valid = preview.items.length;
      final total = preview.totalRows;
      var avoidDuplicates = true;

      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: const Text('Import CSV'),
            insetPadding: _dialogInsetPadding(dialogContext),
            contentPadding: _dialogContentPadding(dialogContext),
            actionsOverflowDirection: VerticalDirection.down,
            actionsOverflowButtonSpacing: 8,
            content: SizedBox(
              width: _dialogContentWidth(dialogContext, 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detected format: $formatLabel'),
                  const SizedBox(height: 6),
                  Text('Rows found: $total'),
                  Text('Valid records: $valid'),
                  Text('Skipped rows: $skipped'),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: avoidDuplicates,
                    onChanged: preview.items.isEmpty
                        ? null
                        : (value) {
                            setState(() {
                              avoidDuplicates = value ?? true;
                            });
                          },
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Avoid duplicates'),
                    subtitle: const Text(
                      'Uses title + username + URL comparison.',
                    ),
                  ),
                  if (preview.items.isNotEmpty)
                    Text(
                      'This will add records to the current folder.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            actions: _adaptiveDialogActions(dialogContext, [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: preview.items.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(avoidDuplicates),
                child: const Text('Import'),
              ),
            ]),
          );
        },
      );
    },
  );

  if (avoidDuplicatesChoice != null && context.mounted) {
    context.read<VaultBloc>().add(
      ImportVaultEntriesFromCsv(
        filePath: filePath,
        avoidDuplicates: avoidDuplicatesChoice,
      ),
    );
  }
}
