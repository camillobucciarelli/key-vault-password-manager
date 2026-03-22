import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_icons.dart';

class DatabaseActionMenu extends StatelessWidget {
  const DatabaseActionMenu({
    super.key,
    required this.onOpen,
    required this.onExport,
    required this.onRemove,
  });

  final VoidCallback onOpen;
  final VoidCallback onExport;
  final VoidCallback onRemove;

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
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(value: 'open', child: Text('Open')),
        PopupMenuItem<String>(value: 'export', child: Text('Export')),
        PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(AppIcons.more),
      ),
    );
  }
}
