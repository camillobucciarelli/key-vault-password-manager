import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_radii.dart';
import '../../../../../../core/theme/app_text_styles.dart';
import '../../../../../../core/theme/keyvault_colors.dart';
import '../../../domain/entities/database_record.dart';
import '../../../domain/models/database_selection_item.dart';
import 'database_action_menu.dart';

/// C-1 metadata subtitle: "On this device · biometrics on/off" for local
/// databases, "Google Drive · synced `<relative time>`" (or the existing
/// sync error) for Drive ones. `canonicalPath` is deliberately not part of
/// this subtitle — it stays available via semantics/overflow only.
String databaseSubtitle(DatabaseSelectionItem item, {DateTime? now}) {
  if (item.sourceType == DatabaseSourceType.drive) {
    if (item.lastSyncError != null && item.lastSyncError!.trim().isNotEmpty) {
      return 'Google Drive · ${item.lastSyncError}';
    }
    final lastSyncAt = item.lastSyncAt;
    if (lastSyncAt == null) {
      return 'Google Drive · not synced yet';
    }
    return 'Google Drive · synced ${_relativeTime(lastSyncAt, now ?? DateTime.now())}';
  }
  final biometrics = item.biometricProtectionEnabled ? 'on' : 'off';
  return 'On this device · biometrics $biometrics';
}

String _relativeTime(DateTime value, DateTime now) {
  final diff = now.difference(value);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class DatabaseItemTile extends StatelessWidget {
  const DatabaseItemTile({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onExport,
    required this.onRemove,
    this.onLocate,
  });

  final DatabaseSelectionItem item;
  final Future<void> Function() onOpen;
  final Future<void> Function() onExport;
  final Future<void> Function() onRemove;

  /// Only invoked for `item.isMissing` (FR-1). Coordinator validates hash
  /// match before rebinding the record — see `LocateMissingDatabase`.
  final Future<void> Function()? onLocate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final active = item.isActive && !item.isMissing;

    return Semantics(
      label: item.displayName,
      value: item.canonicalPath,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: item.isMissing ? onLocate : () => onOpen(),
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.card),
              color: active
                  ? const Color(0xFFFFE1D0) // accent-200, active row tint
                  : colors.surface,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: item.isMissing
                        ? colors.attentionTint
                        : colors.surfaceNested,
                    borderRadius: BorderRadius.circular(AppRadii.iconSquare),
                  ),
                  child: Icon(
                    item.isMissing
                        ? AppIcons.warning
                        : item.sourceType == DatabaseSourceType.drive
                        ? AppIcons.cloud
                        : AppIcons.file,
                    color: item.isMissing ? colors.attentionText : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.rowTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.isMissing
                            ? 'File not found on this device'
                            : databaseSubtitle(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.secondary.copyWith(
                          color: item.isMissing
                              ? colors.attentionText
                              : (active ? colors.actionText : colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.isMissing)
                  TextButton(
                    onPressed: onLocate,
                    child: const Text('Locate'),
                  ),
                DatabaseActionMenu(
                  onOpen: () => onOpen(),
                  onExport: () => onExport(),
                  onRemove: () => onRemove(),
                  onLocate: item.isMissing ? onLocate : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
