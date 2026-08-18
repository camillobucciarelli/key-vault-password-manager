import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/portable_path.dart';
import 'package:path/path.dart' as p;

/// Case-folding probes for #43.
///
/// `PortablePath.encode` resolves symlinks before the containment check but
/// used to compare case-sensitively, so `Documents` vs `documents` made
/// `p.isWithin` return false and the path was persisted absolute. That is the
/// #41 bug reintroduced silently: the record works until the iOS container is
/// relocated, then the database reads as missing.
///
/// Note `resolveSymbolicLinksSync` already canonicalizes an *existing* segment
/// to its on-disk spelling, so the divergence only survives for segments that
/// do not exist yet. The tests below therefore build the case difference out of
/// non-existent directories, which is the only way it reaches the comparison.
void main() {
  late Directory tempRoot;
  late String base;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('portable_case_');
    // macOS temp dirs live under a `/var` -> `/private/var` symlink; resolve
    // once up front so the only difference under test is letter case.
    base = tempRoot.resolveSymbolicLinksSync();
  });

  tearDown(() async {
    await tempRoot.delete(recursive: true);
    PortablePath.debugFoldsCaseOverride = null;
  });

  group('case-insensitive filesystem (iOS, macOS, Windows)', () {
    setUp(() => PortablePath.debugFoldsCaseOverride = true);

    test('a case-different documents root still produces appdocs:', () {
      final docs = p.join(base, 'Documents');
      final file = p.join(base, 'documents', 'vault.kdbx');

      expect(PortablePath.encode(file, docs), 'appdocs:vault.kdbx');
    });

    test(
      'the stored value keeps the real spelling, never a lowercased one',
      () {
        final docs = p.join(base, 'Documents');
        final file = p.join(base, 'documents', 'DataBases', 'Vault.KDBX');

        // Only the containment comparison folds case: the relative segments are
        // sliced off the original path, so mixed case survives into storage.
        expect(
          PortablePath.encode(file, docs),
          'appdocs:DataBases/Vault.KDBX',
          reason:
              'A lowercased relative segment would not resolve on a '
              'case-sensitive volume after a cross-platform vault move.',
        );
      },
    );

    test(
      'encode -> decode round-trips to a path that exists on disk',
      () async {
        // Encode BEFORE anything is created, against the documents root
        // spelled the other way. Order matters: `resolveForComparison`
        // canonicalizes the on-disk spelling of segments that already exist,
        // so creating `Documents/` first would make macOS hand back the
        // matching case, the plain `p.isWithin` branch would succeed and this
        // test would still pass with the #43 fold reverted. Encoding against a
        // not-yet-existing tree is the only way the case difference actually
        // reaches `_relativeWithin` on every host.
        final file = p.join(base, 'Documents', 'databases', 'vault.kdbx');
        final stored = PortablePath.encode(file, p.join(base, 'documents'));
        expect(stored, 'appdocs:databases/vault.kdbx');

        await Directory(p.dirname(file)).create(recursive: true);
        await File(file).writeAsBytes(const [1, 2, 3], flush: true);

        final decoded = PortablePath.decode(stored, p.join(base, 'Documents'));
        expect(File(decoded).existsSync(), isTrue);
        expect(decoded, file);
      },
    );

    test('a path genuinely outside the documents root stays absolute', () {
      final docs = p.join(base, 'Documents');
      final file = p.join(base, 'Elsewhere', 'vault.kdbx');

      expect(PortablePath.encode(file, docs), file);
    });
  });

  group('case-sensitive filesystem (Linux, Android)', () {
    setUp(() => PortablePath.debugFoldsCaseOverride = false);

    test('a case-different documents root stays absolute', () {
      final docs = p.join(base, 'Documents');
      final file = p.join(base, 'documents', 'vault.kdbx');

      expect(
        PortablePath.encode(file, docs),
        file,
        reason:
            'These are two different directories here, so folding case would '
            'claim a containment that does not exist and decode would rebuild '
            'a path pointing at the wrong file.',
      );
    });

    test('a matching-case documents root is unaffected', () {
      final docs = p.join(base, 'Documents');
      final file = p.join(base, 'Documents', 'vault.kdbx');

      expect(PortablePath.encode(file, docs), 'appdocs:vault.kdbx');
    });
  });
}
