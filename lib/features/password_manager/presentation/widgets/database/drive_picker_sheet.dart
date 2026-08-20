import 'package:flutter/material.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_radii.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/keyvault_colors.dart';
import '../../../../../core/widgets/kv_bottom_sheet.dart';
import '../../../../../core/widgets/kv_pill_button.dart';
import '../../../domain/models/drive_account_summary.dart';
import '../../../domain/models/drive_remote_file.dart';
import 'drive_picker_skeleton.dart';

class DrivePickerSheetResult {
  const DrivePickerSheetResult.file(this.file)
    : createAndUpload = false,
      switchAccount = false;

  const DrivePickerSheetResult.createAndUpload()
    : file = null,
      createAndUpload = true,
      switchAccount = false;

  const DrivePickerSheetResult.switchAccount()
    : file = null,
      createAndUpload = false,
      switchAccount = true;

  final DriveRemoteFile? file;
  final bool createAndUpload;
  final bool switchAccount;
}

/// FR-3: Drive picker — skeleton loading, then either the `.kdbx` file list
/// or the empty state naming the connected account (C-2) with create+upload
/// / switch-account actions.
Future<DrivePickerSheetResult?> showDrivePickerSheet(
  BuildContext context, {
  required Future<DrivePickerData> Function() loadPickerData,
}) {
  return KvBottomSheet.show<DrivePickerSheetResult>(
    context: context,
    builder: (_) => _DrivePickerSheetContent(loadPickerData: loadPickerData),
  );
}

/// Preserves the former dialog's exact granular OAuth error copy (moved
/// here from `database_selection_screen.dart`, C-3-adjacent: still never
/// renders a raw `e.toString()` for a recognized failure).
String _driveOpenErrorMessage(Object error) {
  final message = error.toString();
  final normalized = message.toLowerCase();

  if (normalized.contains('google sign-in cancelled')) {
    return 'Google sign-in was cancelled during authorization. Please try again and grant Drive permissions.';
  }
  if (normalized.contains(
    'google account selected, but drive permission was not granted',
  )) {
    return 'Account selected, but Drive permission was not granted. Please try again and accept the requested permissions.';
  }
  if (normalized.contains('android google sign-in is not configured')) {
    return 'Android Google Sign-In is not configured. Check GOOGLE_WEB_CLIENT_ID.';
  }
  if (normalized.contains('ios google sign-in is not configured')) {
    return 'iOS Google Sign-In is not configured. Check GOOGLE_IOS_CLIENT_ID.';
  }
  if (normalized.contains('authorization was not granted')) {
    return 'Google Drive permission was not granted. Enable Drive access and try again.';
  }
  if (normalized.contains('authorization needs to be renewed') ||
      normalized.contains('authorization is outdated') ||
      normalized.contains('google account not connected')) {
    return 'Google Drive session expired or unavailable. Tap "Open from Google Drive" again and complete reconnection.';
  }
  return 'Unable to open database from Google Drive.';
}

class _DrivePickerSheetContent extends StatefulWidget {
  const _DrivePickerSheetContent({required this.loadPickerData});

  final Future<DrivePickerData> Function() loadPickerData;

  @override
  State<_DrivePickerSheetContent> createState() =>
      _DrivePickerSheetContentState();
}

class _DrivePickerSheetContentState extends State<_DrivePickerSheetContent> {
  DrivePickerData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.loadPickerData();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final data = _data;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Text(
            'Open from Google Drive',
            textAlign: TextAlign.center,
            style: AppTextStyles.sheetTitleLarge.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Text(
              _driveOpenErrorMessage(_error!),
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: colors.attentionText),
            )
          else if (data == null) ...[
            const DrivePickerSkeletonRow(),
            const DrivePickerSkeletonRow(),
            const DrivePickerSkeletonRow(),
          ] else if (data.files.isEmpty)
            _DriveEmptyState(account: data.account)
          else
            ...data.files.map(
              (file) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(DrivePickerSheetResult.file(file)),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                    child: Row(
                      children: [
                        Icon(AppIcons.file, color: colors.iconNeutral),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.rowTitle.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          AppIcons.chevronRight,
                          color: colors.iconNeutral,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DriveEmptyState extends StatelessWidget {
  const _DriveEmptyState({required this.account});

  final DriveAccountSummary account;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final label = account.email ?? account.displayLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'No .kdbx files found for $label.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 16),
        KvPillButton(
          label: 'Create & upload a new database',
          onPressed: () => Navigator.of(
            context,
          ).pop(const DrivePickerSheetResult.createAndUpload()),
        ),
        const SizedBox(height: 10),
        KvSecondaryPillButton(
          label: 'Switch account',
          onPressed: () => Navigator.of(
            context,
          ).pop(const DrivePickerSheetResult.switchAccount()),
        ),
      ],
    );
  }
}
