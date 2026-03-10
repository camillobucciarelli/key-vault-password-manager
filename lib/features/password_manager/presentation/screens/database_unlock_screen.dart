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
import 'coordinators/database_flow_coordinator.dart';

class DatabaseUnlockScreen extends StatelessWidget {
  final String databasePath;
  static const DatabaseFlowCoordinator _flowCoordinator =
      DatabaseFlowCoordinator();

  const DatabaseUnlockScreen({super.key, required this.databasePath});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<DatabaseUnlockBloc>(param1: databasePath)
            ..add(const InitializeDatabaseUnlock()),
      child: const _DatabaseUnlockView(),
    );
  }
}

class _DatabaseUnlockView extends StatefulWidget {
  const _DatabaseUnlockView();

  @override
  State<_DatabaseUnlockView> createState() => _DatabaseUnlockViewState();
}

class _DatabaseUnlockViewState extends State<_DatabaseUnlockView> {
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: _isMobilePlatform,
    );
    if (!mounted || result == null) {
      return;
    }

    final selected = result.files.single;
    String? path = selected.path;
    if (_isMobilePlatform) {
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

    if (_isMobilePlatform) {
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
                              'Access to this app is protected by biometric authentication.',
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
                            if (state.keyFilePath == null)
                              OutlinedButton.icon(
                                onPressed: _pickKeyFile,
                                icon: const Icon(AppIcons.attachment),
                                label: const Text('Select Key File'),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(AppIcons.fileKey, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _isMobilePlatform
                                            ? p.basename(state.keyFilePath!)
                                            : state.keyFilePath!,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_isMobilePlatform)
                                      Wrap(
                                        spacing: 2,
                                        children: [
                                          IconButton(
                                            tooltip: 'Change key file',
                                            onPressed: _pickKeyFile,
                                            icon: const Icon(AppIcons.edit),
                                          ),
                                          IconButton(
                                            tooltip: 'Remove key file',
                                            onPressed: () {
                                              context
                                                  .read<DatabaseUnlockBloc>()
                                                  .add(
                                                    const UpdateKeyFilePath(
                                                      null,
                                                    ),
                                                  );
                                            },
                                            icon: const Icon(AppIcons.close),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      IconButton(
                                        tooltip: 'Change key file',
                                        onPressed: _pickKeyFile,
                                        icon: const Icon(AppIcons.edit),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove key file',
                                        onPressed: () {
                                          context
                                              .read<DatabaseUnlockBloc>()
                                              .add(
                                                const UpdateKeyFilePath(null),
                                              );
                                        },
                                        icon: const Icon(AppIcons.close),
                                      ),
                                    ],
                                  ],
                                ),
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
}

bool get _isMobilePlatform {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}
