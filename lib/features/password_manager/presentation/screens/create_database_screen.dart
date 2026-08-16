import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/keyvault_colors.dart';
import '../../../../core/widgets/kv_pill_button.dart';
import '../../domain/models/create_database_step.dart';
import '../bloc/database_selection/database_selection_bloc.dart';
import '../bloc/database_selection/database_selection_event.dart';
import '../bloc/database_selection/database_selection_state.dart';

/// FR-2 create-database wizard, three steps (C-5/C-6): the screen owns
/// ephemeral `TextEditingController`s (including password — it never enters
/// BLoC state); step position/advance policy is coordinator-owned via
/// `DatabaseSelectionBloc`. Pushed as `MaterialPageRoute<CreateDatabaseCredentials>`
/// and returns the typed payload the caller already dispatches
/// `CreateNewDatabase` with, same as the former dialog.
class CreateDatabaseScreen extends StatefulWidget {
  const CreateDatabaseScreen({super.key});

  @override
  State<CreateDatabaseScreen> createState() => _CreateDatabaseScreenState();
}

class _CreateDatabaseScreenState extends State<CreateDatabaseScreen> {
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

  bool get _usesManagedStorage => !kIsWeb;

  @override
  void initState() {
    super.initState();
    context.read<DatabaseSelectionBloc>().add(const StartCreateDatabaseFlow());
  }

  @override
  void dispose() {
    _databaseNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.pickFiles(dialogTitle: 'Select a Key File');
    if (result != null && result.files.single.path != null) {
      setState(() {
        _keyFilePath = result.files.single.path;
        _keyFileName = result.files.single.name;
      });
    }
  }

