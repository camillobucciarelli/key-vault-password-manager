import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/navigation/app_navigation.dart';
import '../../../../../core/responsive/breakpoints.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_motion.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/keyvault_colors.dart';
import '../../../../../core/widgets/kv_bottom_sheet.dart';
import '../../../../../core/widgets/kv_pill_button.dart';
import '../../../../../injection_container.dart' as di;
import '../bloc/database_unlock/database_unlock_bloc.dart';
import '../bloc/database_unlock/database_unlock_event.dart';
import '../bloc/database_unlock/database_unlock_state.dart';
import '../coordinators/database_session_coordinator.dart';
import '../../domain/errors/database_access_failure.dart';
import '../widgets/database/face_id_prompt_sheet.dart';
import '../widgets/internal_key_file_manager_sheet.dart';
import '../utils/platform_utils.dart';
import 'database_selection_screen.dart';
import 'vault_screen.dart';

part 'database_unlock_widgets.part.dart';

class DatabaseUnlockScreen extends StatelessWidget {
  final String databasePath;
  final bool promptBiometricSetup;

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

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    if (isManagedStoragePlatform) {
      final bloc = context.read<DatabaseUnlockBloc>();
      final currentKeyFilePath = bloc.state.keyFilePath;
      final protectedPaths = await di
          .sl<DatabaseSessionCoordinator>()
          .getProtectedKeyFilePaths();
      if (!mounted) {
        return;
      }
      final result = await showInternalKeyFileManagerSheet(
        context,
        initiallySelectedPath: currentKeyFilePath,
        protectedPaths: {...protectedPaths, ?currentKeyFilePath},
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
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return Scaffold(
      backgroundColor: colors.ground,
      body: BlocConsumer<DatabaseUnlockBloc, DatabaseUnlockState>(
        listener: (context, state) {
          if (widget.promptBiometricSetup &&
              !_biometricPromptHandled &&
              state.phase == UnlockPhase.ready) {
            _biometricPromptHandled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              _showBiometricSetupPrompt();
            });
          }
          if (state.unlocked) {
            AppNavigation.pushFadeReplacement(
              context,
              VaultScreen(databasePath: state.databasePath),
            );
          }
        },
        builder: (context, state) {
          switch (state.phase) {
            case UnlockPhase.initializing:
              return const _UnlockLoading();
            case UnlockPhase.biometricGate:
              return _BiometricGate(
                onRetry: () => context.read<DatabaseUnlockBloc>().add(
                  const RetryBiometricAuthentication(),
                ),
                onUseMasterPassword: () => context
                    .read<DatabaseUnlockBloc>()
                    .add(const RequestManualUnlockFallback()),
                errorMessage: state.errorMessage,
              );
            case UnlockPhase.decrypting:
              return _DecryptingView(basename: p.basename(state.databasePath));
            case UnlockPhase.failure:
              return _UnlockFailureView(
                state: state,
                onBack: _goToDatabaseSelection,
              );
            case UnlockPhase.unlocked:
              return const _UnlockLoading();
            case UnlockPhase.ready:
              final hasPassword = _passwordCtrl.text.isNotEmpty;
              final hasKeyFile =
                  state.keyFilePath != null &&
                  state.keyFilePath!.trim().isNotEmpty;
              final canSubmit = hasPassword || hasKeyFile;
              return _UnlockReadyForm(
                state: state,
                passwordCtrl: _passwordCtrl,
                passwordVisible: _passwordVisible,
                onPasswordChanged: () => setState(() {}),
                onTogglePasswordVisible: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                onPickKeyFile: _pickKeyFile,
                onClearKeyFile: () => context.read<DatabaseUnlockBloc>().add(
                  const UpdateKeyFilePath(null),
                ),
                onFaceIdRetry: () => context.read<DatabaseUnlockBloc>().add(
                  const RetryBiometricAuthentication(),
                ),
                onSubmit: canSubmit
                    ? () {
                        context.read<DatabaseUnlockBloc>().add(
                          UnlockWithManualCredentials(
                            password: _passwordCtrl.text,
                            keyFilePath: state.keyFilePath,
                          ),
                        );
                      }
                    : null,
                onBack: _goToDatabaseSelection,
              );
          }
        },
      ),
    );
  }

  Future<void> _goToDatabaseSelection() async {
    final hasPasswordDraft = _passwordCtrl.text.isNotEmpty;
    final keyFilePath = context.read<DatabaseUnlockBloc>().state.keyFilePath;
    final hasKeyFileDraft =
        keyFilePath != null && keyFilePath.trim().isNotEmpty;

    if (hasPasswordDraft || hasKeyFileDraft) {
      final shouldLeave = await KvBottomSheet.show<bool>(
        context: context,
        barrierAlpha: 0.3,
        builder: (sheetContext) {
          final sheetColors = Theme.of(
            sheetContext,
          ).extension<KeyVaultColors>()!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Return to database list?',
                  style: AppTextStyles.sheetTitle.copyWith(
                    color: sheetColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Any unlock credentials entered on this screen will be discarded.',
                  style: AppTextStyles.body.copyWith(
                    color: sheetColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('Stay here'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: KvPillButton(
                        compact: true,
                        label: 'Return',
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
    final basename = p.basename(
      context.read<DatabaseUnlockBloc>().state.databasePath,
    );
    final shouldEnable = await showFaceIdPromptSheet(
      context,
      basename: basename,
    );

    if (shouldEnable == null || !mounted) {
      return;
    }

    await di.sl<DatabaseSessionCoordinator>().updateBiometricProtection(
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
