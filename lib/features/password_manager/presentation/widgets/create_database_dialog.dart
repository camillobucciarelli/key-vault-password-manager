import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _generateKeyFile = false;
  String? _keyFilePath;
  String? _keyFileName;
  String? _generatedKeyFilePath;

  @override
  void dispose() {
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
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Select destination for generated key file',
      fileName: 'database.key',
    );

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
          content: Text('Choose where to save the generated key file.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      CreateDatabaseCredentials(
        password: _passwordCtrl.text,
        keyFilePath: _keyFilePath,
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
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set a Master Password to protect your database. You may also add a Key File for extra security.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

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

              // Key File section
              Text('Key File (optional)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Generate key file automatically'),
                subtitle: const Text(
                  'You will choose where to save the generated file.',
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
                        label: const Text('Choose key file destination'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      )
                    else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(AppIcons.fileKey),
                        title: Text(
                          _generatedKeyFilePath!,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(AppIcons.close),
                          tooltip: 'Remove generated key file path',
                          onPressed: _clearGeneratedKeyFilePath,
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
                    minimumSize: const Size(double.infinity, 44),
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
                  trailing: IconButton(
                    icon: const Icon(AppIcons.close),
                    tooltip: 'Remove key file',
                    onPressed: _clearKeyFile,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class CreateDatabaseCredentials {
  const CreateDatabaseCredentials({
    required this.password,
    this.keyFilePath,
    this.generateKeyFile = false,
    this.generatedKeyFilePath,
  });

  final String password;
  final String? keyFilePath;
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