  Future<void> _pickGeneratedKeyFilePath() async {
    if (_usesManagedStorage) {
      setState(() => _generatedKeyFilePath = 'database.key');
      return;
    }

    String? savePath;
    try {
      savePath = await FilePicker.saveFile(
        dialogTitle: 'Select destination for generated key file',
        fileName: 'database.key',
      );
    } catch (_) {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select destination folder for generated key file',
      );
      if (directory != null && directory.isNotEmpty) {
        savePath = path.join(directory, 'database.key');
      }
    }
    if (savePath == null || savePath.isEmpty) return;
    setState(() => _generatedKeyFilePath = savePath);
  }

  PasswordStrengthCategory _strengthCategory(String password) {
    if (password.isEmpty) return PasswordStrengthCategory.weak;
    var charsetSize = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) charsetSize += 26;
    if (RegExp(r'[A-Z]').hasMatch(password)) charsetSize += 26;
    if (RegExp(r'[0-9]').hasMatch(password)) charsetSize += 10;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) charsetSize += 32;
    if (charsetSize == 0) return PasswordStrengthCategory.weak;
    final bits = password.length * (log(charsetSize) / log(2));
    if (bits < 40) return PasswordStrengthCategory.weak;
    if (bits < 60) return PasswordStrengthCategory.fair;
    if (bits < 80) return PasswordStrengthCategory.good;
    return PasswordStrengthCategory.strong;
  }

  void _advance(CreateDatabaseStep current) {
    switch (current) {
      case CreateDatabaseStep.nameAndStorage:
        context.read<DatabaseSelectionBloc>().add(
          AdvanceCreateDatabaseStep(
            fieldsNonEmpty: _databaseNameCtrl.text.trim().isNotEmpty,
          ),
        );
      case CreateDatabaseStep.masterPassword:
        final hasGeneratedKeyFile =
            _generateKeyFile && (_generatedKeyFilePath?.isNotEmpty ?? false);
        final nonEmpty =
            _passwordCtrl.text.isNotEmpty ||
            _keyFilePath != null ||
            hasGeneratedKeyFile;
        context.read<DatabaseSelectionBloc>().add(
          AdvanceCreateDatabaseStep(
            fieldsNonEmpty: nonEmpty,
            confirmationMatches: _confirmCtrl.text == _passwordCtrl.text,
          ),
        );
      case CreateDatabaseStep.optionalLocks:
        _submit();
    }
  }

  void _back(CreateDatabaseStep current) {
    if (current == CreateDatabaseStep.nameAndStorage) {
      Navigator.of(context).pop();
      return;
    }
    context.read<DatabaseSelectionBloc>().add(const GoBackCreateDatabaseStep());
  }

  void _submit() {
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
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.read<DatabaseSelectionBloc>().add(
          const CancelCreateDatabaseFlow(),
        );
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: colors.ground,
        body: SafeArea(
          child: BlocBuilder<DatabaseSelectionBloc, DatabaseSelectionState>(
            buildWhen: (previous, current) =>
                current is DatabaseSelectionCreateStep,
            builder: (context, state) {
              final step = state is DatabaseSelectionCreateStep
                  ? state.step
                  : CreateDatabaseStep.nameAndStorage;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CreateHeader(step: step, onBack: () => _back(step)),
                    const SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        child: switch (step) {
                          CreateDatabaseStep.nameAndStorage => _NameStep(
                            controller: _databaseNameCtrl,
                          ),
                          CreateDatabaseStep.masterPassword => _PasswordStep(
                            passwordCtrl: _passwordCtrl,
                            confirmCtrl: _confirmCtrl,
                            passwordVisible: _passwordVisible,
                            confirmVisible: _confirmVisible,
                            onTogglePassword: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                            onToggleConfirm: () => setState(
                              () => _confirmVisible = !_confirmVisible,
                            ),
                            strengthCategoryOf: _strengthCategory,
                          ),
                          CreateDatabaseStep.optionalLocks => _LocksStep(
                            biometricProtectionEnabled:
                                _biometricProtectionEnabled,
                            onBiometricChanged: (value) => setState(
                              () => _biometricProtectionEnabled = value,
                            ),
                            generateKeyFile: _generateKeyFile,
                            onGenerateKeyFileChanged: (value) => setState(() {
                              _generateKeyFile = value;
                              _keyFilePath = null;
                              _keyFileName = null;
                              if (!value) _generatedKeyFilePath = null;
                            }),
                            keyFilePath: _keyFilePath,
                            keyFileName: _keyFileName,
                            generatedKeyFilePath: _generatedKeyFilePath,
                            usesManagedStorage: _usesManagedStorage,
                            onPickKeyFile: _pickKeyFile,
                            onClearKeyFile: () => setState(() {
                              _keyFilePath = null;
                              _keyFileName = null;
                            }),
                            onPickGeneratedKeyFilePath:
                                _pickGeneratedKeyFilePath,
                            onClearGeneratedKeyFilePath: () =>
                                setState(() => _generatedKeyFilePath = null),
                          ),
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    KvPillButton(
                      label: step == CreateDatabaseStep.optionalLocks
                          ? 'Create'
                          : 'Continue',
                      onPressed: () => _advance(step),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CreateHeader extends StatelessWidget {
  const _CreateHeader({required this.step, required this.onBack});

  final CreateDatabaseStep step;
  final VoidCallback onBack;

  static const _stepLabels = {
    CreateDatabaseStep.nameAndStorage: 'Step 1 of 3',
    CreateDatabaseStep.masterPassword: 'Step 2 of 3',
    CreateDatabaseStep.optionalLocks: 'Step 3 of 3',
  };

  static const _stepTitles = {
    CreateDatabaseStep.nameAndStorage: 'Name your database',
    CreateDatabaseStep.masterPassword: 'Set a master password',
    CreateDatabaseStep.optionalLocks: 'Optional locks',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final index = CreateDatabaseStep.values.indexOf(step);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(AppIcons.back),
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Row(
                children: List.generate(3, (i) {
                  final done = i <= index;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                      decoration: BoxDecoration(
                        color: done ? colors.actionEmphasis : colors.canvas,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _stepLabels[step]!,
          style: AppTextStyles.labelUpper.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          _stepTitles[step]!,
          style: AppTextStyles.screenTitle.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

class _NameStep extends StatefulWidget {
  const _NameStep({required this.controller});

  final TextEditingController controller;

  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<_NameStep> {
  String? _error;

  String? _validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Enter a database file name.';
    }
    if (trimmed.contains(RegExp(r'[\\/:*?"<>|]'))) {
      return 'Invalid characters in file name.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          onChanged: (value) => setState(() => _error = _validate(value)),
          decoration: InputDecoration(
            labelText: 'Database file name',
            prefixIcon: const Icon(AppIcons.file),
            errorText: _error,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'KDBX Vault Manager app storage',
          style: AppTextStyles.secondary.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose the database file name and security options. On native platforms, the database and generated key file are saved in app internal storage, so export manual backups regularly.',
          style: AppTextStyles.body.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.passwordVisible,
    required this.confirmVisible,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.strengthCategoryOf,
  });

  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool passwordVisible;
  final bool confirmVisible;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final PasswordStrengthCategory Function(String) strengthCategoryOf;

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final category = strengthCategoryOf(passwordCtrl.text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: passwordCtrl,
              obscureText: !passwordVisible,
              onChanged: (_) => setLocalState(() {}),
              decoration: InputDecoration(
                labelText: 'Master Password',
                prefixIcon: const Icon(AppIcons.lock),
                suffixIcon: IconButton(
                  icon: Icon(passwordVisible ? AppIcons.eyeOff : AppIcons.eye),
                  onPressed: onTogglePassword,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _StrengthMeter(category: category),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final colors = Theme.of(context).extension<KeyVaultColors>()!;
                return Text(
                  'Please enter a password or choose a Key File.',
                  style: AppTextStyles.secondary.copyWith(
                    color: colors.textSecondary,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: confirmCtrl,
              obscureText: !confirmVisible,
              onChanged: (_) => setLocalState(() {}),
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: const Icon(AppIcons.lock),
                suffixIcon: IconButton(
                  icon: Icon(confirmVisible ? AppIcons.eyeOff : AppIcons.eye),
                  onPressed: onToggleConfirm,
                ),
                errorText: confirmCtrl.text.isNotEmpty &&
                        confirmCtrl.text != passwordCtrl.text
                    ? 'Passwords do not match.'
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.category});

  final PasswordStrengthCategory category;

  static const _labels = {
    PasswordStrengthCategory.weak: 'Weak',
    PasswordStrengthCategory.fair: 'Fair',
    PasswordStrengthCategory.good: 'Good',
    PasswordStrengthCategory.strong: 'Strong',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final activeCount = PasswordStrengthCategory.values.indexOf(category) + 1;
    return Row(
      children: [
        ...List.generate(4, (i) {
          final active = i < activeCount;
          return Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: i == 3 ? 8 : 8),
              decoration: BoxDecoration(
                color: active ? colors.actionEmphasis : colors.canvas,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }),
        Text(
          _labels[category]!,
          style: AppTextStyles.secondary.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _LocksStep extends StatelessWidget {
  const _LocksStep({
    required this.biometricProtectionEnabled,
    required this.onBiometricChanged,
    required this.generateKeyFile,
    required this.onGenerateKeyFileChanged,
    required this.keyFilePath,
    required this.keyFileName,
    required this.generatedKeyFilePath,
    required this.usesManagedStorage,
    required this.onPickKeyFile,
    required this.onClearKeyFile,
    required this.onPickGeneratedKeyFilePath,
    required this.onClearGeneratedKeyFilePath,
  });

  final bool biometricProtectionEnabled;
  final ValueChanged<bool> onBiometricChanged;
  final bool generateKeyFile;
  final ValueChanged<bool> onGenerateKeyFileChanged;
  final String? keyFilePath;
  final String? keyFileName;
  final String? generatedKeyFilePath;
  final bool usesManagedStorage;
  final VoidCallback onPickKeyFile;
  final VoidCallback onClearKeyFile;
  final VoidCallback onPickGeneratedKeyFilePath;
  final VoidCallback onClearGeneratedKeyFilePath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable biometric protection'),
          subtitle: const Text(
            'If enabled, unlock requires biometric authentication when available.',
          ),
          value: biometricProtectionEnabled,
          onChanged: onBiometricChanged,
        ),
        const SizedBox(height: 8),
        Text('Key File (optional)', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Generate key file automatically'),
          subtitle: const Text(
            'On native platforms it will be saved in app internal storage.',
          ),
          value: generateKeyFile,
          onChanged: onGenerateKeyFileChanged,
        ),
        const SizedBox(height: 8),
        if (generateKeyFile)
          generatedKeyFilePath == null
              ? OutlinedButton.icon(
                  onPressed: onPickGeneratedKeyFilePath,
                  icon: const Icon(AppIcons.save),
                  label: Text(
                    usesManagedStorage
                        ? 'Prepare generated key file'
                        : 'Choose key file destination',
                  ),
                )
              : ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.fileKey),
                  title: Text(
                    usesManagedStorage
                        ? 'Generated key file will be saved in app internal storage'
                        : generatedKeyFilePath!,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Tooltip(
                    message: 'Remove generated key file path',
                    child: IconButton(
                      icon: const Icon(AppIcons.close),
                      onPressed: onClearGeneratedKeyFilePath,
                    ),
                  ),
                )
        else if (keyFilePath == null)
          OutlinedButton.icon(
            onPressed: onPickKeyFile,
            icon: const Icon(AppIcons.attachment),
            label: const Text('Select Key File'),
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.file),
            title: Text(keyFileName ?? keyFilePath!, overflow: TextOverflow.ellipsis),
            trailing: Tooltip(
              message: 'Remove key file',
              child: IconButton(
                icon: const Icon(AppIcons.close),
                onPressed: onClearKeyFile,
              ),
            ),
          ),
      ],
    );
  }
}

/// Existing typed route result — unchanged shape from the former dialog.
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
