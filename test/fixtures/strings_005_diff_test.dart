// spec-005 T21/AC7: `Empty bin (n)` and the recycle-bin confirm strings are
// byte-identical to the pre-restyle dialog. Same pattern as
// strings_003_diff_test.dart / strings_004_diff_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _sectionToCurrentFiles = <String, List<String>>{
  'vault_recycle_bin.part.dart': [
    'lib/features/password_manager/presentation/screens/vault/vault_recycle_bin.part.dart',
  ],
};

void main() {
  test('every pre-spec-005 recycle-bin literal still appears byte-identical '
      'in the current source', () {
    final projectRoot = _findProjectRoot();
    final fixtureFile = File(
      p.join(projectRoot, 'test', 'fixtures', 'strings_005_before.txt'),
    );
    expect(fixtureFile.existsSync(), isTrue);

    final lines = fixtureFile.readAsLinesSync();
    String? currentSection;
    final missing = <String>[];
    var checked = 0;

    for (final rawLine in lines) {
      final sectionMatch = RegExp(r'^## (.+)$').firstMatch(rawLine);
      if (sectionMatch != null) {
        currentSection = sectionMatch.group(1);
        continue;
      }
      if (rawLine.startsWith('#') || rawLine.trim().isEmpty) {
        continue;
      }
      final section = currentSection;
      if (section == null) {
        continue;
      }
      final files = _sectionToCurrentFiles[section];
      if (files == null) {
        continue;
      }

      final haystack = files
          .map(
            (relative) =>
                File(p.join(projectRoot, relative)).readAsStringSync(),
          )
          .join('\n');
      checked += 1;
      if (!haystack.contains(rawLine)) {
        missing.add('[$section] "$rawLine"');
      }
    }

    expect(
      checked,
      11,
      reason: 'Sanity check: the fixture should have exactly 11 literals.',
    );

    expect(
      missing,
      isEmpty,
      reason:
          'AC7 violation(s) — each of these pre-spec-005 recycle-bin '
          'literals must still exist verbatim:\n${missing.join('\n')}',
    );
  });
}

String _findProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate project root (pubspec.yaml).');
    }
    dir = parent;
  }
}
