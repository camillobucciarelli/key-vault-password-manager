import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/di/core_di.dart';
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
}
