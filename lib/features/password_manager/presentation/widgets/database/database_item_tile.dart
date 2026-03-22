import 'package:flutter/material.dart';

import '../../../../../core/theme/app_icons.dart';
import 'database_action_menu.dart';

class DatabaseItemTile extends StatelessWidget {
  const DatabaseItemTile({
    super.key,
    required this.fileName,
    required this.path,
    required this.isMostRecent,
    required this.onOpen,
    required this.onExport,
    required this.onRemove,
  });

  final String fileName;
  final String path;
  final bool isMostRecent;
  final Future<void> Function() onOpen;
  final Future<void> Function() onExport;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 1 : 0.9,
            ),
          ),
          color: colorScheme.surface.withValues(alpha: isDark ? 0.7 : 0.92),
        ),
        child: Row(
          children: [
            const Icon(AppIcons.file),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isMostRecent)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: isDark ? 0.55 : 0.7,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Most recent',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            DatabaseActionMenu(
              onOpen: () => onOpen(),
              onExport: () => onExport(),
              onRemove: () => onRemove(),
            ),
          ],
        ),
      ),
    );
  }
}
