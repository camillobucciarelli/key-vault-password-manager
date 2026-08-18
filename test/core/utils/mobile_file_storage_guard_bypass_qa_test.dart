// Platform prerequisite: this suite uses `Link.create` to build a
// `/var`→`/private/var`-style path divergence. On Windows that requires
// Developer Mode or an elevated shell; without it these tests fail for
// environment reasons only. Deliberately not skipped — CI Flutter jobs run on
// `ubuntu-latest`, and macOS is unaffected.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/mobile_file_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Bypass probes for the two-condition app-storage guard.
///
/// Companion to `mobile_file_storage_guard_qa_test.dart`: that file pins the
/// guard's core behaviour, this one hunts for a third way past it (symlink
/// chains, symlinked parents, hardlinks), checks that real caller shapes are
/// not refused by mistake, and asserts `isPathInAppDirectory` agrees with
/// `deleteFileFromAppDirectory` — they gate each other at
/// `database_import_service.dart:64-72`.
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
  const sub = 'keys';

  setUp(() async {
    // See mobile_file_storage_guard_qa_test.dart: the documents directory is
    // reached through a symlink so the `/var` vs `/private/var` divergence is
    // reproduced on Linux as well as macOS.
    final rawRoot = await Directory.systemTemp.createTemp('guard_bypass_');
    root = Directory(rawRoot.resolveSymbolicLinksSync());
    final realDocs = await Directory(
      p.join(root.path, 'Documents.real'),
    ).create();
    final docsLink = Link(p.join(root.path, 'Documents'));
    await docsLink.create(realDocs.path);

    docs = Directory(docsLink.path);
    outside = await Directory(p.join(root.path, 'outside')).create();
    PathProviderPlatform.instance = _FixedPathProvider(docs.path);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Directory appSub() => Directory(p.join(docs.path, sub));

  Future<void> expectRefused(String filePath) async {
    await expectLater(
      MobileFileStorage.deleteFileFromAppDirectory(
        filePath: filePath,
        subdirectory: sub,
      ),
      throwsA(isA<Exception>()),
    );
  }

  group('is there a third way past the two conditions?', () {
    test(
      'symlink CHAIN inside app storage ending outside is refused',
      () async {
        await appSub().create(recursive: true);
        final victim = File(p.join(outside.path, 'secret.kdbx'));
        await victim.writeAsString('secret');

        // hop1 -> hop2 -> victim, all resolved by realpath in one shot.
        final hop2 = Link(p.join(appSub().path, 'hop2.kdbx'));
        await hop2.create(victim.path);
        final hop1 = Link(p.join(appSub().path, 'hop1.kdbx'));
        await hop1.create(hop2.path);

        await expectRefused(hop1.path);
        expect(await victim.exists(), isTrue);
      },
    );

    test('symlinked PARENT directory pointing outside is refused', () async {
      await appSub().create(recursive: true);
      final realDir = await Directory(p.join(outside.path, 'dir')).create();
      final victim = File(p.join(realDir.path, 'secret.kdbx'));
      await victim.writeAsString('secret');

      // <docs>/keys/alias -> <root>/outside/dir
      final alias = Link(p.join(appSub().path, 'alias'));
      await alias.create(realDir.path);

      await expectRefused(p.join(alias.path, 'secret.kdbx'));
      expect(await victim.exists(), isTrue);
    });

    test(
      'symlink whose parent is ALSO a symlink, both landing outside, refused',
      () async {
        await appSub().create(recursive: true);
        final realDir = await Directory(p.join(outside.path, 'dir')).create();
        final victim = File(p.join(realDir.path, 'secret.kdbx'));
        await victim.writeAsString('secret');
        final aliasDir = Link(p.join(outside.path, 'aliasdir'));
        await aliasDir.create(realDir.path);
        final entry = Link(p.join(appSub().path, 'entry.kdbx'));
        await entry.create(p.join(aliasDir.path, 'secret.kdbx'));

        await expectRefused(entry.path);
        expect(await victim.exists(), isTrue);
      },
    );

    test(
      'outside symlink whose target is an in-app symlink is refused',
      () async {
        await appSub().create(recursive: true);
        final real = File(p.join(appSub().path, 'v.kdbx'));
        await real.writeAsString('data');
        final inner = Link(p.join(appSub().path, 'inner.kdbx'));
        await inner.create(real.path);
        final outer = Link(p.join(outside.path, 'outer.kdbx'));
        await outer.create(inner.path);

        await expectRefused(outer.path);
        expect(outer.existsSync(), isTrue);
        expect(await real.exists(), isTrue);
      },
    );

    test(
      'traversal check cannot be short-circuited past a containment fail',
      () async {
        // Refusal conditions are OR-ed, so an earlier true only refuses sooner.
        await expectRefused(p.join(outside.path, '..', 'x.kdbx'));
        await expectRefused(p.join(appSub().path, '..', '..', 'x.kdbx'));
        await expectRefused(p.join(appSub().path, 'a', '..', 'x.kdbx'));
      },
    );

    test(
      'HARDLINK in app storage to an outside file: only the in-app name goes',
      () async {
        await appSub().create(recursive: true);
        final victim = File(p.join(outside.path, 'secret.kdbx'));
        await victim.writeAsString('secret');
        final hard = p.join(appSub().path, 'hard.kdbx');
        final r = await Process.run('ln', [victim.path, hard]);
        expect(r.exitCode, 0, reason: 'could not create hardlink');

        // realpath cannot see a hardlink's other names, so this passes the
        // guard. unlink() removes only this name; the outside file survives.
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: hard,
          subdirectory: sub,
        );
        expect(File(hard).existsSync(), isFalse);
        expect(
          await victim.exists(),
          isTrue,
          reason: 'no file outside app storage may be destroyed',
        );
      },
    );

    test('in-app symlink to an in-app file unlinks only the link', () async {
      await appSub().create(recursive: true);
      final real = File(p.join(appSub().path, 'v.kdbx'));
      await real.writeAsString('data');
      final link = Link(p.join(appSub().path, 'alias.kdbx'));
      await link.create(real.path);

      await MobileFileStorage.deleteFileFromAppDirectory(
        filePath: link.path,
        subdirectory: sub,
      );
      expect(link.existsSync(), isFalse);
      expect(await real.exists(), isTrue);
    });
  });

  group('false negatives: real caller shapes must still be accepted', () {
    test(
      'saveBytesToAppDirectory output round-trips through both APIs',
      () async {
        final saved = await MobileFileStorage.saveBytesToAppDirectory(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'vault.keyx',
          subdirectory: sub,
        );
        expect(
          await MobileFileStorage.isPathInAppDirectory(
            filePath: saved,
            subdirectory: sub,
          ),
          isTrue,
        );
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: saved,
          subdirectory: sub,
        );
        expect(File(saved).existsSync(), isFalse);
      },
    );

    test(
      'listFilesInAppDirectory output is accepted (sheet/dialog delete)',
      () async {
        await MobileFileStorage.saveBytesToAppDirectory(
          bytes: Uint8List.fromList([1]),
          fileName: 'a.keyx',
          subdirectory: sub,
        );
        final entries = await MobileFileStorage.listFilesInAppDirectory(
          subdirectory: sub,
        );
        expect(entries, hasLength(1));
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: entries.single.path,
          subdirectory: sub,
        );
        expect(File(entries.single.path).existsSync(), isFalse);
      },
    );

    test(
      'getPathInAppDirectory output (file not yet created) is accepted',
      () async {
        final path = await MobileFileStorage.getPathInAppDirectory(
          fileName: 'ghost.keyx',
          subdirectory: sub,
        );
        expect(
          await MobileFileStorage.isPathInAppDirectory(
            filePath: path,
            subdirectory: sub,
          ),
          isTrue,
        );
        // Non-existent but in-app: must not throw.
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: path,
          subdirectory: sub,
        );
      },
    );

    test(
      '/private/var spelling of a real in-app file is still accepted',
      () async {
        final saved = await MobileFileStorage.saveBytesToAppDirectory(
          bytes: Uint8List.fromList([1]),
          fileName: 'v.keyx',
          subdirectory: sub,
        );
        final resolvedSpelling = p.join(
          Directory(appSub().path).resolveSymbolicLinksSync(),
          'v.keyx',
        );
        expect(resolvedSpelling, isNot(saved));
        expect(
          await MobileFileStorage.isPathInAppDirectory(
            filePath: resolvedSpelling,
            subdirectory: sub,
          ),
          isTrue,
        );
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: resolvedSpelling,
          subdirectory: sub,
        );
        expect(File(saved).existsSync(), isFalse);
      },
    );

    test(
      'a filename containing dots but no ".." segment is accepted',
      () async {
        final saved = await MobileFileStorage.saveBytesToAppDirectory(
          bytes: Uint8List.fromList([1]),
          fileName: 'my..vault..keyx',
          subdirectory: sub,
        );
        expect(p.split(saved).contains('..'), isFalse);
        expect(
          await MobileFileStorage.isPathInAppDirectory(
            filePath: saved,
            subdirectory: sub,
          ),
          isTrue,
        );
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: saved,
          subdirectory: sub,
        );
      },
    );
  });

  group('isPathInAppDirectory agrees with the delete guard', () {
    test('in-app symlink pointing outside reports false', () async {
      await appSub().create(recursive: true);
      final victim = File(p.join(outside.path, 'secret.kdbx'));
      await victim.writeAsString('secret');
      final link = Link(p.join(appSub().path, 'escape.keyx'));
      await link.create(victim.path);

      expect(
        await MobileFileStorage.isPathInAppDirectory(
          filePath: link.path,
          subdirectory: sub,
        ),
        isFalse,
      );
    });

    test('outside symlink pointing in reports false', () async {
      await appSub().create(recursive: true);
      final real = File(p.join(appSub().path, 'v.keyx'));
      await real.writeAsString('data');
      final link = Link(p.join(outside.path, 'handle.keyx'));
      await link.create(real.path);

      expect(
        await MobileFileStorage.isPathInAppDirectory(
          filePath: link.path,
          subdirectory: sub,
        ),
        isFalse,
      );
    });

    test('".." reports false', () async {
      expect(
        await MobileFileStorage.isPathInAppDirectory(
          filePath: p.join(appSub().path, 'a', '..', 'v.keyx'),
          subdirectory: sub,
        ),
        isFalse,
      );
    });
  });
}
