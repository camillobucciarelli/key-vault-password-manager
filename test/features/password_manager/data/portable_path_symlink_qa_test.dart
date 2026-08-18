// Platform prerequisite: this suite uses `Link.create` to build a
// `/var`→`/private/var`-style path divergence. On Windows that requires
// Developer Mode or an elevated shell; without it these tests fail for
// environment reasons only. Deliberately not skipped — CI Flutter jobs run on
// `ubuntu-latest`, and macOS is unaffected.

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
    // Build the two spellings explicitly rather than relying on the host temp
    // directory to supply them: macOS `/var/folders/...` is a symlink to
    // `/private/var/folders/...`, but Linux `/tmp/...` is not, so on CI the
    // divergence simply did not exist and these tests either failed on the
    // precondition or passed without exercising anything.
    //
    // `base` is resolved first so `real` and `link` are the only difference.
    final base = Directory(containerRoot.resolveSymbolicLinksSync());
    final realRoot = await Directory(p.join(base.path, 'real')).create();
    final linkRoot = Link(p.join(base.path, 'link'));
    await linkRoot.create(realRoot.path);

    // Stands in for what path_provider returns (`/var/...`).
    unresolvedRoot = linkRoot.path;
    // Stands in for what UIDocumentPickerViewController returns
    // (`/private/var/...`): the same directory, spelled through the target.
    resolvedRoot = realRoot.path;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await containerRoot.delete(recursive: true);
  });

  /// The setUp builds a symlinked spelling of one directory -- structurally
  /// identical to iOS, where `NSSearchPathForDirectoriesInDomains` yields
  /// `/var/mobile/Containers/...` while `UIDocumentPickerViewController` hands
  /// back `/private/var/mobile/Containers/...` for the very same file.
  test('PRECONDITION: the two spellings diverge but name one directory', () {
    expect(
      resolvedRoot,
      isNot(unresolvedRoot),
      reason:
          'The test did not construct the two-spelling divergence, so the '
          'symlink findings below cannot be exercised.',
    );
    expect(
      Directory(unresolvedRoot).resolveSymbolicLinksSync(),
      resolvedRoot,
      reason:
          'Both spellings must name the same directory, otherwise the findings '
          'below would be testing two unrelated paths.',
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

    // Flipped by #43. This used to pin the giving-up behaviour: a
    // case-different root made `p.isWithin` return false, so a file that
    // physically lives in the documents directory was persisted absolute and
    // went missing on the next container relocation -- the #41 bug, silently
    // reintroduced. Containment now folds case on case-insensitive volumes.
    test('case-different documents root no longer defeats containment', () {
      PortablePath.debugFoldsCaseOverride = true;
      addTearDown(() => PortablePath.debugFoldsCaseOverride = null);

      final docs = p.join(unresolvedRoot, 'Documents');
      final file = p.join(unresolvedRoot, 'documents', 'vault.kdbx');
      expect(PortablePath.encode(file, docs), 'appdocs:vault.kdbx');
    });

    test('case-different documents root stays absolute on a case-sensitive '
        'filesystem', () {
      PortablePath.debugFoldsCaseOverride = false;
      addTearDown(() => PortablePath.debugFoldsCaseOverride = null);

      final docs = p.join(unresolvedRoot, 'Documents');
      final file = p.join(unresolvedRoot, 'documents', 'vault.kdbx');
      expect(
        PortablePath.encode(file, docs),
        file,
        reason:
            'On Linux/Android these are two different directories, so folding '
            'case would invent a containment that does not exist.',
      );
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
