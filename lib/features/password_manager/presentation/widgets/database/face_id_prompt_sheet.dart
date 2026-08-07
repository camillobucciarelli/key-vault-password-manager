import 'package:flutter/material.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/keyvault_colors.dart';
import '../../../../../core/widgets/kv_bottom_sheet.dart';
import '../../../../../core/widgets/kv_pill_button.dart';

/// FR-5 post-Drive prompt: "Use Face ID for `<basename>`?" (approved copy).
/// Preserves the former dialog's exact "Not now"/"Enable" action labels.
Future<bool?> showFaceIdPromptSheet(
  BuildContext context, {
  required String basename,
}) {
  return KvBottomSheet.show<bool>(
    context: context,
    isDismissible: false,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).extension<KeyVaultColors>()!;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.attentionTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.fingerprint, color: colors.attentionText),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Use Face ID for $basename?',
              textAlign: TextAlign.center,
              style: AppTextStyles.sheetTitleLarge.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This database came from Google Drive. Do you want to require '
              'biometric authentication before unlock when available?',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 18),
            KvPillButton(
              label: 'Enable',
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      );
    },
  );
}
