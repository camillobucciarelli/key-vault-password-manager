import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/portable_path.dart';
import 'package:password_manager/features/password_manager/data/datasources/database_registry_local_data_source.dart';
import 'package:password_manager/features/password_manager/data/repositories/database_registry_repository_impl.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Symlink probes for `fix/ios-portable-database-paths`.
///
/// These were written to fail against the first implementation, which compared
/// path strings without resolving `/var` onto `/private/var` and so silently
/// stored an absolute path for files the picker returned. Regression guard: a
/// red test here means the portability fix has stopped working.
class _MutablePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _MutablePathProvider(this.basePath);

  String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory containerRoot;
  late String unresolvedRoot;
  late String resolvedRoot;
  late _MutablePathProvider pathProvider;

  setUp(() async {
    containerRoot = await Directory.systemTemp.createTemp('portable_symlink_');
    unresolvedRoot = containerRoot.path;
    resolvedRoot = containerRoot.resolveSymbolicLinksSync();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await containerRoot.delete(recursive: true);
  });

  /// On macOS `Directory.systemTemp` is `/var/folders/...`, a symlink to
  /// `/private/var/folders/...` -- structurally identical to iOS, where
  /// `NSSearchPathForDirectoriesInDomains` yields `/var/mobile/Containers/...`
  /// while `UIDocumentPickerViewController` hands back
  /// `/private/var/mobile/Containers/...` for the very same file.
  test('PRECONDITION: temp root is a symlink (/var vs /private/var)', () {
    expect(
      resolvedRoot,
      isNot(unresolvedRoot),
      reason:
          'Host filesystem does not reproduce the iOS symlink shape; the '
          'symlink findings below cannot be exercised here.',
    );
    expect(p.isWithin(unresolvedRoot, p.join(resolvedRoot, 'x')), isFalse);
  });

  test('DEFECT: encode silently gives up when docs root and path disagree on '
      '/var vs /private/var', () {
    final picked = p.join(resolvedRoot, 'databases', 'vault.kdbx');

    final encoded = PortablePath.encode(picked, unresolvedRoot);

    expect(
      encoded,
      startsWith('appdocs:'),
      reason:
          'A file that physically lives inside the app documents directory '
          'was persisted as an absolute path because the two strings use '
          'different symlink prefixes. On iOS this reintroduces the original '
          'bug with every existing test still green.',
    );
  });

  test('DEFECT: a record located via the iOS file picker stays missing after a '
      'container relocation', () async {
    final oldDocs = await Directory(
      p.join(unresolvedRoot, 'UUID-A', 'Documents'),
    ).create(recursive: true);
    final newDocs = await Directory(
      p.join(unresolvedRoot, 'UUID-B', 'Documents'),
    ).create(recursive: true);
    pathProvider = _MutablePathProvider(oldDocs.path);
    PathProviderPlatform.instance = pathProvider;

    // What UIDocumentPickerViewController returns for a file the app itself
    // owns: the same file, spelled through /private/var.
    final pickedPath = p.join(
      resolvedRoot,
      'UUID-A',
      'Documents',
      'databases',
      'vault.kdbx',
    );

    Future<DatabaseRegistryRepositoryImpl> registry() async =>
        DatabaseRegistryRepositoryImpl(
          localDataSource: DatabaseRegistryLocalDataSourceImpl(
            sharedPreferences: await SharedPreferences.getInstance(),
          ),
        );

    final now = DateTime.utc(2024, 1, 1);
    await (await registry()).upsert(
      DatabaseRecord(
        databaseId: 'db-1',
        canonicalPath: pickedPath,
        displayName: 'Vault',
        sourceType: DatabaseSourceType.local,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Relocate: carry metadata across, swap the container UUID.
    final source = Directory(p.join(oldDocs.path, 'metadata'));
    final target = Directory(p.join(newDocs.path, 'metadata'));
    await target.create(recursive: true);
    await for (final entry in source.list(followLinks: false)) {
      if (entry is File) {
        await entry.copy(p.join(target.path, p.basename(entry.path)));
      }
    }
    pathProvider.basePath = newDocs.path;

    final records = await (await registry()).list();
    expect(
      records.single.canonicalPath,
      p.join(newDocs.path, 'databases', 'vault.kdbx'),
      reason:
          'The record still points at the dead UUID-A container: the fix did '
          'not portabilize it because the picker path uses /private/var.',
    );
  });

  group('lower-severity encode edge cases', () {
    test('a path equal to the documents root is stored absolute', () {
      expect(
        PortablePath.encode(unresolvedRoot, unresolvedRoot),
        isNot(startsWith('appdocs:')),
      );
    });

    test('case-different documents root defeats containment', () {
      final docs = p.join(unresolvedRoot, 'Documents');
      final file = p.join(unresolvedRoot, 'documents', 'vault.kdbx');
      expect(PortablePath.encode(file, docs), file);
    });

    test('unnormalized ".." segments are handled', () {
      final docs = p.join(unresolvedRoot, 'Documents');
      final file = p.join(unresolvedRoot, 'Documents', 'a', '..', 'v.kdbx');
      expect(PortablePath.encode(file, docs), 'appdocs:v.kdbx');
    });

    test(
      'a file literally named "appdocs:x" inside the docs root round-trips',
      () {
        final docs = p.join(unresolvedRoot, 'Documents');
        final file = p.join(docs, 'appdocs:x.kdbx');
        expect(PortablePath.encode(file, docs), 'appdocs:appdocs:x.kdbx');
        expect(
          PortablePath.decode(PortablePath.encode(file, docs), docs),
          file,
        );
      },
    );
  });
}
