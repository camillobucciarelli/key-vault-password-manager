// Shared widget-test harness for spec-002 navigation-shell tests.
//
// `VaultScreen` resolves several collaborators through the global GetIt
// (`di.sl`) container. This file registers minimal fakes so [VaultScreen]
// can be pumped in a widget test without touching platform channels, real
// kdbx I/O, or the full production DI graph. Callers MUST call
// `resetVaultShellTestDi()` in `tearDown` to avoid leaking registrations
// between tests.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:password_manager/core/theme/app_theme.dart';
import 'package:password_manager/core/theme/theme_cubit.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/vault_csv_import_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_duplicate_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/otpauth_deep_link_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/vault_session_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/screens/vault_screen.dart';
import 'package:password_manager/injection_container.dart' as di;
import 'package:shared_preferences/shared_preferences.dart';

const kTestDatabasePath = '/tmp/vault_shell_test.kdbx';

/// Registers fakes into the global `di.sl` GetIt instance and returns a
/// ready-to-pump `VaultScreen` wrapped in the app theme + ThemeCubit it
/// needs. Uses an empty vault snapshot (no entries/groups) so the shell
/// renders deterministically for geometry/golden assertions.
Future<Widget> pumpableVaultShell({
  String databasePath = kTestDatabasePath,
  ThemeMode? themeMode,
}) async {
  SharedPreferences.setMockInitialValues({});
  final sharedPreferences = await SharedPreferences.getInstance();

  di.sl.registerLazySingleton<OtpAuthDeepLinkCoordinator>(
    () => OtpAuthDeepLinkCoordinator(),
  );
  di.sl.registerLazySingleton<VaultSessionCoordinator>(
    () => _FakeVaultSessionCoordinator(),
  );
  di.sl.registerFactoryParam<VaultBloc, String, void>(
    (path, _) => VaultBloc(
      databasePath: path,
      getSelectedKeyFilePath: () async => null,
      secureDataSource: _FakeSecureDataSource(),
      vaultKdbxService: _FakeVaultKdbxService(),
      vaultCsvImportService: VaultCsvImportService(),
      vaultDuplicateService: VaultDuplicateService(),
      databaseSyncRepository: _FakeDatabaseSyncRepository(),
    ),
  );

  return BlocProvider<ThemeCubit>(
    create: (_) => ThemeCubit(sharedPreferences),
    child: Builder(
      builder: (context) {
        final resolvedThemeMode =
            themeMode ?? context.watch<ThemeCubit>().state;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en', 'US'),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: resolvedThemeMode,
          home: VaultScreen(databasePath: databasePath),
        );
      },
    ),
  );
}

/// Undo the registrations made by [pumpableVaultShell]. Call from `tearDown`.
Future<void> resetVaultShellTestDi() => di.sl.reset();

class _FakeSecureDataSource implements SecureDataSource {
  @override
  Future<String?> getMasterPassword() async => '';

  @override
  Future<void> saveMasterPassword(String password) async {}

  @override
  Future<void> clearMasterPassword() async {}
}

class _FakeVaultKdbxService implements VaultKdbxService {
  @override
  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async => const VaultSnapshot(
    rootGroupId: 'root',
    currentGroupId: 'root',
    groups: [],
    entries: [],
    allEntries: [],
  );

  @override
  Future<List<VaultEntry>> loadRecycleBinEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseSyncRepository implements DatabaseSyncRepository {
  @override
  Future<bool> isConnected() async => false;

  @override
  Future<DatabaseSyncMapping?> getMapping(String path) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVaultSessionCoordinator implements VaultSessionCoordinator {
  @override
  Future<String?> getSelectedKeyFilePath() async => null;

  @override
  Future<String?> getPersistedKeyFilePath(String databasePath) async => null;

  @override
  Future<Set<String>> getProtectedKeyFilePaths() async => const {};

  @override
  Future<void> changeDatabase({required String currentDatabasePath}) async {}

  @override
  Future<void> lockVault({required String currentDatabasePath}) async {}

  @override
  Future<bool> getBiometricProtectionEnabledForPath({
    required String databasePath,
  }) async => false;

  @override
  Future<int?> getInactivityLockTimeoutForPath({
    required String databasePath,
  }) async => null;

  @override
  Future<DatabaseSettingsUpdateResult> updateDatabaseSettings(
    DatabaseSettingsUpdateRequest request,
  ) => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
