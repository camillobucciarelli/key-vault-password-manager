import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/di/core_di.dart';
import 'features/password_manager/data/datasources/secure_data_source.dart';
import 'features/password_manager/di/password_manager_data_di.dart';
import 'features/password_manager/di/password_manager_domain_di.dart';
import 'features/password_manager/di/password_manager_presentation_di.dart';

final sl = GetIt.instance;

Future<void> init() async {
  final sharedPreferences = await SharedPreferences.getInstance();

  await registerCoreDependencies(sl, sharedPreferences: sharedPreferences);
  registerPasswordManagerDataDependencies(sl);
  registerPasswordManagerDomainDependencies(sl);
  registerPasswordManagerPresentationDependencies(sl);

  // spec-011 FR-6: one-time migration. The pre-spec global 'MASTER_PASSWORD'
  // entry cannot be reliably attributed to a database, so it is deleted
  // unconditionally on first run after this change. Users with biometric
  // protection re-establish a per-database entry at their next manual unlock.
  // Best-effort: a migration failure must never block startup.
  try {
    await sl<SecureDataSource>().clearLegacyGlobalMasterPassword();
  } catch (_) {}
}
