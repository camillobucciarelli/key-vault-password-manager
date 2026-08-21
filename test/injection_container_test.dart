import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/injection_container.dart' as di;
import 'package:shared_preferences/shared_preferences.dart';

/// spec-011 FR-6 wiring test: the startup migration must run from `di.init()`
/// itself, before any widget exists. Removing the call in `init()` makes this
/// test fail — it kills the "delete the migration call" mutation that the
/// data-source unit tests cannot see.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  final deletedKeys = <String>[];

  setUp(() {
    deletedKeys.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'delete') {
            final arguments = call.arguments as Map<Object?, Object?>;
            deletedKeys.add(arguments['key']! as String);
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    await di.sl.reset();
  });

  test('di.init() deletes the legacy global master password entry', () async {
    await di.init();

    expect(deletedKeys, contains(SecureDataSourceImpl.legacyMasterPasswordKey));
  });
}
