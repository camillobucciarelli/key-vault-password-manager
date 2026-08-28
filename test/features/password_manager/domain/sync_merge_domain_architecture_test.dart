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
    for (final relative in mergeRegisteredFiles) {
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

    // The name pattern alone was not enough once Phase 3 landed: none of the
    // adapter's own types match it (`KdbxMergeAdapter`, `KdbxPresenceDiff`,
    // `KdbxFieldPresent` all have no `\bMerge[A-Z]` or `SyncMerge` boundary),
    // so a file could name the type that carries decrypted plaintext and count
    // as "not participating in the merge contract". The membership rule is
    // therefore also derived from the SYMBOLS the registered files declare —
    // no hand-maintained second list, so it cannot drift from the code.
    final declaredSymbols = <String>{
      for (final relative in mergeSymbolSourceFiles)
        ..._declaredTopLevelNames(p.join(root, relative)),
    };
    final symbolPattern = RegExp(
      r'\b(' + declaredSymbols.map(RegExp.escape).join('|') + r')\b',
    );

    for (final entry in _dartFilesUnder(p.join(root, 'lib'))) {
      final relative = p.relative(entry.path, from: root).replaceAll(r'\', '/');
      if (mergeRegisteredFiles.contains(relative)) continue;

      final source = entry.readAsStringSync();
      final hits =
          <String>{
                ...mergeIdentifierPattern
                    .allMatches(source)
                    .map((m) => m.group(0)!),
                ...symbolPattern.allMatches(source).map((m) => m.group(0)!),
              }
              .where(
                (id) =>
                    !(nonSpec008MergeIdentifiers[id]?.contains(relative) ??
                        false),
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

  test('the data-layer merge implementation lives in data/ (N7, mirrored)', () {
    // Same reasoning as the domain rule above, in the other direction: a
    // `domain/` file registered into the data bucket would be exempted from
    // every redaction rule by a one-line list edit.
    for (final relative in mergeDataImplementationFiles) {
      expect(
        relative,
        startsWith('lib/features/password_manager/data/'),
        reason:
            '$relative is registered as a data-layer merge file but does not '
            'live under data/. The data bucket is an exemption from the '
            'redaction rules; it must not be reachable from domain/.',
      );
    }
  });

  test('no domain or presentation file reaches the data-layer merge '
      'implementation, transitively (T303 boundary)', () {
    // The adapter owns KdbxFile, Credentials, decrypted values and attachment
    // bytes.
    //
    // This used to match DIRECT imports by basename, and that was launderable
    // in two lines: `data/reexport.dart` containing only
    // `export 'kdbx_merge_adapter.dart';`, plus a domain file importing the
    // re-export. No direct import, no basename match, analyzer clean — and
    // `KdbxFieldPresent.semanticValue`, which is decrypted plaintext, readable
    // from `domain/`. One indirection defeated the whole check.
    //
    // So the check is now over the TRANSITIVE closure of the import/export
    // graph: it asks "can this file reach the adapter at all", which is the
    // question the boundary is actually about. Any chain length, any file name.
    //
    // ONE barrier, and it is argued rather than convenient: the composition
    // root. DI must name `SyncMergeRepositoryImpl` to construct it and
    // presentation must import `injection_container.dart` to resolve services,
    // so `presentation -> injection_container -> di -> impl -> adapter` exists
    // in any app with DI. Dart imports are not transitive for name resolution,
    // so importing the DI module does NOT let a screen name an adapter type —
    // it would need its own import, which this check still catches. The one
    // construct that would republish names through the barrier is `export`,
    // and the test below proves the barrier files contain none.
    final reaching = _filesReaching(
      root,
      mergeDataImplementationFiles.toSet(),
      barriers: mergeCompositionRootFiles.toSet(),
    );
    final offenders = <String>[];

    for (final relative in reaching) {
      if (mergeDataImplementationFiles.contains(relative)) continue;
      final segments = p.split(relative);
      if (segments.contains('domain') || segments.contains('presentation')) {
        offenders.add(relative);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These domain/presentation files can reach the data-layer merge '
          'implementation through some chain of imports or exports, so they '
          'can name its types and read decrypted values (T303):\n'
          '${offenders.map((o) => '  - $o').join('\n')}',
    );
  });

  test('the composition root re-publishes NOTHING — bounded by construction, '
      'not by a list of forbidden constructs', () {
    // The T303 reachability check stops at these files, and the exemption is
    // sound only while a barrier gives its importers no way to name what it
    // imports. The first version of this test checked for `export`, which is
    // one member of a family: a tester walked straight past it with
    //
    //     typedef QaLeakedFieldPresent = KdbxFieldPresent;
    //     KdbxMergeAdapter qaLeakAdapter() => const KdbxMergeAdapter();
    //
    // and read `semanticValue` — decrypted plaintext — from `presentation/`,
    // with `analyze` clean and every T303 test green. A public top-level
    // variable of an adapter type is the same hole again.
    //
    // So the rule is not "these constructs are forbidden" but "these two
    // functions are permitted, and nothing else is" — the Gate 2 lesson, in the
    // one place Gate 2's own judge does not reach. A construct that does not
    // exist yet fails here the first time it is used.
    final dataTypeNames = <String>{
      for (final relative in mergeDataImplementationFiles)
        ..._declaredTopLevelNames(p.join(root, relative)),
    };

    for (final relative in mergeCompositionRootFiles) {
      expect(
        relative,
        startsWith(mergeCompositionRootDirectory),
        reason:
            '$relative is registered as a composition root but does not live '
            'under $mergeCompositionRootDirectory',
      );

      final path = p.join(root, relative);
      final unit = parseString(
        content: File(path).readAsStringSync(),
        path: path,
      ).unit;

      // `export` republishes; `part` moves declarations somewhere this walker
      // never looks. Only `import` and `library` are evaluable here.
      for (final directive in unit.directives) {
        expect(
          directive is ImportDirective || directive is LibraryDirective,
          isTrue,
          reason:
              '$relative declares a ${directive.runtimeType}. A barrier may '
              'only import: anything that republishes or relocates its '
              'declarations reopens the T303 hole.',
        );
      }

      for (final declaration in unit.declarations) {
        if (declaration is FunctionDeclaration) {
          final name = declaration.name.lexeme;
          if (name.startsWith('_')) continue; // unreachable from outside.
          expect(
            mergeCompositionRootPublicNames,
            contains(name),
            reason:
                '$relative declares the public function "$name". A barrier may '
                'declare only $mergeCompositionRootPublicNames.',
          );
          // ...and even an allowlisted name must not carry a data type out
          // through its own signature.
          //
          // Joined with a separator, and each part null-coalesced, because the
          // obvious `'$a$b$c'` form is a **no-op on the return type**: an
          // absent `typeParameters` interpolates as the literal `null`, glued
          // straight onto the type name, so the signature of the real function
          // read `KdbxMergeAdapternull(GetIt sl)` and `\bKdbxMergeAdapter\b`
          // did not match. Parameters stayed covered — they are fenced by
          // parentheses and commas — but the return type is the laundering
          // direction that matters here: a barrier leaks by *returning* the
          // adapter, not by accepting one.
          final signature = [
            declaration.returnType,
            declaration.functionExpression.typeParameters,
            declaration.functionExpression.parameters,
          ].map((node) => node?.toString() ?? '').join(' ');
          for (final type in dataTypeNames) {
            expect(
              RegExp('\\b${RegExp.escape(type)}\\b').hasMatch(signature),
              isFalse,
              reason:
                  '$relative exposes "$type" through the signature of "$name"',
            );
          }
          continue;
        }
        if (declaration is TopLevelVariableDeclaration &&
            declaration.variables.variables.every(
              (variable) => variable.name.lexeme.startsWith('_'),
            )) {
          continue; // private: no importer can name it.
        }
        fail(
          '$relative declares a ${declaration.runtimeType} at top level. A '
          'T303 barrier may declare only '
          '$mergeCompositionRootPublicNames, plus private declarations. This '
          'check refuses what it cannot evaluate: if the construct is '
          'genuinely safe, argue it here rather than widening the rule.',
        );
      }
    }
  });

  test('the data-layer merge implementation imports no presentation code', () {
    final offenders = <String>[];

    for (final relative in mergeDataImplementationFiles) {
      for (final rawUri in importsOf(p.join(root, relative))) {
        final resolved = rawUri.startsWith('package:password_manager/')
            ? 'lib/${rawUri.split('/').skip(1).join('/')}'
            : rawUri.startsWith('package:') || rawUri.startsWith('dart:')
            ? null
            : p
                  .relative(
                    p.normalize(
                      p.join(p.dirname(p.join(root, relative)), rawUri),
                    ),
                    from: root,
                  )
                  .replaceAll(r'\', '/');
        if (resolved != null && p.split(resolved).contains('presentation')) {
          offenders.add('$relative -> $rawUri');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test(
    'Gate 2 is not jumped: no data implementation and no DI binding exists',
    () {
      final offenders = <String>[];

      for (final entry in _dartFilesUnder(p.join(root, 'lib'))) {
        final relative = p
            .relative(entry.path, from: root)
            .replaceAll(r'\', '/');
        if (mergeRegisteredFiles.contains(relative)) continue;
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

/// Every `lib/` file that can reach one of [targets] by following import and
/// export directives, to any depth. Includes [targets] themselves.
///
/// Export edges are followed for the same reason imports are: a re-export makes
/// the target's declarations nameable from the re-exporting library, which is
/// precisely the laundering path this replaced.
Set<String> _filesReaching(
  String root,
  Set<String> targets, {
  Set<String> barriers = const <String>{},
}) {
  // Forward edges file -> its direct import/export targets, then invert.
  final reachedBy = <String, Set<String>>{};
  for (final entry in _dartFilesUnder(p.join(root, 'lib'))) {
    final relative = p.relative(entry.path, from: root).replaceAll(r'\', '/');
    for (final rawUri in importsOf(entry.path)) {
      final resolved = _resolveLibUri(root, relative, rawUri);
      if (resolved != null) {
        (reachedBy[resolved] ??= <String>{}).add(relative);
      }
    }
  }

  final closure = <String>{...targets};
  final queue = [...targets];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    // A barrier is still IN the closure — it does reach the target, and that
    // is correct — but propagation stops there: its importers cannot name what
    // it imports.
    if (barriers.contains(current)) continue;
    for (final importer in reachedBy[current] ?? const <String>{}) {
      if (closure.add(importer)) queue.add(importer);
    }
  }
  return closure;
}

/// Resolves a directive URI to a project-relative `lib/` path, or null when it
/// points outside the project (`dart:`, another package).
String? _resolveLibUri(String root, String fromRelative, String rawUri) {
  if (rawUri.startsWith('dart:')) return null;
  if (rawUri.startsWith('package:')) {
    if (!rawUri.startsWith('package:password_manager/')) return null;
    return 'lib/${rawUri.split('/').skip(1).join('/')}';
  }
  return p
      .relative(
        p.normalize(p.join(p.dirname(p.join(root, fromRelative)), rawUri)),
        from: root,
      )
      .replaceAll(r'\', '/');
}

/// Public top-level names a file declares — every kind, including the ones
/// `declaredTypeNames` deliberately skips, because this drives a completeness
/// check and a completeness check that enumerates what it knows is the hole
/// this module has already been bitten by twice.
Set<String> _declaredTopLevelNames(String path) {
  final unit = parseString(
    content: File(path).readAsStringSync(),
    path: path,
  ).unit;
  final names = <String>{};
  for (final declaration in unit.declarations) {
    switch (declaration) {
      case ClassDeclaration():
        names.add(declaration.namePart.typeName.lexeme);
      case EnumDeclaration():
        names.add(declaration.namePart.typeName.lexeme);
      case ExtensionTypeDeclaration():
        names.add(declaration.namePart.typeName.lexeme);
      case MixinDeclaration():
        names.add(declaration.name.lexeme);
      case GenericTypeAlias():
        names.add(declaration.name.lexeme);
      case ExtensionDeclaration():
        final name = declaration.name?.lexeme;
        if (name != null) names.add(name);
      case FunctionDeclaration():
        names.add(declaration.name.lexeme);
      case TopLevelVariableDeclaration():
        for (final variable in declaration.variables.variables) {
          names.add(variable.name.lexeme);
        }
      default:
        throw StateError(
          'Unhandled top-level declaration ${declaration.runtimeType} in '
          '$path. This walker refuses what it cannot evaluate: add a case '
          'before using the construct in a registered merge file.',
        );
    }
  }
  return names..removeWhere((name) => name.startsWith('_'));
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
