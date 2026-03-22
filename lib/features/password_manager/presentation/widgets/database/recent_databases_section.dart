import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_icons.dart';
import 'database_item_tile.dart';

class RecentDatabasesSection extends StatefulWidget {
  const RecentDatabasesSection({
    super.key,
    required this.recentDatabasePaths,
    required this.onOpen,
    required this.onExport,
    required this.onRemove,
  });

  final List<String> recentDatabasePaths;
  final Future<void> Function(String path) onOpen;
  final Future<void> Function(String path) onExport;
  final Future<void> Function(String path) onRemove;

  @override
  State<RecentDatabasesSection> createState() => _RecentDatabasesSectionState();
}

class _RecentDatabasesSectionState extends State<RecentDatabasesSection> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    if (widget.recentDatabasePaths.isEmpty) {
      return const SizedBox.shrink();
    }

    final normalizedQuery = _query.trim().toLowerCase();
    var filtered = widget.recentDatabasePaths
        .where((path) {
          if (normalizedQuery.isEmpty) {
            return true;
          }
          final fileName = p.basename(path).toLowerCase();
          return fileName.contains(normalizedQuery) ||
              path.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);

    filtered = filtered.reversed.toList(growable: false);
    final showSearch = widget.recentDatabasePaths.length > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(AppIcons.refresh, size: 18),
            const SizedBox(width: 8),
            Text(
              'Managed databases',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (showSearch) ...[
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Search recent databases',
              prefixIcon: Icon(AppIcons.search),
            ),
            onChanged: (value) {
              setState(() {
                _query = value;
              });
            },
          ),
          const SizedBox(height: 8),
        ],
        ...filtered.asMap().entries.map((entry) {
          final index = entry.key;
          final pathValue = entry.value;
          final fileName = p.basename(pathValue);
          final isMostRecent = index == 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DatabaseItemTile(
              fileName: fileName,
              path: pathValue,
              isMostRecent: isMostRecent,
              onOpen: () => widget.onOpen(pathValue),
              onExport: () => widget.onExport(pathValue),
              onRemove: () => widget.onRemove(pathValue),
            ),
          );
        }),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No recent database matches your search.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
