import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/mobile_file_storage.dart';
import 'package:password_manager/core/utils/portable_path.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Security probes for the app-storage delete guard after it was made
/// symlink-aware in `fix/ios-portable-database-paths`.
///
/// Regression guard: several of these were written to fail against the
/// intermediate implementation and must not be relaxed.
class _FixedPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FixedPathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory docs;
  late Directory outside;
  const sub = 'databases';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('guard_qa_');
    docs = await Directory(p.join(root.path, 'Documents')).create();
    outside = await Directory(p.join(root.path, 'outside')).create();
    PathProviderPlatform.instance = _FixedPathProvider(docs.path);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Directory appSub() => Directory(p.join(docs.path, sub));

  group('guard is not loosened for plain paths', () {
    test('existing file outside the app dir is still refused', () async {
      final victim = File(p.join(outside.path, 'secret.kdbx'));
      await victim.writeAsString('secret');

      await expectLater(
        MobileFileStorage.deleteFileFromAppDirectory(
          filePath: victim.path,
          subdirectory: sub,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await victim.exists(), isTrue);
    });

    test(
      'non-existent path outside the app dir is still refused (exercises the '
      'p.normalize fallback inside resolveForComparison)',
      () async {
        await expectLater(
          MobileFileStorage.deleteFileFromAppDirectory(
            filePath: p.join(outside.path, 'nope', 'ghost.kdbx'),
            subdirectory: sub,
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('sibling directory with a shared prefix is still refused', () async {
      final sibling = await Directory(
        '${p.join(docs.path, sub)}_evil',
      ).create(recursive: true);
      final victim = File(p.join(sibling.path, 'x.kdbx'));
      await victim.writeAsString('secret');

      await expectLater(
        MobileFileStorage.deleteFileFromAppDirectory(
          filePath: victim.path,
          subdirectory: sub,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await victim.exists(), isTrue);
    });
  });

  group('the intended loosening, and only that', () {
    test(
      'a genuine app-dir file spelled through /private/var is deleted',
      () async {
        await appSub().create(recursive: true);
        final real = File(p.join(appSub().path, 'v.kdbx'));
        await real.writeAsString('data');

        // Same file, spelled the way UIDocumentPickerViewController spells it.
        final resolvedSpelling = p.join(
          Directory(appSub().path).resolveSymbolicLinksSync(),
          'v.kdbx',
        );
        expect(resolvedSpelling, isNot(real.path));

        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: resolvedSpelling,
          subdirectory: sub,
        );
        expect(await real.exists(), isFalse);
      },
    );
  });

  group('symlink escape attempts', () {
    test(
      'SECURITY: symlink INSIDE the app dir pointing OUT is refused',
      () async {
        await appSub().create(recursive: true);
        final victim = File(p.join(outside.path, 'secret.kdbx'));
        await victim.writeAsString('secret');
        final link = Link(p.join(appSub().path, 'escape.kdbx'));
        await link.create(victim.path);

        await expectLater(
          MobileFileStorage.deleteFileFromAppDirectory(
            filePath: link.path,
            subdirectory: sub,
          ),
          throwsA(isA<Exception>()),
          reason:
              'The resolved target is outside app storage, so the guard must '
              'refuse. (Pre-fix this was ALLOWED and unlinked the symlink.)',
        );
        expect(await victim.exists(), isTrue);
      },
    );

    test(
      'SECURITY: symlink OUTSIDE the app dir pointing IN must be refused',
      () async {
        await appSub().create(recursive: true);
        final real = File(p.join(appSub().path, 'v.kdbx'));
        await real.writeAsString('data');
        // An entry that lives outside app storage. Deleting it removes a file
        // outside the app directory, which is exactly what the guard exists to
        // prevent.
        final link = Link(p.join(outside.path, 'handle.kdbx'));
        await link.create(real.path);

        await expectLater(
          MobileFileStorage.deleteFileFromAppDirectory(
            filePath: link.path,
            subdirectory: sub,
          ),
          throwsA(isA<Exception>()),
          reason:
              'filePath is outside app storage. Resolving it before the '
              'containment check makes the guard accept it, and the delete '
              'then unlinks the OUTSIDE entry. Pre-fix this was refused.',
        );
        expect(
          await Link(link.path).exists(),
          isTrue,
          reason: 'the outside symlink must survive',
        );
      },
    );

    test(
      'SECURITY: ".." traversal through a symlink inside the app dir',
      () async {
        await appSub().create(recursive: true);
        final victim = File(p.join(root.path, 'secret.kdbx'));
        await victim.writeAsString('secret');
        final link = Link(p.join(appSub().path, 'hop'));
        await link.create(outside.path);

        // Textually normalizes to <docs>/databases/secret.kdbx (inside), but
        // the kernel resolves `hop` first and `..` then lands in <root>.
        final crafted = p.join(appSub().path, 'hop', '..', 'secret.kdbx');

        try {
          await MobileFileStorage.deleteFileFromAppDirectory(
            filePath: crafted,
            subdirectory: sub,
          );
        } catch (_) {
          // Refused: fine.
        }
        final survived = await victim.exists();

        // Parity check against the PRE-FIX guard, which compared
        // `p.normalize(dir)` with `p.normalize(filePath)`. If that also
        // considered `crafted` to be inside, this hazard is pre-existing and
        // NOT a regression introduced by the symlink work.
        final preFixWouldHaveAllowed = p.isWithin(
          p.normalize(appSub().path),
          p.normalize(crafted),
        );

        expect(
          preFixWouldHaveAllowed,
          isTrue,
          reason:
              'If the pre-fix guard had refused this, the escape would be a '
              'NEW regression rather than a pre-existing one.',
        );
        expect(
          survived,
          isTrue,
          reason:
              'PRE-EXISTING (not a regression): normalize-then-resolve lets a '
              '".." hop through an in-app symlink delete a file outside app '
              'storage. Identical before and after this change.',
        );
      },
    );
  });

  test(
    'SECURITY (proof): the outside symlink is actually unlinked, no throw',
    () async {
      await appSub().create(recursive: true);
      final real = File(p.join(appSub().path, 'v.kdbx'));
      await real.writeAsString('data');
      final link = Link(p.join(outside.path, 'handle.kdbx'));
      await link.create(real.path);

      var threw = false;
      try {
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: link.path,
          subdirectory: sub,
        );
      } catch (_) {
        threw = true;
      }

      // ignore: avoid_print
      print(
        'GUARD_PROBE threw=$threw '
        'outsideLinkStillThere=${link.existsSync()} '
        'appFileStillThere=${real.existsSync()}',
      );
    },
  );

  group('resolveForComparison edge cases', () {
    test('broken symlink in the middle of the path does not throw', () {
      final link = Link(p.join(docs.path, 'dangling'));
      link.createSync(p.join(root.path, 'does', 'not', 'exist'));
      final probe = p.join(link.path, 'child', 'v.kdbx');

      expect(() => PortablePath.resolveForComparison(probe), returnsNormally);
    });

    test('a relative path is returned normalized, never thrown', () {
      expect(
        () => PortablePath.resolveForComparison('relative/dir/v.kdbx'),
        returnsNormally,
      );
    });

    test('empty string does not throw', () {
      expect(() => PortablePath.resolveForComparison(''), returnsNormally);
    });

    test('decode performs no filesystem I/O', () {
      // A root that does not exist: if decode touched the filesystem this
      // would throw or resolve differently.
      final ghostRoot = p.join(root.path, 'ghost', 'Documents');
      expect(
        PortablePath.decode('appdocs:databases/v.kdbx', ghostRoot),
        p.join(ghostRoot, 'databases', 'v.kdbx'),
      );
    });
  });
}
