part of '../vault_screen.dart';

Future<ConfirmDecision?> _showConfirmation(
  BuildContext context, {
  required String title,
  required String body,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Confirm',
}) => VaultShellRouterScope.of(context).confirm(
  context: context,
  title: title,
  body: body,
  cancelLabel: cancelLabel,
  confirmLabel: confirmLabel,
);
