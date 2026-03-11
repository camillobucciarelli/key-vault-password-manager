part of '../vault_screen.dart';

class _SyncStripActionIcon extends StatelessWidget {
  const _SyncStripActionIcon({
    required this.icon,
    this.highlighted = false,
    this.spinning = false,
  });

  final IconData icon;
  final bool highlighted;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = highlighted
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final background = highlighted
        ? colorScheme.primaryContainer.withValues(alpha: 0.9)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.84);
    final borderColor = highlighted
        ? colorScheme.primary.withValues(alpha: 0.28)
        : colorScheme.outlineVariant.withValues(alpha: 0.55);

    final iconWidget = Icon(icon, size: 16, color: foreground);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: borderColor),
      ),
      child: spinning
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            )
          : iconWidget,
    );
  }
}

Future<void> _openAndroidAutofillSettings(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = AutofillService();
  final status = await service.status;

  if (status == AutofillServiceStatus.unsupported) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Android Autofill is not supported on this device.'),
      ),
    );
    return;
  }

  if (status == AutofillServiceStatus.enabled) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Autofill service is already active.')),
    );
    return;
  }

  await service.requestSetAutofillService();
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Select this app as your Android Autofill service.'),
    ),
  );
}

class _DriveSetupProgressIndicator extends StatelessWidget {
  const _DriveSetupProgressIndicator({
    required this.connected,
    required this.linked,
  });

  final bool connected;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget step({required int number, required bool done}) {
      final activeColor = colorScheme.primary;
      final idleColor = colorScheme.outline.withValues(alpha: 0.7);
      final bg = done
          ? activeColor.withValues(alpha: 0.18)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.8);
      final fg = done ? activeColor : idleColor;

      return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: fg.withValues(alpha: 0.7)),
        ),
        child: done
            ? Icon(AppIcons.check, size: 11, color: fg)
            : Text(
                '$number',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
      );
    }

    return Tooltip(
      message: linked
          ? 'Drive setup complete'
          : connected
          ? 'Link this database'
          : 'Connect Google Drive',
      ignorePointer: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          step(number: 1, done: connected),
          Container(
            width: 10,
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: (connected ? colorScheme.primary : colorScheme.outline)
                .withValues(alpha: 0.45),
          ),
          step(number: 2, done: linked),
        ],
      ),
    );
  }
}

enum _ChildGroupAction { rename, move, delete }

Future<void> _handleChildGroupAction(
  BuildContext context, {
  required VaultGroup group,
  required _ChildGroupAction action,
  required List<VaultGroup> allGroups,
}) async {
  switch (action) {
    case _ChildGroupAction.rename:
      final name = await _showGroupDialog(
        context,
        initialName: group.name,
        title: 'Rename folder',
        actionLabel: 'Save',
      );
      if (name != null && name.trim().isNotEmpty && context.mounted) {
        context.read<VaultBloc>().add(
          RenameVaultGroup(groupId: group.id, newName: name.trim()),
        );
      }
      break;
    case _ChildGroupAction.move:
      final target = await _showMoveTargetDialog(
        context,
        allGroups,
        currentGroupId: group.id,
      );
      if (target != null && context.mounted) {
        context.read<VaultBloc>().add(
          MoveVaultGroup(groupId: group.id, targetGroupId: target),
        );
      }
      break;
    case _ChildGroupAction.delete:
      final confirmed = await _showDeleteConfirm(
        context,
        label: 'Permanently delete this empty folder?',
        actionLabel: 'Delete forever',
      );
      if (confirmed && context.mounted) {
        context.read<VaultBloc>().add(DeleteVaultGroup(group.id));
      }
      break;
  }
}
