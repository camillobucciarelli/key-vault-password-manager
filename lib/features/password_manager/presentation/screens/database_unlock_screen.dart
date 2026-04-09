import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/navigation/app_navigation.dart';
import '../../../../../injection_container.dart' as di;
import '../bloc/database_unlock/database_unlock_bloc.dart';
import '../bloc/database_unlock/database_unlock_event.dart';
import '../bloc/database_unlock/database_unlock_state.dart';
import '../coordinators/database_session_coordinator.dart';
import 'coordinators/database_flow_coordinator.dart';
import 'database_selection_screen.dart';
import '../widgets/internal_key_file_manager_dialog.dart';
import '../widgets/styled_info_container.dart';

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
    return true;
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    if (_usesManagedStorage) {
      final bloc = context.read<DatabaseUnlockBloc>();
      final currentKeyFilePath = bloc.state.keyFilePath;
      final result = await showInternalKeyFileManagerDialog(
        context,
        initiallySelectedPath: currentKeyFilePath,
      );
      if (!mounted || result == null) {
        return;
      }

      if (result.selectedPath != null) {
        bloc.add(UpdateKeyFilePath(result.selectedPath));
        return;
      }

      if (result.currentSelectionDeleted &&
          currentKeyFilePath != null &&
          currentKeyFilePath.trim().isNotEmpty) {
        bloc.add(const UpdateKeyFilePath(null));
      }
      return;
    }

    final result = await FilePicker.pickFiles(withData: false);
    if (!mounted || result == null) {
      return;
    }

    final selected = result.files.single;
    String? path = selected.path;
    if (path == null || path.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    context.read<DatabaseUnlockBloc>().add(UpdateKeyFilePath(path));
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
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

            final hasPassword = _passwordCtrl.text.trim().isNotEmpty;
            final hasKeyFile =
                state.keyFilePath != null &&
                state.keyFilePath!.trim().isNotEmpty;
            final requiresBiometricGate =
                state.biometricAvailable && !state.biometricVerified;
            final canUnlockManually =
                (hasPassword || hasKeyFile) && !requiresBiometricGate;

            final viewportWidth = MediaQuery.sizeOf(context).width;
            final horizontalPadding = viewportWidth < 420
                ? 16.0
                : (viewportWidth - 600) * 0.5;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  topInset + 24,
                  horizontalPadding,
                  32,
                ),
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
                            'Unlock vault',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Unlock active vault by choosing at least one credential method.',
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You can use the master password, a key file, or both.',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Step 1 of 2 - Verify identity',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          if (requiresBiometricGate) ...[
                            FilledButton.icon(
                              onPressed: () {
                                context.read<DatabaseUnlockBloc>().add(
                                  const RetryBiometricAuthentication(),
                                );
                              },
                              icon: const Icon(AppIcons.fingerprint),
                              label: const Text('Authenticate with biometrics'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Complete biometric verification before manual unlock.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ] else
                            StyledInfoContainer(
                              child: Text(
                                state.biometricAvailable
                                    ? 'Biometric check completed.'
                                    : 'Biometric check not required for this vault.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          const SizedBox(height: 20),
                          Text(
                            'Step 2 of 2 - Provide unlock credentials',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: !_passwordVisible,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Master password',
                              helperText: hasKeyFile
                                  ? 'Optional while a key file is selected.'
                                  : 'Required if no key file is selected.',
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
                            onClearKeyFile: () {
                              context.read<DatabaseUnlockBloc>().add(
                                const UpdateKeyFilePath(null),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          StyledInfoContainer(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Ready to unlock with: '
                              '${hasPassword ? 'master password' : ''}'
                              '${hasPassword && hasKeyFile ? ' + ' : ''}'
                              '${hasKeyFile ? 'key file' : ''}'
                              '${!hasPassword && !hasKeyFile ? 'no credentials selected' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: canUnlockManually
                                ? () {
                                    context.read<DatabaseUnlockBloc>().add(
                                      UnlockWithManualCredentials(
                                        password: _passwordCtrl.text,
                                        keyFilePath: state.keyFilePath,
                                      ),
                                    );
                                  }
                                : null,
                            child: const Text('Unlock vault'),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _goToDatabaseSelection,
                            icon: const Icon(AppIcons.back, size: 18),
                            label: const Text('Back to database list'),
                          ),
                          if (!hasPassword && !hasKeyFile) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Select a key file or enter your master password to continue.',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ] else if (requiresBiometricGate) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Biometric verification is still required before unlocking.',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
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

  Future<void> _goToDatabaseSelection() async {
    final hasPasswordDraft = _passwordCtrl.text.trim().isNotEmpty;
    final keyFilePath = context.read<DatabaseUnlockBloc>().state.keyFilePath;
    final hasKeyFileDraft =
        keyFilePath != null && keyFilePath.trim().isNotEmpty;

    if (hasPasswordDraft || hasKeyFileDraft) {
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Return to database list?'),
            content: const Text(
              'Any unlock credentials entered on this screen will be discarded.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Stay here'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Return'),
              ),
            ],
          );
        },
      );

      if (shouldLeave != true || !mounted) {
        return;
      }
    }

    await AppNavigation.pushFadeReplacement(
      context,
      const DatabaseSelectionScreen(),
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

    await di.sl<DatabaseSessionCoordinatorContract>().updateBiometricProtection(
      databasePath: context.read<DatabaseUnlockBloc>().state.databasePath,
      enabled: shouldEnable,
    );
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
