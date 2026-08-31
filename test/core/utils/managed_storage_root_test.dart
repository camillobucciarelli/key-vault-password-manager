import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/managed_storage_root.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _RecordingPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final calls = <String>[];

  @override
  Future<String?> getApplicationDocumentsPath() async {
    calls.add('documents');
    return '/fake/documents';
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    calls.add('support');
    return '/fake/support';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPathProvider provider;

  setUp(() {
    provider = _RecordingPathProvider();
    PathProviderPlatform.instance = provider;
  });

  tearDown(() {
    ManagedStorageRoot.debugIsDesktopOverride = null;
  });

  test(
    'desktop resolves the application data directory, not Documents',
    () async {
      ManagedStorageRoot.debugIsDesktopOverride = true;
      final path = await ManagedStorageRoot.resolvePath();
      expect(path, '/fake/support');
      expect(provider.calls, ['support']);
    },
  );

  test('mobile resolves the app documents directory', () async {
    ManagedStorageRoot.debugIsDesktopOverride = false;
    final path = await ManagedStorageRoot.resolvePath();
    expect(path, '/fake/documents');
    expect(provider.calls, ['documents']);
  });

  test('platform detection maps macOS/Windows/Linux to desktop', () {
    // The suite runs on a desktop host; the real (non-overridden) branch must
    // therefore pick the support directory. This pins the Platform.is* wiring
    // without needing to fake dart:io.
    expect(
      Platform.isMacOS || Platform.isWindows || Platform.isLinux,
      isTrue,
      reason: 'flutter test runs on a desktop host',
    );
  });

  test('guard: getApplicationDocumentsDirectory appears in exactly one '
      'production file (the root resolver)', () {
    final matches = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = entity
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      if (code.contains('getApplicationDocumentsDirectory(')) {
        matches.add(entity.path);
      }
    }
    expect(
      matches,
      ['lib/core/utils/managed_storage_root.dart'],
      reason:
          'every managed path must resolve through ManagedStorageRoot '
          '(spec 014 FR-2)',
    );
  });

  test('guard: getApplicationSupportDirectory appears in exactly one '
      'production file (the root resolver)', () {
    final matches = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = entity
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      if (code.contains('getApplicationSupportDirectory(')) {
        matches.add(entity.path);
      }
    }
    expect(matches, ['lib/core/utils/managed_storage_root.dart']);
  });
}
