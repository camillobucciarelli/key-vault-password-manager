import 'package:flutter/material.dart';

import '../../../../../../core/navigation/app_navigation.dart';
import '../../bloc/database_selection/database_selection_state.dart';
import '../../bloc/database_unlock/database_unlock_state.dart';
import '../database_unlock_screen.dart';
import '../vault_screen.dart';

class DatabaseFlowCoordinator {
  const DatabaseFlowCoordinator();

  void onDatabaseSelectionState(
    BuildContext context,
    DatabaseSelectionState state,
  ) {
    if (state is DatabaseSelectionSuccess) {
      if (state.userMessage != null && state.userMessage!.isNotEmpty) {
        _showSnackBar(context, state.userMessage!);
      }
      AppNavigation.pushFadeReplacement(
        context,
        DatabaseUnlockScreen(
          databasePath: state.path,
          promptBiometricSetup: state.promptBiometricSetup,
        ),
      );
      return;
    }

    if (state is DatabaseSelectionError) {
      _showSnackBar(context, state.message);
    }

    if (state is DatabaseSelectionInfo) {
      _showSnackBar(context, state.message);
    }
  }

  void onDatabaseUnlockState(BuildContext context, DatabaseUnlockState state) {
    if (state.unlocked) {
      AppNavigation.pushFadeReplacement(
        context,
        VaultScreen(databasePath: state.databasePath),
      );
      return;
    }

    final errorMessage = state.errorMessage;
    if (errorMessage != null && errorMessage.isNotEmpty) {
      _showSnackBar(context, errorMessage);
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
