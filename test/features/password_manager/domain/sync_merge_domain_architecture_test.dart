// spec-008 T206 / constitution principle II — executable layering gate for the
// merge domain contract.
//
// The file list is NOT written here. It comes from
// `sync_merge_module_registry.dart`, and the first test below fails if any file
// in `lib/` participates in the merge contract without being registered — which
// is what makes the other gates apply to files nobody has thought of yet. The
// earlier version hardcoded the list, so a new leaking model in `domain/models/`
// was inspected by nothing and passed the whole suite.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'sync_merge_module_registry.dart';

/// Packages a merge domain file may import. `equatable` is the base the safe
/// models use; nothing else is needed to express the contract.
const _approvedPackages = <String>{'equatable'};

void main() {
  final root = _findProjectRoot();

  test('every registered merge domain file exists', () {
    for (final relative in mergeModuleFiles) {
      expect(
        File(p.join(root, relative)).existsSync(),
        isTrue,
        reason: 'missing $relative',
      );
    }
  });

  test('every registered file lives in the merge domain directory (N7)', () {
    // The layering test judges a registered file's IMPORTS, never its
    // location, so registering a presentation/ or data/ file into a merge
    // bucket used to pass. Membership of a bucket now implies membership of
    // the domain layer.
    for (final relative in mergeModuleFiles) {
      expect(
        relative,
        startsWith(mergeModuleDirectory),
        reason:
            '$relative is registered as a merge module file but does not live '
            'under $mergeModuleDirectory',
      );
    }
  });

  test('the transient bucket is a closed singleton (N5)', () {
    // Bucket 2 is exempt from the field/type/name rules — it is the one place
    // plaintext may live — so it must not be usable as an opt-out. Extending
    // it requires editing this assertion, which is a review, not an edit to a
    // list.
    expect(
      mergeTransientFiles,
      ['lib/features/password_manager/domain/models/merge_field_display.dart'],
      reason:
          'Registering a file in mergeTransientFiles exempts it from the '
          'redaction rules. The bucket is deliberately a closed singleton: '
          'adding to it is a security decision that must be argued, not a '
          'list edit.',
    );
  });

  test('every file participating in the merge contract is registered '
      '(a new merge file cannot escape the gates)', () {
    final unregistered = <String, Set<String>>{};

    for (final entry in _dartFilesUnder(p.join(root, 'lib'))) {
      final relative = p.relative(entry.path, from: root).replaceAll(r'\', '/');
      if (mergeModuleFiles.contains(relative)) continue;

      final hits = mergeIdentifierPattern
          .allMatches(entry.readAsStringSync())
          .map((m) => m.group(0)!)
          .where(
            (id) =>
                !(nonSpec008MergeIdentifiers[id]?.contains(relative) ?? false),
          )
          .toSet();

      if (hits.isNotEmpty) unregistered[relative] = hits;
    }

    expect(
      unregistered,
      isEmpty,
      reason:
          'These files name a spec-008 merge identifier but are not in '
          'sync_merge_module_registry.dart, so none of the redaction or '
          'layering rules were applied to them. Register each one in the '
          'bucket that matches what it is, or stop it naming merge types:\n'
          '${unregistered.entries.map((e) => '  - ${e.key}: ${e.value.join(', ')}').join('\n')}',
    );
  });

  test(
    'no merge domain file imports data/, presentation/, dart:io or Flutter',
    () {
      final violations = <String>[];

      for (final relative in mergeModuleFiles) {
        for (final rawUri in importsOf(p.join(root, relative))) {
          if (rawUri.startsWith('dart:')) {
            if (rawUri == 'dart:io' || rawUri == 'dart:ui') {
              violations.add('$relative -> $rawUri');
            }
            continue;
          }
          if (rawUri.startsWith('package:')) {
            final packageName = rawUri
                .substring('package:'.length)
                .split('/')[0];
            if (packageName == 'password_manager') {
              final resolved = 'lib/${rawUri.split('/').skip(1).join('/')}';
              final violation = _internalViolation(resolved);
              if (violation != null) {
                violations.add('$relative -> $rawUri ($violation)');
              }
              continue;
            }
            if (!_approvedPackages.contains(packageName)) {
              violations.add(
                '$relative -> $rawUri (package not in $_approvedPackages)',
              );
            }
            continue;
          }
          // Relative import.
          final resolved = p.relative(
            p.normalize(p.join(p.dirname(p.join(root, relative)), rawUri)),
            from: root,
          );
          final violation = _internalViolation(resolved.replaceAll(r'\', '/'));
          if (violation != null) {
            violations.add('$relative -> $rawUri ($violation)');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test('the transient field display is imported only by allowlisted files', () {
    // Targets derive from the registry, not from a literal filename: a SECOND
    // transient file used to arrive with no import restriction at all (N5).
    final transientBasenames = [
      for (final relative in mergeTransientFiles) p.basename(relative),
    ];
    final offenders = <String>[];

    for (final entry in _dartFilesUnder(p.join(root, 'lib'))) {
      final relative = p.relative(entry.path, from: root).replaceAll(r'\', '/');
      if (mergeFieldDisplayImporters.contains(relative)) continue;
      final imported = importsOf(
        entry.path,
      ).where((uri) => transientBasenames.any(uri.endsWith));
      if (imported.isNotEmpty) {
        offenders.add('$relative -> ${imported.join(', ')}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'MergeFieldDisplay is the one transient plaintext response; only the '
          'port, its use case and the field widget may name it. Offenders:\n'
          '${offenders.join('\n')}',
    );
  });

  test(
    'Gate 2 is not jumped: no data implementation and no DI binding exists',
    () {
      final offenders = <String>[];

      for (final entry in _dartFilesUnder(p.join(root, 'lib'))) {
        final relative = p
            .relative(entry.path, from: root)
            .replaceAll(r'\', '/');
        if (mergeModuleFiles.contains(relative)) continue;
        final source = entry.readAsStringSync();
        for (final typeName in phase3TypeNames) {
          if (source.contains(typeName)) offenders.add('$relative: $typeName');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Phase 3 (data implementation + DI) must not start before Gate 2 '
            'exits. Offenders:\n${offenders.join('\n')}',
      );
    },
  );
}

Iterable<File> _dartFilesUnder(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

String? _internalViolation(String resolved) {
  final segments = p.split(resolved);
  if (segments.contains('data')) return 'imports data/';
  if (segments.contains('presentation')) return 'imports presentation/';
  if (!resolved.startsWith('lib/features/password_manager/domain/')) {
    return 'outside domain/';
  }
  return null;
}

List<String> importsOf(String path) {
  final content = File(path).readAsStringSync();
  final unit = parseString(content: content, path: path).unit;
  return [
    for (final directive in unit.directives)
      if (directive is ImportDirective || directive is ExportDirective)
        (directive as UriBasedDirective).uri.stringValue ?? '<unresolvable>',
  ];
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
