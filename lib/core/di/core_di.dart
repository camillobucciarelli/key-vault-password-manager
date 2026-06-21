import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> registerCoreDependencies(
  GetIt sl, {
  required SharedPreferences sharedPreferences,
}) async {
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => const FlutterSecureStorage());
  sl.registerLazySingleton(() => LocalAuthentication());
  sl.registerLazySingleton<http.Client>(() => http.Client());
}
