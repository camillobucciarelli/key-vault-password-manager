// spec-006 T0/T8/AC2: browser-setup + settings/master-password copy is
// byte-identical to the pre-restyle screens. Same pattern as
// strings_003/004/005_diff_test.dart. See strings_006_before.txt for the
// note on why this snapshots the *real* pre-restyle strings rather than the
// five Italian strings named in tasks.md (which do not exist in the repo).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _sectionToCurrentFiles = <String, List<String>>{
  'browser_setup_screen.dart': [
    'lib/features/password_manager/presentation/screens/browser_setup_screen.dart',
  ],
  // spec-002 T10: this copy moved from vault_navigation.part.dart to the
  // Settings-owned vault_settings.part.dart. The section key is kept as the
  // pre-restyle label (it names the fixture section, not the current file).
  'vault_navigation.part.dart (settings / master-password)': [
    'lib/features/password_manager/presentation/screens/vault/vault_settings.part.dart',
  ],
};

void main() {
  test('every pre-spec-006 browser-setup / settings literal still appears '
      'byte-identical in the current source', () {
    final projectRoot = _findProjectRoot();
    final fixtureFile = File(
      p.join(projectRoot, 'test', 'fixtures', 'strings_006_before.txt'),
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
      42,
      reason: 'Sanity check: the fixture should have exactly 42 literals.',
    );

    expect(
      missing,
      isEmpty,
      reason:
          'AC2 violation(s) — each of these pre-spec-006 browser-setup / '
          'settings literals must still exist verbatim:\n${missing.join('\n')}',
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
