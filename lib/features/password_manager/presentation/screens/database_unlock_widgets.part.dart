part of 'database_unlock_screen.dart';

class _KeyFileSelector extends StatelessWidget {
  const _KeyFileSelector({
    required this.keyFilePath,
    required this.onPickKeyFile,
  });

  final String? keyFilePath;
  final Future<void> Function() onPickKeyFile;

  @override
  Widget build(BuildContext context) {
    if (keyFilePath == null) {
      return OutlinedButton.icon(
        onPressed: onPickKeyFile,
        icon: const Icon(AppIcons.attachment),
        label: const Text('Select Key File'),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.fileKey, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isManagedStoragePlatform ? p.basename(keyFilePath!) : keyFilePath!,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isManagedStoragePlatform)
            Wrap(
              spacing: 2,
              children: [
                Tooltip(
                  message: 'Change key file',
                  ignorePointer: true,
                  child: IconButton(
                    onPressed: onPickKeyFile,
                    icon: const Icon(AppIcons.edit),
                  ),
                ),
                Tooltip(
                  message: 'Remove key file',
                  ignorePointer: true,
                  child: IconButton(
                    onPressed: () {
                      context.read<DatabaseUnlockBloc>().add(
                        const UpdateKeyFilePath(null),
                      );
                    },
                    icon: const Icon(AppIcons.close),
                  ),
                ),
              ],
            )
          else ...[
            Tooltip(
              message: 'Change key file',
              ignorePointer: true,
              child: IconButton(
                onPressed: onPickKeyFile,
                icon: const Icon(AppIcons.edit),
              ),
            ),
            Tooltip(
              message: 'Remove key file',
              ignorePointer: true,
              child: IconButton(
                onPressed: () {
                  context.read<DatabaseUnlockBloc>().add(
                    const UpdateKeyFilePath(null),
                  );
                },
                icon: const Icon(AppIcons.close),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
