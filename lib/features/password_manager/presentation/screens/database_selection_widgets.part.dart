part of 'database_selection_screen.dart';

class _SelectionActionTile extends StatelessWidget {
  const _SelectionActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant),
          color: colorScheme.surface.withValues(alpha: 0.72),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              AppIcons.chevronRight,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentDatabasesSection extends StatefulWidget {
  const _RecentDatabasesSection({
    required this.recentDatabasePaths,
    required this.onOpen,
    required this.onRemove,
  });

  final List<String> recentDatabasePaths;
  final Future<void> Function(String path) onOpen;
  final Future<void> Function(String path) onRemove;

  @override
  State<_RecentDatabasesSection> createState() =>
      _RecentDatabasesSectionState();
}

class _RecentDatabasesSectionState extends State<_RecentDatabasesSection> {
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
              'Recent databases',
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
            child: _RecentDatabaseTile(
              path: pathValue,
              fileName: fileName,
              isMostRecent: isMostRecent,
              onOpen: () => widget.onOpen(pathValue),
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

class _RecentDatabaseTile extends StatefulWidget {
  const _RecentDatabaseTile({
    required this.path,
    required this.fileName,
    required this.isMostRecent,
    required this.onOpen,
    required this.onRemove,
  });

  final String path;
  final String fileName;
  final bool isMostRecent;
  final Future<void> Function() onOpen;
  final Future<void> Function() onRemove;

  @override
  State<_RecentDatabaseTile> createState() => _RecentDatabaseTileState();
}

class _RecentDatabaseTileState extends State<_RecentDatabaseTile> {
  bool _isDriveLinked = false;
  bool _loadingDriveState = true;
  int? _sizeBytes;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final mapping = await di.sl<DatabaseSyncRepository>().getMapping(
        widget.path,
      );

      int? sizeBytes;
      if (!kIsWeb) {
        final file = File(widget.path);
        if (await file.exists()) {
          sizeBytes = await file.length();
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isDriveLinked = mapping != null;
        _sizeBytes = sizeBytes;
        _loadingDriveState = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingDriveState = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: widget.onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
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
                          widget.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (widget.isMostRecent)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.55),
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
                    widget.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (_sizeBytes != null)
                        Text(
                          _formatSize(_sizeBytes!),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (_sizeBytes != null)
                        Text(
                          '  •  ',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (_loadingDriveState)
                        Text(
                          'Checking Drive link...',
                          style: Theme.of(context).textTheme.labelSmall,
                        )
                      else if (_isDriveLinked)
                        Row(
                          children: [
                            const Icon(AppIcons.cloud, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Linked to Drive',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        )
                      else
                        Text(
                          'Local only',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isMobilePlatform)
              FilledButton.tonalIcon(
                onPressed: widget.onOpen,
                icon: const Icon(AppIcons.folderOpen),
                label: const Text('Open'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'More actions',
              onSelected: (value) {
                if (value == 'remove') {
                  widget.onRemove();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(AppIcons.more),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
