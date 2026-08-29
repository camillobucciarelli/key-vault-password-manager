part of '../vault_screen.dart';

// spec-019 FR-013 / C-03-12: `_SyncStatusStrip` — the database status card
// that sat above the records list at every width — was deleted here. Its
// primary sync button and its `Settings` overflow moved verbatim into
// `_VaultDatabaseActions` (FR-015); the sheet behind the overflow,
// `_VaultSettingsSheet`, is untouched, so every action it carried keeps both
// its wording and its interaction count.

class _SyncStripMenuButton extends StatelessWidget {
  const _SyncStripMenuButton({
    required this.state,
    required this.canConfigureAndroidAutofill,
    required this.canConfigureBrowserAutofill,
    required this.onOpenRecycleBin,
    required this.onOpenDuplicates,
    required this.onChangeDatabase,
  });

  final VaultState state;
  final bool canConfigureAndroidAutofill;
  final bool canConfigureBrowserAutofill;
  final VoidCallback onOpenRecycleBin;
  final VoidCallback onOpenDuplicates;
  final Future<void> Function() onChangeDatabase;

  // spec-005: bodies moved to top-level `_exportDatabaseBackup` /
  // `_exportKeyFileBackup` in vault_shared.part.dart so the new Backups
  // destination (T17) can call the same code — behaviour unchanged (FR-8:
  // "the three existing export actions, unchanged in behaviour").
  Future<void> _exportCurrentDatabaseBackup(BuildContext context) =>
      _exportDatabaseBackup(context, state.databasePath);

  Future<void> _exportCurrentKeyFile(BuildContext context) =>
      _exportKeyFileBackup(context);

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select((ThemeCubit cubit) => cubit.state);

    Future<void> handleSelection(String value) async {
      switch (value) {
        case 'connect':
          context.read<VaultBloc>().add(const ConnectGoogleDrive());
          break;
        case 'disconnect':
          context.read<VaultBloc>().add(const DisconnectGoogleDrive());
          break;
        case 'link':
          await _startDriveLinkFlow(context);
          break;
        case 'toggleAutoSync':
          context.read<VaultBloc>().add(
            ToggleCurrentDatabaseAutoSync(!state.autoSyncEnabled),
          );
          break;
        case 'recycleBin':
          onOpenRecycleBin();
          break;
        case 'manageDuplicates':
          onOpenDuplicates();
          break;
        case 'changeDatabase':
          await onChangeDatabase();
          break;
        case 'importCsv':
          await _startCsvImportFlow(context);
          break;
        case 'lockVault':
          final databasePath = state.databasePath;
          if (databasePath.trim().isNotEmpty) {
            await di.sl<VaultSessionCoordinator>().lockVault(
              currentDatabasePath: databasePath,
            );
            if (!context.mounted) {
              return;
            }
            await AppNavigation.pushFadeReplacement(
              context,
              DatabaseUnlockScreen(databasePath: databasePath),
            );
          }
          break;
        case 'exportDatabaseBackup':
          await _exportCurrentDatabaseBackup(context);
          break;
        case 'exportKeyFile':
          await _exportCurrentKeyFile(context);
          break;
        case 'androidAutofill':
          await _openAndroidAutofillSettings(context);
          break;
        case 'themeSystem':
          context.read<ThemeCubit>().setTheme(ThemeMode.system);
          break;
        case 'themeLight':
          context.read<ThemeCubit>().setTheme(ThemeMode.light);
          break;
        case 'themeDark':
          context.read<ThemeCubit>().setTheme(ThemeMode.dark);
          break;
        case 'browserSetup':
          await _openBrowserAutofillSettings(context);
          break;
        case 'databaseSettings':
          await _showDatabaseSettings(context, state);
          break;
        case 'passwordGenerator':
          await _showPasswordGeneratorSheet(context, standalone: true);
          break;
      }
    }

    return Tooltip(
      message: 'Settings',
      ignorePointer: true,
      child: IconButton(
        style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheetContext) {
              Future<void> closeAndSelect(String value) async {
                Navigator.of(sheetContext).pop();
                await handleSelection(value);
              }

              return _VaultSettingsSheet(
                state: state,
                themeMode: themeMode,
                canConfigureAndroidAutofill: canConfigureAndroidAutofill,
                canConfigureBrowserAutofill: canConfigureBrowserAutofill,
                onSelect: closeAndSelect,
              );
            },
          );
        },
        icon: _DuplicateBadge(
          count: state.duplicateGroupCount,
          child: const _SyncStripActionIcon(icon: AppIcons.more),
        ),
      ),
    );
  }
}
