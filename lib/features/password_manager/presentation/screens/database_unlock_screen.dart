import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../injection_container.dart' as di;
import '../bloc/database_unlock/database_unlock_bloc.dart';
import '../bloc/database_unlock/database_unlock_event.dart';
import '../bloc/database_unlock/database_unlock_state.dart';
import 'vault_screen.dart';

class DatabaseUnlockScreen extends StatelessWidget {
  final String databasePath;

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
    final result = await FilePicker.platform.pickFiles();
    if (!mounted || result == null || result.files.single.path == null) {
      return;
    }
    context.read<DatabaseUnlockBloc>().add(
      UpdateKeyFilePath(result.files.single.path),
    );
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
            if (state.unlocked) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => VaultScreen(databasePath: state.databasePath),
                ),
              );
            }

            if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            }
          },
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, topInset + 24, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
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
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Authenticate with Biometrics'),
                            ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: !_passwordVisible,
                            decoration: InputDecoration(
                              labelText:
                                  'Master Password (optional with key file)',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
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
                              icon: const Icon(Icons.attach_file),
                              label: const Text('Select Key File'),
                            )
                          else
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.key_outlined),
                              title: Text(
                                state.keyFilePath!,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  IconButton(
                                    tooltip: 'Change key file',
                                    onPressed: _pickKeyFile,
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove key file',
                                    onPressed: () {
                                      context.read<DatabaseUnlockBloc>().add(
                                        const UpdateKeyFilePath(null),
                                      );
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
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
            );
          },
        ),
      ),
    );
  }
}
