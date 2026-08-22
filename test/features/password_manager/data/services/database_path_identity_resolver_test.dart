// Platform prerequisite: this suite uses `Link.create` to build symlink
// aliases. On Windows that requires Developer Mode or an elevated shell;
// without it these tests fail for environment reasons only. Deliberately not
// skipped — CI Flutter jobs run on `ubuntu-latest`, and macOS is unaffected.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/database_path_identity_resolver.dart';
import 'package:path/path.dart' as p;

// =============================================================================
// spec 008 Gate 1 T103/T107 — path identity alias matrix.
//
// Every alias pair below must collapse onto one lock key (or be provably the
// same entity), and every case where identity is NOT provable must surface
// `proven: false`, which is what routes the mutex onto the global fallback.
// =============================================================================

void main() {
  const resolver = DatabasePathIdentityResolver();

  late Directory root;
  late String base;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('path_identity_');
    // Resolve the temp root first (macOS `/var/folders` is itself a symlink
    // to `/private/var/folders`) so the aliases built below are the only
    // divergence under test.
    base = root.resolveSymbolicLinksSync();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  /// Detected at runtime, not assumed per platform: what the case-alias
  /// expectations assert depends on the filesystem the suite runs on.
  bool fsFoldsCase(String existingFile) {
    final dir = p.dirname(existingFile);
    final name = p.basename(existingFile);
    final flipped = p.join(dir, name.toUpperCase());
    if (flipped == existingFile) {
      fail('probe file name needs lowercase letters');
    }
    try {
      return FileSystemEntity.identicalSync(existingFile, flipped);
    } on FileSystemException {
      return false;
    }
  }

  Future<File> vault(String name, [String? dir]) async {
    if (dir != null) {
      await Directory(dir).create(recursive: true);
    }
    return File(p.join(dir ?? base, name)).writeAsBytes([1, 2, 3]);
  }

  group('T103 alias matrix', () {
    test('relative and absolute spellings share one identity', () async {
      final file = await vault('vault.kdbx');
      final previous = Directory.current;
      Directory.current = base;
      addTearDown(() => Directory.current = previous);

      final absolute = resolver.resolve(file.path);
      final relative = resolver.resolve('vault.kdbx');
      expect(relative.lockKey, absolute.lockKey);
      expect(relative.proven, isTrue);
      expect(absolute.proven, isTrue);
    });

    test('redundant separators and . / .. segments collapse', () async {
      final file = await vault('vault.kdbx', p.join(base, 'a'));
      final plain = resolver.resolve(file.path);
      final messy = resolver.resolve(
        '$base${p.separator}a${p.separator}${p.separator}.'
        '${p.separator}b${p.separator}..${p.separator}vault.kdbx',
      );
      expect(messy.lockKey, plain.lockKey);
    });

    test('a symlinked file resolves to its target identity', () async {
      final real = await vault('vault.kdbx');
      final link = Link(p.join(base, 'alias.kdbx'));
      await link.create(real.path);

      expect(
        resolver.resolve(link.path).lockKey,
        resolver.resolve(real.path).lockKey,
      );
    });

    test(
      'a symlinked parent directory resolves to the real directory',
      () async {
        final realDir = await Directory(p.join(base, 'real')).create();
        final real = await vault('vault.kdbx', realDir.path);
        final linkDir = Link(p.join(base, 'linkdir'));
        await linkDir.create(realDir.path);

        final viaLink = resolver.resolve(p.join(linkDir.path, 'vault.kdbx'));
        expect(viaLink.lockKey, resolver.resolve(real.path).lockKey);
        expect(viaLink.proven, isTrue);
      },
    );

    test(
      'a dangling symlink takes the identity of its missing target',
      () async {
        // Writing "through" the link is what creates the target, so locking
        // the link independently of the target path would be two locks on one
        // future file.
        final targetPath = p.join(base, 'future.kdbx');
        final link = Link(p.join(base, 'dangling.kdbx'));
        await link.create(targetPath);

        final viaLink = resolver.resolve(link.path);
        final direct = resolver.resolve(targetPath);
        expect(viaLink.lockKey, direct.lockKey);
        expect(viaLink.exists, isFalse);
      },
    );

    test('missing target with an existing parent is proven and comparable', () {
      final identity = resolver.resolve(p.join(base, 'not-yet.kdbx'));
      expect(identity.exists, isFalse);
      expect(identity.proven, isTrue);
      expect(
        resolver.resolve(p.join(base, 'x', '..', 'not-yet.kdbx')).lockKey,
        identity.lockKey,
      );
    });

    test('missing parent directory is NOT proven — global-lock fallback', () {
      final identity = resolver.resolve(
        p.join(base, 'missing-dir', 'deeper', 'v.kdbx'),
      );
      expect(identity.exists, isFalse);
      expect(
        identity.proven,
        isFalse,
        reason:
            'a to-be-created directory chain has no probeable case '
            'semantics; the mutex must fall back to the global lock instead '
            'of guessing',
      );
    });

    test(
      'case aliases follow the real filesystem, detected at runtime',
      () async {
        final file = await vault('casealias.kdbx');
        final folds = fsFoldsCase(file.path);

        final lower = resolver.resolve(file.path);
        final upper = resolver.resolve(p.join(base, 'CASEALIAS.KDBX'));
        if (folds) {
          expect(
            upper.lockKey,
            lower.lockKey,
            reason: 'one file on a folding volume must map to one lock',
          );
        } else {
          expect(
            upper.lockKey,
            isNot(lower.lockKey),
            reason: 'two genuinely distinct paths on a sensitive volume',
          );
        }
        expect(
          lower.proven,
          isTrue,
          reason: 'the probe is decisive on an existing path either way',
        );
      },
    );

    test('a not-yet-created file has one identity across case spellings on a '
        'folding volume', () async {
      // MEDIUM-1 (tester): for a missing target the case probe runs on the
      // PARENT directory, and the case-different tail is re-appended
      // verbatim by canonicalization — so only the probe-driven fold can
      // merge the spellings. A mutated probe that answers "sensitive" on a
      // folding volume hands two independent locks to one future file;
      // this test is what kills that mutation.
      final probe = await vault('probe.tmp');
      final folds = fsFoldsCase(probe.path);

      final lower = resolver.resolve(p.join(base, 'newvault.kdbx'));
      final upper = resolver.resolve(p.join(base, 'NEWVAULT.KDBX'));
      expect(lower.exists, isFalse);
      expect(upper.exists, isFalse);
      expect(
        lower.proven,
        isTrue,
        reason: 'the parent exists and the probe is decisive',
      );
      if (folds) {
        expect(
          upper.lockKey,
          lower.lockKey,
          reason:
              'both spellings will create the SAME file on this folding '
              'volume; two lock keys here means two independent locks on '
              'one future vault',
        );
      } else {
        expect(
          upper.lockKey,
          isNot(lower.lockKey),
          reason:
              'on a sensitive volume these create two distinct files and '
              'must stay independently lockable',
        );
      }
    });

    test('source == target trivially shares one identity', () async {
      final file = await vault('same.kdbx');
      expect(
        resolver.resolve(file.path).lockKey,
        resolver.resolve(file.path).lockKey,
      );
    });

    test(
      'hard links are the same entity where the platform supports them',
      () async {
        final original = await vault('original.kdbx');
        final linked = p.join(base, 'hardlink.kdbx');
        final result = Platform.isWindows
            ? await Process.run('fsutil', [
                'hardlink',
                'create',
                linked,
                original.path,
              ])
            : await Process.run('ln', [original.path, linked]);
        expect(
          result.exitCode,
          0,
          reason: 'hard-link creation failed: ${result.stderr}',
        );

        // Two different canonical strings, one inode: the string form cannot
        // see it, the pairwise entity check must.
        expect(
          resolver.resolve(linked).lockKey,
          isNot(resolver.resolve(original.path).lockKey),
        );
        expect(resolver.isSameEntity(linked, original.path), isTrue);
      },
    );

    test('isSameEntity is false for a nonexistent path', () async {
      final file = await vault('exists.kdbx');
      expect(
        resolver.isSameEntity(file.path, p.join(base, 'ghost.kdbx')),
        isFalse,
      );
      expect(resolver.isSameEntity(file.path, file.path), isTrue);
    });

    test('distinct files are distinct identities', () async {
      final a = await vault('a.kdbx');
      final b = await vault('b.kdbx');
      expect(
        resolver.resolve(a.path).lockKey,
        isNot(resolver.resolve(b.path).lockKey),
      );
      expect(resolver.isSameEntity(a.path, b.path), isFalse);
    });
  });
}
