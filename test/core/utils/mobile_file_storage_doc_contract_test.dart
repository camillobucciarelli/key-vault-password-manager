import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/mobile_file_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Pins the documented contract added by #44 and #45.
///
/// Both claims are prose in `mobile_file_storage.dart`, and prose that drifts
/// from the code is a bug. These assert the two statements a caller would rely
/// on, on *the same path*, so the asymmetry cannot silently collapse:
///
///   #44 - a `..` segment makes `isPathInAppDirectory` answer `false` and
///         makes `deleteFileFromAppDirectory` **throw**.
///   #45 - hardlinks are out of scope, and that is safe because delete is
///         `unlink`: the external name survives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late Directory outside;
  const sub = 'keys';

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('mfs_doc_contract_');
    docs = await Directory(p.join(root.path, 'Documents')).create();
    outside = await Directory(p.join(root.path, 'outside')).create();
    PathProviderPlatform.instance = _FixedPathProvider(docs.path);
  });

  tearDown(() async {
    final root = Directory(p.dirname(docs.path));
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Directory appSub() => Directory(p.join(docs.path, sub));

  test(
    '#44: one traversal path, two documented answers -- false and a throw',
    () async {
      await appSub().create(recursive: true);
      final real = File(p.join(appSub().path, 'v.keyx'));
      await real.writeAsString('data');

      // Textually this normalizes to exactly `real.path`, i.e. a file that
      // genuinely is inside app storage. The documented behaviour is to refuse
      // it anyway, because normalization and the kernel disagree once a
      // symlink sits in the middle.
      final traversal = p.join(appSub().path, 'hop', '..', 'v.keyx');
      expect(p.normalize(traversal), real.path);

      expect(
        await MobileFileStorage.isPathInAppDirectory(
          filePath: traversal,
          subdirectory: sub,
        ),
        isFalse,
        reason: 'documented: the predicate answers false, it does not throw',
      );

      await expectLater(
        MobileFileStorage.deleteFileFromAppDirectory(
          filePath: traversal,
          subdirectory: sub,
        ),
        throwsA(isA<Exception>()),
        reason: 'documented: deletion is destructive, so it must be loud',
      );

      expect(
        await real.exists(),
        isTrue,
        reason: 'the refusal must also not have deleted anything',
      );
    },
  );

  test('#45: a hardlink passes the guard, and that is safe', () async {
    await appSub().create(recursive: true);
    final victim = File(p.join(outside.path, 'victim.keyx'));
    await victim.writeAsString('external');
    final hard = p.join(appSub().path, 'hard.keyx');
    final ln = await Process.run('ln', [victim.path, hard]);
    expect(ln.exitCode, 0, reason: 'could not create hardlink');

    // Claim 1: realpath cannot see the second name, so the guard admits it.
    expect(
      await MobileFileStorage.isPathInAppDirectory(
        filePath: hard,
        subdirectory: sub,
      ),
      isTrue,
      reason:
          'If this ever becomes false the #45 comment is wrong and hardlinks '
          'are in fact defended against.',
    );

    // Claim 2: that is safe, because delete is `unlink`.
    await MobileFileStorage.deleteFileFromAppDirectory(
      filePath: hard,
      subdirectory: sub,
    );
    expect(File(hard).existsSync(), isFalse);
    expect(await victim.exists(), isTrue);
    expect(
      await victim.readAsString(),
      'external',
      reason: 'unlink must not have touched the external content',
    );
  }, skip: Platform.isWindows ? 'ln(1) is POSIX-only' : null);
}

class _FixedPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FixedPathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}
