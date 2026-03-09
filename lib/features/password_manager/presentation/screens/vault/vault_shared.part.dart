part of '../vault_screen.dart';

String? _validateCustomFieldsText(String text) {
  final seen = <String>{};
  final lines = text.split('\n');
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      return 'Invalid custom field format. Use key=value.';
    }

    final key = line.substring(0, separatorIndex).trim();
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
  required String customFieldsText,
  required String otpUri,
}) {
  final fields = _parseCustomFields(
    customFieldsText,
  ).where((field) => !_isOtpFieldKey(field.key)).toList(growable: true);

  final trimmedOtpUri = otpUri.trim();
  if (trimmedOtpUri.isNotEmpty) {
    fields.add(VaultCustomField(key: 'otp', value: trimmedOtpUri));
  }

  return fields;
}

List<VaultCustomField> _parseCustomFields(String text) {
  final fields = <VaultCustomField>[];
  final lines = text.split('\n');
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    final key = line.substring(0, separatorIndex).trim();
    final value = line.substring(separatorIndex + 1).trim();
    if (key.isEmpty) {
      continue;
    }
    fields.add(VaultCustomField(key: key, value: value));
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

  final foreground = switch (status) {
    DatabaseSyncStatus.error => theme.colorScheme.onError,
    DatabaseSyncStatus.idle => theme.colorScheme.onSurface,
    DatabaseSyncStatus.disconnected => theme.colorScheme.onSurface,
    _ => Colors.white,
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
  bloc.add(const LoadDriveRemoteFolders());
  final choice = await _showLinkDatabaseDialog(context);
  if (choice == null || !context.mounted) {
    return;
  }

  bloc.add(
    LinkCurrentDatabaseToDrive(
      remoteFileId: choice.remoteFileId,
      remoteFileName: choice.remoteFileName,
      remoteFolderId: choice.remoteFolderId,
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
  return '$y-$m-$d $hh:$mm';
}
