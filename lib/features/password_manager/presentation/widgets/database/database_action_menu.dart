import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_icons.dart';

class DatabaseActionMenu extends StatelessWidget {
  const DatabaseActionMenu({
    super.key,
    required this.onOpen,
    required this.onExport,
    required this.onRemove,
    this.onLocate,
  });

  final VoidCallback onOpen;
  final VoidCallback onExport;
  final VoidCallback onRemove;

  /// Only present for `isMissing` items (FR-1 Locate).
  final VoidCallback? onLocate;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      onSelected: (value) {
        switch (value) {
          case 'open':
            onOpen();
            break;
          case 'export':
            onExport();
            break;
          case 'remove':
            onRemove();
            break;
          case 'locate':
            onLocate?.call();
            break;
        }
      },
      itemBuilder: (_) => [
        if (onLocate != null)
          const PopupMenuItem<String>(value: 'locate', child: Text('Locate')),
        const PopupMenuItem<String>(value: 'open', child: Text('Open')),
        const PopupMenuItem<String>(value: 'export', child: Text('Export')),
        const PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(AppIcons.more),
      ),
    );
  }
}
