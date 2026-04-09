import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/utils/mobile_file_storage.dart';

class InternalKeyFileManagerResult {
  const InternalKeyFileManagerResult({
    this.selectedPath,
    this.currentSelectionDeleted = false,
  });

  final String? selectedPath;
  final bool currentSelectionDeleted;
}

Future<InternalKeyFileManagerResult?> showInternalKeyFileManagerDialog(
  BuildContext context, {
  String? initiallySelectedPath,
}) {
  return showDialog<InternalKeyFileManagerResult>(
    context: context,
    builder: (context) {
      return _InternalKeyFileManagerDialog(
        initiallySelectedPath: initiallySelectedPath,
      );
    },
  );
}

class _InternalKeyFileManagerDialog extends StatefulWidget {
  const _InternalKeyFileManagerDialog({this.initiallySelectedPath});

  final String? initiallySelectedPath;

  @override
  State<_InternalKeyFileManagerDialog> createState() =>
      _InternalKeyFileManagerDialogState();
}

class _InternalKeyFileManagerDialogState
    extends State<_InternalKeyFileManagerDialog> {
  static const _keysSubdirectory = 'keys';

  var _entries = const <AppStorageFileEntry>[];
  var _isLoading = true;
  var _currentSelectionDeleted = false;

  @override
  void initState() {
    super.initState();
    _reloadEntries();
  }

  Future<void> _reloadEntries() async {
    setState(() {
      _isLoading = true;
    });

    final entries = await MobileFileStorage.listFilesInAppDirectory(
      subdirectory: _keysSubdirectory,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _importKeyFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: true,
      dialogTitle: 'Import key file',
    );
    if (!mounted || result == null) {
      return;
    }

    final selected = result.files.single;
    final fallbackName = selected.name.trim().isEmpty
        ? 'database.key'
        : selected.name;
    String? importedPath = selected.path;

    if (importedPath != null && importedPath.trim().isNotEmpty) {
      importedPath = await MobileFileStorage.copyFileToAppDirectory(
        sourcePath: importedPath,
        fallbackFileName: fallbackName,
        subdirectory: _keysSubdirectory,
      );
    } else if (selected.bytes != null) {
      importedPath = await MobileFileStorage.saveBytesToAppDirectory(
        bytes: selected.bytes!,
        fileName: fallbackName,
        subdirectory: _keysSubdirectory,
      );
    }

    if (!mounted || importedPath == null || importedPath.trim().isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      InternalKeyFileManagerResult(
        selectedPath: importedPath,
        currentSelectionDeleted: _currentSelectionDeleted,
      ),
    );
  }

  Future<void> _exportKeyFile(AppStorageFileEntry entry) async {
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Export key file',
      fileName: entry.name,
      type: FileType.any,
    );
    if (!mounted || savePath == null || savePath.trim().isEmpty) {
      return;
    }

    final source = File(entry.path);
    if (!await source.exists()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected key file was not found.')),
      );
      await _reloadEntries();
      return;
    }

    await source.copy(savePath);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Key file exported.')));
  }

  Future<void> _deleteKeyFile(AppStorageFileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete key file?'),
          content: Text('Delete "${entry.name}" from app storage?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await MobileFileStorage.deleteFileFromAppDirectory(
      filePath: entry.path,
      subdirectory: _keysSubdirectory,
    );

    final selected = widget.initiallySelectedPath;
    if (selected != null && selected.trim() == entry.path.trim()) {
      _currentSelectionDeleted = true;
    }

    await _reloadEntries();
  }

  String _formatFileMeta(AppStorageFileEntry entry) {
    final sizeKb = entry.sizeBytes / 1024;
    final date = entry.modifiedAt;
    final dateLabel =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '${sizeKb.toStringAsFixed(1)} KB • $dateLabel';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Internal key files'),
      content: SizedBox(
        width: 520,
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _entries.isEmpty
            ? const Text('No key files in app storage. Import one to use it.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final isCurrent =
                      widget.initiallySelectedPath?.trim() == entry.path.trim();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isCurrent ? AppIcons.check : AppIcons.fileKey,
                      size: 20,
                    ),
                    title: Text(entry.name),
                    subtitle: Text(_formatFileMeta(entry)),
                    onTap: () {
                      Navigator.of(context).pop(
                        InternalKeyFileManagerResult(
                          selectedPath: entry.path,
                          currentSelectionDeleted: _currentSelectionDeleted,
                        ),
                      );
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'select':
                            if (!mounted) {
                              return;
                            }
                            Navigator.of(context).pop(
                              InternalKeyFileManagerResult(
                                selectedPath: entry.path,
                                currentSelectionDeleted:
                                    _currentSelectionDeleted,
                              ),
                            );
                            break;
                          case 'export':
                            await _exportKeyFile(entry);
                            break;
                          case 'delete':
                            await _deleteKeyFile(entry);
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'select',
                          child: Text('Select'),
                        ),
                        PopupMenuItem<String>(
                          value: 'export',
                          child: Text('Export'),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _importKeyFile,
          icon: const Icon(AppIcons.attachment),
          label: const Text('Import'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            InternalKeyFileManagerResult(
              currentSelectionDeleted: _currentSelectionDeleted,
            ),
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
