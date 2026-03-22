part of 'database_unlock_screen.dart';

class _KeyFileSelector extends StatelessWidget {
  const _KeyFileSelector({
    required this.keyFilePath,
    required this.onPickKeyFile,
    required this.onClearKeyFile,
  });

  final String? keyFilePath;
  final Future<void> Function() onPickKeyFile;
  final VoidCallback onClearKeyFile;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (keyFilePath == null) {
      return OutlinedButton.icon(
        onPressed: onPickKeyFile,
        icon: const Icon(AppIcons.attachment),
        label: const Text('Select key file'),
      );
    }

    return StyledInfoContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      borderRadius: 12,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: isDark ? 0.72 : 0.92),
      borderColor: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: isDark ? 1 : 0.9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.fileKey, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  !kIsWeb ? p.basename(keyFilePath!) : keyFilePath!,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 4),
            Text(
              'Stored in app internal key storage.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPickKeyFile,
                icon: const Icon(AppIcons.edit),
                label: const Text('Change key file'),
              ),
              OutlinedButton.icon(
                onPressed: onClearKeyFile,
                icon: const Icon(AppIcons.close),
                label: const Text('Remove key file'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
