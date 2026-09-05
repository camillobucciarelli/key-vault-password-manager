import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/mobile_file_storage.dart';
import 'package:password_manager/features/password_manager/data/datasources/key_file_names_data_source.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'in_memory_secure_data_source.dart';

/// spec 014 FR-3: a managed key file rests under an opaque name, so the name
/// the user knows it by is recorded at write time and shown at list time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InMemorySecureDataSource secure;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('key_file_names_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    secure = InMemorySecureDataSource();
    MobileFileStorage.keyFileNames = KeyFileNamesDataSource(
      secureDataSource: secure,
    );
  });

  tearDown(() async {
    MobileFileStorage.keyFileNames = null;
    await tempDir.delete(recursive: true);
  });

  test('a written key file lists under the name it was imported as, and the '
      'name file is encrypted metadata', () async {
    final path = await MobileFileStorage.saveBytesToAppDirectory(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'personal.key',
      subdirectory: 'keys',
    );

    expect(MobileFileStorage.isOpaqueFileName(p.basename(path)), isTrue);
    expect(await MobileFileStorage.keyFileDisplayName(path), 'personal.key');
    final listed = await MobileFileStorage.listFilesInAppDirectory(
      subdirectory: 'keys',
    );
    expect(listed.single.name, 'personal.key');
    expect(listed.single.path, path);

    final namesFile = File(
      p.join(tempDir.path, 'metadata', 'key_file_names.json'),
    );
    expect(namesFile.existsSync(), isTrue);
    expect(
      String.fromCharCodes(namesFile.readAsBytesSync()),
      isNot(contains('personal.key')),
      reason: 'the name must not be readable from the directory (FR-3/FR-4)',
    );
  });

  test('deleting the key file forgets its name', () async {
    final path = await MobileFileStorage.saveBytesToAppDirectory(
      bytes: Uint8List.fromList([1]),
      fileName: 'work.key',
      subdirectory: 'keys',
    );

    await MobileFileStorage.deleteFileFromAppDirectory(
      filePath: path,
      subdirectory: 'keys',
    );

    expect(await MobileFileStorage.keyFileNames!.getAll(), isEmpty);
  });

  test('a key file written before names were recorded, or with the name '
      'store unreadable, is labelled rather than shown as hex', () async {
    final legacy = File(
      p.join(tempDir.path, 'keys', '0123456789abcdef0123456789abcdef'),
    );
    await legacy.create(recursive: true);

    expect(
      await MobileFileStorage.keyFileDisplayName(legacy.path),
      'Unnamed key file',
    );

    secure.unavailable = true;
    final listed = await MobileFileStorage.listFilesInAppDirectory(
      subdirectory: 'keys',
    );
    expect(listed.single.name, 'Unnamed key file');
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}
