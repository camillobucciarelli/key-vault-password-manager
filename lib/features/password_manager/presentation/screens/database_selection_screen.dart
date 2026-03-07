import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/navigation/app_navigation.dart';
import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_icons.dart';
import '../bloc/database_selection/database_selection_bloc.dart';
import '../bloc/database_selection/database_selection_event.dart';
import '../bloc/database_selection/database_selection_state.dart';
import 'database_unlock_screen.dart';
import '../widgets/android_autofill_action.dart';
import '../widgets/create_database_dialog.dart';

class DatabaseSelectionScreen extends StatelessWidget {
  const DatabaseSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Select Database'),
        actions: const [AndroidAutofillAction()],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppBackgrounds.gradient(context)),
        child: BlocConsumer<DatabaseSelectionBloc, DatabaseSelectionState>(
          listener: (context, state) {
            if (state is DatabaseSelectionSuccess) {
              AppNavigation.pushFadeReplacement(
                context,
                DatabaseUnlockScreen(databasePath: state.path),
              );
            } else if (state is DatabaseSelectionError) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.message)));
            }
          },
          builder: (context, state) {
            if (state is DatabaseSelectionLoading ||
                state is DatabaseSelectionInitial) {
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
                        : const Duration(milliseconds: 300),
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
                          children: [
                            Icon(
                              AppIcons.lock,
                              size: 72,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'No database selected',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Please select an existing KDBX database or create a new one to continue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 32),
                            FilledButton.icon(
                              onPressed: () {
                                context.read<DatabaseSelectionBloc>().add(
                                  SelectExistingDatabase(),
                                );
                              },
                              icon: const Icon(AppIcons.folderOpen),
                              label: const Text('Open Existing Database'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final credentials =
                                    await showDialog<CreateDatabaseCredentials>(
                                      context: context,
                                      builder: (_) =>
                                          const CreateDatabaseDialog(),
                                    );
                                if (credentials != null && context.mounted) {
                                  context.read<DatabaseSelectionBloc>().add(
                                    CreateNewDatabase(
                                      password: credentials.password,
                                      keyFilePath: credentials.keyFilePath,
                                      generateKeyFile:
                                          credentials.generateKeyFile,
                                      generatedKeyFilePath:
                                          credentials.generatedKeyFilePath,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(AppIcons.add),
                              label: const Text('Create New Database'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
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
