import 'package:flutter/material.dart';

/// Title/body confirmation with one positive and (optionally) one negative
/// action. A modal `AlertDialog` on every width (2026-09-05, user-directed):
/// only choosers with lists adapt to a bottom sheet on phones
/// (`KvBottomSheet`). Resolves `true` on confirm, `false` on cancel, `null`
/// when dismissed. `cancelLabel: null` makes it a single-action message.
Future<bool?> showKvConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String? cancelLabel = 'Cancel',
  bool dismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: dismissible,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        if (cancelLabel != null)
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
