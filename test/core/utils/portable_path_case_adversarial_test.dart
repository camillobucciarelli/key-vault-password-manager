import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/portable_path.dart';
import 'package:path/path.dart' as p;

/// QA adversarial probes for #43 (`_relativeWithin` case folding).
///
/// The developer's `portable_path_case_test.dart` covers the happy shapes.
/// These push on the edges the fix's own comments claim to handle: a root with
/// a trailing separator, the filesystem root, mixed case across several
/// levels, non-ASCII segments, and the interaction with the pre-existing
/// `/var` -> `/private/var` symlink normalization.
///
/// The invariant under test throughout: the *comparison* may fold case, the
/// *stored value* never may. A lowercased `appdocs:` segment would not resolve
/// once the vault moved to a case-sensitive volume.
void main() {
  late Directory tempRoot;
  late String base;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pp_case_adv_');
    base = tempRoot.resolveSymbolicLinksSync();
  });

  tearDown(() async {
    PortablePath.debugFoldsCaseOverride = null;
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('case-insensitive volume', () {
    setUp(() => PortablePath.debugFoldsCaseOverride = true);

    test('a root spelled with a trailing separator still folds', () {
      final docs = '${p.join(base, 'Documents')}${p.separator}';
      final file = p.join(base, 'documents', 'Sub', 'Vault.KDBX');

      expect(PortablePath.encode(file, docs), 'appdocs:Sub/Vault.KDBX');
    });

    test('mixed case across several levels keeps every segment verbatim', () {
      final docs = p.join(base, 'DOCUMENTS');
      final file = p.join(base, 'documents', 'DaTaBaSeS', 'Ar', 'VaULT.KdBx');

      final stored = PortablePath.encode(file, docs);
      expect(stored, 'appdocs:DaTaBaSeS/Ar/VaULT.KdBx');
      expect(
        stored,
        isNot(contains('databases')),
        reason: 'A lowercased segment must never reach storage.',
      );
    });

    test('non-ASCII segments survive the fold with their own case', () {
      final docs = p.join(base, 'Documenti');
      final file = p.join(base, 'documenti', 'Àrchivi', 'Größe', 'Vàult.KDBX');

      expect(
        PortablePath.encode(file, docs),
        'appdocs:Àrchivi/Größe/Vàult.KDBX',
      );
    });

    test(
      'the filesystem root as documents root yields a full relative tail',
      () {
        expect(PortablePath.encode('/Vault.KDBX', '/'), 'appdocs:Vault.KDBX');
        expect(
          PortablePath.encode('/A/B/Vault.KDBX', '/'),
          'appdocs:A/B/Vault.KDBX',
        );
      },
      // POSIX-only: `/` is the filesystem root only on POSIX. On Windows a
      // leading `\\` is DRIVE-RELATIVE, so `resolveForComparison` resolves it
      // against the current drive and the synthetic segments may collide with
      // real directories — on the CI runner `/A` resolves onto the workspace
      // root `D:\\a`, and `resolveSymbolicLinksSync` then correctly rewrites
      // `A` to its on-disk spelling `a`. That is the documented behaviour of
      // the helper, not a defect, and the root-as-documents-root case has no
      // Windows equivalent to assert.
      skip: Platform.isWindows
          ? 'POSIX-only: "/" is drive-relative on Windows, not the '
                'filesystem root'
          : null,
    );

    test(
      'a path equal to the root modulo case is not claimed as contained',
      () {
        final docs = p.join(base, 'Documents');
        final file = p.join(base, 'documents');

        expect(
          PortablePath.encode(file, docs),
          file,
          reason:
              'p.isWithin excludes equality; the folded branch must not '
              'disagree with the unfolded one about the root itself.',
        );
      },
    );

    test(
      'a sibling whose name merely starts with the root name stays absolute',
      () {
        final docs = p.join(base, 'Documents');
        final file = p.join(base, 'documents2', 'Vault.KDBX');

        expect(PortablePath.encode(file, docs), file);
      },
    );

    test(
      'folding does not regress /var -> /private/var normalization',
      () async {
        // Reproduce the #41 divergence: `link` -> `real`, root spelled through
        // the link, file spelled through the target, plus a case difference.
        final real = await Directory(p.join(base, 'real')).create();
        final linkPath = p.join(base, 'link');
        await Link(linkPath).create(real.path);

        final docs = p.join(linkPath, 'Documents');
        final file = p.join(real.path, 'documents', 'DataBases', 'Vault.KDBX');

        expect(PortablePath.encode(file, docs), 'appdocs:DataBases/Vault.KDBX');
      },
    );

    test('round-trip resolves on disk when neither spelling existed at encode '
        'time', () async {
      // Deliberately encode *before* creating anything: on macOS `realpath`
      // canonicalizes the case of an existing directory, which would let the
      // plain `p.isWithin` branch succeed and make this test blind to the fix.
      final file = p.join(base, 'Documents', 'DataBases', 'Vault.KDBX');
      final stored = PortablePath.encode(file, p.join(base, 'documents'));
      expect(stored, 'appdocs:DataBases/Vault.KDBX');

      await Directory(p.dirname(file)).create(recursive: true);
      await File(file).writeAsBytes(const [1, 2, 3], flush: true);

      final decoded = PortablePath.decode(stored, p.join(base, 'Documents'));
      expect(decoded, file);
      expect(File(decoded).existsSync(), isTrue);
    });

    test(
      'an already-encoded value is not double-encoded by the fold branch',
      () {
        expect(
          PortablePath.encode(
            'appdocs:DataBases/Vault.KDBX',
            p.join(base, 'documents'),
          ),
          'appdocs:DataBases/Vault.KDBX',
        );
      },
    );
  });

  group('case-sensitive volume', () {
    setUp(() => PortablePath.debugFoldsCaseOverride = false);

    test(
      'two real directories differing only by case stay distinct',
      () {
        final docs = p.join(base, 'Documents');
        final file = p.join(base, 'documents', 'DataBases', 'Vault.KDBX');

        expect(PortablePath.encode(file, docs), file);
      },
      // POSIX-only, and not a coverage gap that can be closed here.
      // `debugFoldsCaseOverride = false` turns off PortablePath's OWN case
      // fold, but the first branch of `_relativeWithin` is `p.isWithin`, and
      // on Windows `package:path` uses its Windows context, which compares
      // case-insensitively by itself. Containment therefore succeeds before
      // the override is ever consulted, so a case-SENSITIVE volume cannot be
      // expressed on this host at all. The scenario stays covered on Linux and
      // macOS CI, where the override does what it says.
      skip: Platform.isWindows
          ? 'a case-sensitive volume cannot be simulated on Windows: '
                'package:path folds case in p.isWithin before the override '
                'is consulted'
          : null,
    );

    test('a path outside the root stays absolute, unchanged', () {
      final docs = p.join(base, 'Documents');
      final file = p.join(base, 'Elsewhere', 'Vault.KDBX');

      expect(PortablePath.encode(file, docs), file);
    });

    test('matching case is unaffected at any depth', () {
      final docs = p.join(base, 'Documents');
      final file = p.join(base, 'Documents', 'DaTaBaSeS', 'VaULT.KdBx');

      expect(PortablePath.encode(file, docs), 'appdocs:DaTaBaSeS/VaULT.KdBx');
    });
  });

  test('the default (no override) matches the host platform', () {
    PortablePath.debugFoldsCaseOverride = null;
    final docs = p.join(base, 'Documents');
    final file = p.join(base, 'documents', 'Vault.KDBX');
    final expected = (Platform.isIOS || Platform.isMacOS || Platform.isWindows)
        ? 'appdocs:Vault.KDBX'
        : file;

    expect(
      PortablePath.encode(file, docs),
      expected,
      reason:
          'Guards against the override masking a broken platform predicate: '
          'the un-overridden path must agree with the branch the host is on.',
    );
  });
}
