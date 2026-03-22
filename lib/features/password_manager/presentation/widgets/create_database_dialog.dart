import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../../../../core/theme/app_icons.dart';

/// A dialog that collects a Master Password (and confirm) plus an optional Key File
/// before creating a new KDBX database.
///
/// Returns a [CreateDatabaseCredentials] when the user confirms, or null if cancelled.
class CreateDatabaseDialog extends StatefulWidget {
  const CreateDatabaseDialog({super.key});

  @override
  State<CreateDatabaseDialog> createState() => _CreateDatabaseDialogState();
}

class _CreateDatabaseDialogState extends State<CreateDatabaseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _databaseNameCtrl = TextEditingController(text: 'new_database.kdbx');
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _biometricProtectionEnabled = false;
  bool _generateKeyFile = false;
  String? _keyFilePath;
  String? _keyFileName;
  String? _generatedKeyFilePath;

  bool get _usesManagedStorage {
    if (kIsWeb) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _databaseNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a Key File',
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _keyFilePath = result.files.single.path;
        _keyFileName = result.files.single.name;
      });
    }
  }

  void _clearKeyFile() {
    setState(() {
      _keyFilePath = null;
      _keyFileName = null;
    });
  }

  Future<void> _pickGeneratedKeyFilePath() async {
    if (_usesManagedStorage) {
      setState(() {
        _generatedKeyFilePath = 'database.key';
      });
      return;
    }

    String? savePath;

    try {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Select destination for generated key file',
        fileName: 'database.key',
      );
    } catch (_) {
      final directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select destination folder for generated key file',
      );
      if (directory != null && directory.isNotEmpty) {
        savePath = path.join(directory, 'database.key');
      }
    }

    if (savePath == null || savePath.isEmpty) {
      return;
    }

    setState(() {
      _generatedKeyFilePath = savePath;
    });
  }

  void _clearGeneratedKeyFilePath() {
    setState(() {
      _generatedKeyFilePath = null;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_generateKeyFile &&
        (_generatedKeyFilePath == null || _generatedKeyFilePath!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose the generated key file option to continue.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      CreateDatabaseCredentials(
        databaseFileName: _databaseNameCtrl.text.trim(),
        password: _passwordCtrl.text,
        keyFilePath: _keyFilePath,
        biometricProtectionEnabled: _biometricProtectionEnabled,
        generateKeyFile: _generateKeyFile,
        generatedKeyFilePath: _generatedKeyFilePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth = _dialogContentWidth(context, 420);

    return AlertDialog(
      title: const Text('New Database Credentials'),
      insetPadding: _dialogInsetPadding(context),
      contentPadding: _dialogContentPadding(context),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose the database file name and security options. On native platforms, the database and generated key file are saved in app internal storage, so export manual backups regularly.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _databaseNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Database file name',
                    prefixIcon: Icon(AppIcons.file),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) {
                      return 'Enter a database file name.';
                    }
                    if (raw.contains(RegExp(r'[\\/:*?"<>|]'))) {
                      return 'Invalid characters in file name.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Master Password
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: !_passwordVisible,
                  decoration: InputDecoration(
                    labelText: 'Master Password',
                    prefixIcon: const Icon(AppIcons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible ? AppIcons.eyeOff : AppIcons.eye,
                      ),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                    ),
                  ),
                  validator: (value) {
                    final hasGeneratedKeyFile =
                        _generateKeyFile &&
                        (_generatedKeyFilePath?.isNotEmpty ?? false);
                    if ((value == null || value.isEmpty) &&
                        _keyFilePath == null &&
                        !hasGeneratedKeyFile) {
                      return 'Please enter a password or choose a Key File.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: !_confirmVisible,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(AppIcons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _confirmVisible ? AppIcons.eyeOff : AppIcons.eye,
                      ),
                      onPressed: () =>
                          setState(() => _confirmVisible = !_confirmVisible),
                    ),
                  ),
                  validator: (value) {
                    if (value != _passwordCtrl.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable biometric protection'),
                  subtitle: const Text(
                    'If enabled, unlock requires biometric authentication when available.',
                  ),
                  value: _biometricProtectionEnabled,
                  onChanged: (value) {
                    setState(() {
                      _biometricProtectionEnabled = value;
                    });
                  },
                ),
                const SizedBox(height: 8),

                // Key File section
                Text('Key File (optional)', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Generate key file automatically'),
                  subtitle: const Text(
                    'On native platforms it will be saved in app internal storage.',
                  ),
                  value: _generateKeyFile,
                  onChanged: (value) {
                    setState(() {
                      _generateKeyFile = value;
                      _keyFilePath = null;
                      _keyFileName = null;
                      if (!value) {
                        _generatedKeyFilePath = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                if (_generateKeyFile)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_generatedKeyFilePath == null)
                        OutlinedButton.icon(
                          onPressed: _pickGeneratedKeyFilePath,
                          icon: const Icon(AppIcons.save),
                          label: Text(
                            _usesManagedStorage
                                ? 'Prepare generated key file'
                                : 'Choose key file destination',
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        )
                      else
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(AppIcons.fileKey),
                          title: Text(
                            _usesManagedStorage
                                ? 'Generated key file will be saved in app internal storage'
                                : _generatedKeyFilePath!,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Tooltip(
                            message: 'Remove generated key file path',
                            ignorePointer: true,
                            child: IconButton(
                              icon: const Icon(AppIcons.close),
                              onPressed: _clearGeneratedKeyFilePath,
                            ),
                          ),
                        ),
                    ],
                  )
                else if (_keyFilePath == null)
                  OutlinedButton.icon(
                    onPressed: _pickKeyFile,
                    icon: const Icon(AppIcons.attachment),
                    label: const Text('Select Key File'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(AppIcons.file),
                    title: Text(
                      _keyFileName ?? _keyFilePath!,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Tooltip(
                      message: 'Remove key file',
                      ignorePointer: true,
                      child: IconButton(
                        icon: const Icon(AppIcons.close),
                        onPressed: _clearKeyFile,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        ..._adaptiveDialogActions(context, [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Create')),
        ]),
      ],
    );
  }
}

List<Widget> _adaptiveDialogActions(
  BuildContext context,
  List<Widget> actions,
) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 360) {
    return actions;
  }

  return actions
      .map((action) => SizedBox(width: double.infinity, child: action))
      .toList(growable: false);
}

bool _isVeryCompactDialogWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 340;
}

EdgeInsets _dialogInsetPadding(BuildContext context) {
  if (_isVeryCompactDialogWidth(context)) {
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 20);
  }
  return const EdgeInsets.symmetric(horizontal: 20, vertical: 24);
}

EdgeInsets _dialogContentPadding(BuildContext context) {
  if (_isVeryCompactDialogWidth(context)) {
    return const EdgeInsets.fromLTRB(12, 10, 12, 6);
  }
  return const EdgeInsets.fromLTRB(20, 18, 20, 12);
}

class CreateDatabaseCredentials {
  const CreateDatabaseCredentials({
    required this.databaseFileName,
    required this.password,
    this.keyFilePath,
    this.biometricProtectionEnabled = false,
    this.generateKeyFile = false,
    this.generatedKeyFilePath,
  });

  final String databaseFileName;
  final String password;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final bool generateKeyFile;
  final String? generatedKeyFilePath;
}

double _dialogContentWidth(BuildContext context, double preferredWidth) {
  final viewport = MediaQuery.sizeOf(context).width;
  final availableWidth = viewport - 56;
  if (availableWidth < 280) {
    return viewport - 24;
  }
  return availableWidth < preferredWidth ? availableWidth : preferredWidth;
}
