import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/utils/mobile_file_storage.dart';
import '../../../../../injection_container.dart' as di;
import '../bloc/database_unlock/database_unlock_bloc.dart';
import '../bloc/database_unlock/database_unlock_event.dart';
import '../bloc/database_unlock/database_unlock_state.dart';
import '../../domain/usecases/set_biometric_protection_enabled_usecase.dart';
import 'coordinators/database_flow_coordinator.dart';
import '../utils/platform_utils.dart';

part 'database_unlock_widgets.part.dart';

class DatabaseUnlockScreen extends StatelessWidget {
  final String databasePath;
  final bool promptBiometricSetup;
  static const DatabaseFlowCoordinator _flowCoordinator =
      DatabaseFlowCoordinator();

  const DatabaseUnlockScreen({
    super.key,
    required this.databasePath,
    this.promptBiometricSetup = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<DatabaseUnlockBloc>(param1: databasePath)
            ..add(const InitializeDatabaseUnlock()),
      child: _DatabaseUnlockView(promptBiometricSetup: promptBiometricSetup),
    );
  }
}

class _DatabaseUnlockView extends StatefulWidget {
  const _DatabaseUnlockView({required this.promptBiometricSetup});

  final bool promptBiometricSetup;

  @override
  State<_DatabaseUnlockView> createState() => _DatabaseUnlockViewState();
}

class _DatabaseUnlockViewState extends State<_DatabaseUnlockView> {
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = false;
  bool _biometricPromptHandled = false;

  bool get _usesManagedStorage {
    if (kIsWeb) {
      return false;
    }
    return isMobilePlatform || defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: _usesManagedStorage,
    );
    if (!mounted || result == null) {
      return;
    }

    final selected = result.files.single;
    String? path = selected.path;
    if (_usesManagedStorage) {
      if (path != null && path.isNotEmpty) {
        path = await MobileFileStorage.copyFileToAppDirectory(
          sourcePath: path,
          fallbackFileName: selected.name,
          subdirectory: 'keys',
        );
      } else if (selected.bytes != null) {
        path = await MobileFileStorage.saveBytesToAppDirectory(
          bytes: selected.bytes!,
          fileName: selected.name,
          subdirectory: 'keys',
        );
      }
    }

    if (path == null || path.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    context.read<DatabaseUnlockBloc>().add(UpdateKeyFilePath(path));

    if (_usesManagedStorage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Key file imported to app internal storage.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Unlock Database')),
      body: Container(
        decoration: BoxDecoration(gradient: AppBackgrounds.gradient(context)),
        child: BlocConsumer<DatabaseUnlockBloc, DatabaseUnlockState>(
          listener: (context, state) {
            if (widget.promptBiometricSetup &&
                !_biometricPromptHandled &&
                !state.isLoading) {
              _biometricPromptHandled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                _showBiometricSetupPrompt();
              });
            }
            DatabaseUnlockScreen._flowCoordinator.onDatabaseUnlockState(
              context,
              state,
            );
          },
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(32, topInset + 24, 32, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: TweenAnimationBuilder<double>(
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0.98, end: 1),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Unlock this vault with password and optional key file. Biometric authentication is only required when enabled for this database.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            if (state.biometricAvailable &&
                                !state.biometricVerified)
                              FilledButton.icon(
                                onPressed: () {
                                  context.read<DatabaseUnlockBloc>().add(
                                    const RetryBiometricAuthentication(),
                                  );
                                },
                                icon: const Icon(AppIcons.fingerprint),
                                label: const Text(
                                  'Authenticate with Biometrics',
                                ),
                              ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: !_passwordVisible,
                              decoration: InputDecoration(
                                labelText:
                                    'Master Password (optional with key file)',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(AppIcons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _passwordVisible
                                        ? AppIcons.eyeOff
                                        : AppIcons.eye,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _passwordVisible = !_passwordVisible;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _KeyFileSelector(
                              keyFilePath: state.keyFilePath,
                              onPickKeyFile: _pickKeyFile,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () {
                                context.read<DatabaseUnlockBloc>().add(
                                  UnlockWithManualCredentials(
                                    password: _passwordCtrl.text,
                                    keyFilePath: state.keyFilePath,
                                  ),
                                );
                              },
                              child: const Text('Unlock Database'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showBiometricSetupPrompt() async {
    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enable biometric protection?'),
          content: const Text(
            'This database came from Google Drive. Do you want to require biometric authentication before unlock when available?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );

    if (shouldEnable == null || !mounted) {
      return;
    }

    await di.sl<SetBiometricProtectionEnabledUseCase>()(shouldEnable);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          shouldEnable
              ? 'Biometric protection enabled for this database.'
              : 'Biometric protection remains disabled for this database.',
        ),
      ),
    );

    if (shouldEnable) {
      context.read<DatabaseUnlockBloc>().add(const InitializeDatabaseUnlock());
    }
  }
}
