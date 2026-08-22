// spec-008 T202/T203/T206 — the redaction gate for the merge domain module.
//
// Structural, not a spot check: the sources are parsed with the real Dart
// analyzer and every declared class, field, getter, static and method is
// judged. The scope comes from `sync_merge_module_registry.dart`, whose
// completeness is enforced by `sync_merge_domain_architecture_test.dart`, so a
// file nobody remembered to add is a failure rather than a blind spot.
//
// Round 2 closed four holes here (F1 scope from the registry, F2 rules over
// every strict file, F3 getters and statics walked, F4 serializers judged by
// return type). Round 3 found that the walk itself was still an enumeration —
// of declaration KINDS this time — and that the safe-type set wrongly absorbed
// the plaintext bucket. Both are fixed by delegating every judgement to
// `SyncMergeAstGate`, which is **fail-closed**: an unrecognised declaration,
// member, type shape or directive is a violation, not a skip.
//
//   N1 `moduleDeclaredTypes()` included the transient bucket, so a strict-bucket
//      field could be typed `MergeDisplaySide` and hold live plaintext ->
//      the safe STORED set is built from the strict files only, and the judge
//      compares AST names so nullability no longer changes the answer;
//   N2/N3 enums, extensions, extension types, typedefs and mixins were never
//      walked -> all are walked, and anything else fails;
//   N4 a `part` injected declarations invisibly -> parts and exports refused.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/merge_field_display.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_merge_models.dart';
import 'package:path/path.dart' as p;

import '../sync_merge_ast_gate.dart';
import '../sync_merge_module_registry.dart';

/// Scalars a strictly-redacted member may have, on top of the module types the
/// judge is given.
const _safeScalars = <String>{'int', 'bool'};

/// The only `String` members allowed to cross the port, each validated by shape
/// in its own constructor. A fourth row is a review, not an edit.
const _allowedStringMembers = <String>{
  'MergeSessionId.token',
  'MergeDecisionId.token',
  'MergeDatabaseId.value',
};

/// Private statics may additionally be a `RegExp` — the shape validators.
const _allowedPrivateStaticTypes = <String>{'RegExp'};

final _secretishName = RegExp(
  r'path|uuid|checksum|hash|token|secret|password|credential|plaintext|'
  r'bytes|key|value|label|name|title|note|url|username|otp|attachment|'
  r'manifest|generation|reveal',
  caseSensitive: false,
);

void main() {
  final root = _findProjectRoot();
  final modelsPaths = [
    for (final relative in mergeSafeModelFiles) p.join(root, relative),
  ];
  final displayPaths = [
    for (final relative in mergeTransientFiles) p.join(root, relative),
  ];

  CompilationUnit unitFor(String relative) => _parse(p.join(root, relative));

  /// Types the judge may accept in a STORED position.
  ///
  /// Built from the strictly-redacted files only, and with the transient
  /// bucket's own type names subtracted (N1). The transient library is
  /// explicitly exempt from these rules — it is where plaintext lives — so
  /// treating its types as "safe" let `SyncMergeFailure` hold a live
  /// `MergeDisplaySide` and a `List<MergeFieldDisplay>`. That is F2 reopened
  /// through the type system instead of through the file list.
  Set<String> safeStoredTypes() {
    final transient = {
      for (final relative in mergeTransientFiles)
        ...declaredTypeNames(unitFor(relative)),
    };
    final strict = {
      for (final relative in mergeStrictlyRedactedFiles)
        ...declaredTypeNames(unitFor(relative)),
    };
    return {..._safeScalars, ...strict.difference(transient)};
  }

  /// A method may RETURN a transient type — the port's `loadFieldDisplay` is
  /// the whole point of the module — while no field may hold one.
  Set<String> safeReturnedTypes() => {
    ...safeStoredTypes(),
    for (final relative in mergeTransientFiles)
      ...declaredTypeNames(unitFor(relative)),
  };

  SyncMergeAstGate newGate() => SyncMergeAstGate(
    safeStoredTypes: safeStoredTypes(),
    safeReturnedTypes: safeReturnedTypes(),
    // `Equatable` is the redaction-bearing base; `Exception` is a marker
    // interface with no members. Everything else must be a judged module type.
    allowedSupertypes: {'Equatable', 'Exception', ...safeStoredTypes()},
    allowedStringMembers: _allowedStringMembers,
    allowedPrivateStaticTypes: _allowedPrivateStaticTypes,
    secretishName: _secretishName,
  );

  group('safe domain models are redacted by construction', () {
    test('every declared class is Equatable and declares props', () {
      final violations = <String>[];
      for (final cls
          in modelsPaths
              .map(_parse)
              .expand((unit) => unit.declarations)
              .whereType<ClassDeclaration>()) {
        final name = cls.namePart.typeName.lexeme;
        final superName = cls.extendsClause?.superclass.name.lexeme;
        final isEquatable =
            superName == 'Equatable' || superName == 'MergeCommitOutcome';
        if (!isEquatable) {
          violations.add('$name does not extend Equatable');
          continue;
        }
        final declaresProps = cls.body.members
            .whereType<MethodDeclaration>()
            .any((m) => m.isGetter && m.name.lexeme == 'props');
        if (!declaresProps && cls.sealedKeyword == null) {
          violations.add('$name declares no props getter');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('the fail-closed judge accepts every declaration in the module '
        '(N1/N2/N3: unknown construct == violation, not skip)', () {
      final gate = newGate();

      for (final relative in mergeModuleFiles) {
        final unit = unitFor(relative);
        final strict = mergeStrictlyRedactedFiles.contains(relative);
        gate.judgeDirectives(p.basename(relative), unit);
        gate.judgeUnit(p.basename(relative), unit, strict: strict);
      }

      expect(
        gate.violations,
        isEmpty,
        reason:
            'The judge refuses what it cannot evaluate. Either the construct '
            'below is a leak, or the judge needs an explicit rule for it — '
            'it is never waved through:\n'
            '${gate.violations.map((v) => '  - $v').join('\n')}',
      );
    });
  });

  group('MergeFieldDisplay is structurally excluded from state', () {
    late List<ClassDeclaration> displayClasses;

    setUpAll(() {
      displayClasses = displayPaths
          .map(_parse)
          .expand((unit) => unit.declarations)
          .whereType<ClassDeclaration>()
          .toList();
    });

    test('no class is Equatable and none declares props', () {
      final violations = <String>[];
      for (final cls in displayClasses) {
        if (cls.extendsClause != null) {
          violations.add(
            '${cls.namePart.typeName.lexeme} extends '
            '${cls.extendsClause!.superclass.name.lexeme}; the transient '
            'display must extend nothing so it cannot be an Equatable member',
          );
        }
        if (cls.withClause != null || cls.implementsClause != null) {
          violations.add(
            '${cls.namePart.typeName.lexeme} mixes in or implements a type',
          );
        }
        final declaresProps = cls.body.members
            .whereType<MethodDeclaration>()
            .any((m) => m.name.lexeme == 'props');
        if (declaresProps) {
          violations.add('${cls.namePart.typeName.lexeme} declares props');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('every class redacts toString with a literal', () {
      for (final cls in displayClasses) {
        final toStringDecls = cls.body.members
            .whereType<MethodDeclaration>()
            .where((m) => m.name.lexeme == 'toString')
            .toList();
        expect(
          toStringDecls,
          hasLength(1),
          reason: '${cls.namePart.typeName.lexeme} does not override toString',
        );
        final source = toStringDecls.single.toSource();
        expect(
          source,
          contains('<redacted>'),
          reason: '${cls.namePart.typeName.lexeme}.toString is not redacted',
        );
        expect(
          source,
          isNot(contains(r'$')),
          reason:
              '${cls.namePart.typeName.lexeme}.toString interpolates a value '
              'instead of returning a constant literal',
        );
      }
    });

    test('the transient display is not exported by the safe models', () {
      final directives = [
        for (final path in modelsPaths)
          for (final directive in _parse(path).directives)
            if (directive is UriBasedDirective)
              directive.uri.stringValue ?? '<unresolvable>',
      ];
      expect(
        directives,
        isNot(contains(endsWith('merge_field_display.dart'))),
        reason:
            'sync_merge_models.dart must not import or export the transient '
            'display: importing the safe models must not put MergeFieldDisplay '
            'in scope.',
      );
    });
  });

  group('runtime redaction', () {
    test('props and toString of every safe model carry no marker', () {
      const marker = 'CANARY-PLAINTEXT';
      final summary = MergeReviewSummary(
        sessionId: MergeSessionId('ms-${'a' * 32}'),
        databaseId: MergeDatabaseId('registry-id-1'),
        phase: MergeReviewPhase.reviewing,
        decisions: [_decision(0)],
        localOnlyRecordCount: 2,
        remoteOnlyRecordCount: 3,
        oneSidedFieldCount: 4,
      );

      final rendered = [
        summary.toString(),
        summary.props.toString(),
        summary.sessionId.toString(),
        summary.databaseId.toString(),
        summary.decisions.single.toString(),
        const MergeApplied(
          entryCount: 1,
          backupCreated: true,
          uploadState: MergeUploadState.pendingRecovery,
        ).toString(),
        const MergeRejected(
          MergeFailureCode.staleRecoveryLocal,
          localCommitCompleted: true,
        ).toString(),
        const MergeRecoveryOutcome(
          MergeRecoveryDisposition.staleRecoveryLocal,
        ).toString(),
      ].join('\n');

      expect(rendered, isNot(contains(marker)));
      // The opaque ids never print their token either.
      expect(rendered, isNot(contains('a' * 32)));
      expect(rendered, isNot(contains('registry-id-1')));
    });

    test('the transient display never prints its plaintext', () {
      final display = MergeFieldDisplay(
        label: 'Recovery codes',
        local: MergeDisplaySide.present('hunter2'),
        remote: MergeDisplaySide.missing(),
        protected: true,
      );
      expect(display.toString(), 'MergeFieldDisplay(<redacted>)');
      expect(display.local.toString(), 'MergeDisplaySide(<redacted>)');
      expect('$display ${display.local}', isNot(contains('hunter2')));
      expect('$display ${display.local}', isNot(contains('Recovery codes')));
    });

    test('disposal drops the plaintext and a later read throws', () {
      final display = MergeFieldDisplay(
        label: 'Notes',
        local: MergeDisplaySide.present('secret'),
        remote: MergeDisplaySide.present('other'),
        protected: false,
      );
      expect(display.local.value, 'secret');

      display.dispose();

      expect(display.isDisposed, isTrue);
      expect(display.local.isDisposed, isTrue);
      expect(() => display.label, throwsStateError);
      expect(() => display.local.value, throwsStateError);
      expect(() => display.remote.value, throwsStateError);
    });
  });

  group('identifier shape guard', () {
    // F5: this is a TYPO guard, not a security control. It rejects a value
    // handed over in place of an id; it cannot and does not prove the token is
    // unpredictable. Non-derivability is a MINTING requirement, owned by the
    // data layer and tested in Gate 3 (tasks.md T302a). The assertions below
    // state exactly that, including the cases the shape does NOT reject, so
    // nobody reads more into the type than it delivers.
    test('a bare path, UUID or MD5 handed over as an id is rejected', () {
      const candidates = <String>[
        '/Users/me/Vault.kdbx',
        'C:\\vaults\\Vault.kdbx',
        '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
        '3f2504e04f8911d39a0c0305e82c3301', // bare 32-hex: MD5 / UUID shape
        'd41d8cd98f00b204e9800998ecf8427e', // MD5 of the empty input
        'ms-NOTHEX',
        '',
      ];
      for (final candidate in candidates) {
        expect(
          () => MergeSessionId(candidate),
          throwsArgumentError,
          reason: 'accepted "$candidate" as an opaque session id',
        );
        expect(() => MergeDecisionId(candidate), throwsArgumentError);
      }
    });

    test('the shape does NOT prove non-derivability, and says so', () {
      // A prefixed MD5 is 32 lowercase hex and therefore passes. So does hex
      // that decodes straight back to a secret. Recording it as an executable
      // fact stops the contract claiming a guarantee the type does not give.
      expect(
        () => MergeSessionId('ms-d41d8cd98f00b204e9800998ecf8427e'),
        returnsNormally,
      );
      expect(
        () => MergeSessionId('ms-7573657240636f72702e636f6d212121'),
        returnsNormally,
      );
      expect(
        () => MergeDecisionId('md-3f2504e04f8911d39a0c0305e82c3301'),
        returnsNormally,
      );
    });

    test('the rejection message does not echo the rejected value', () {
      try {
        MergeSessionId('/Users/me/Secret Vault.kdbx');
        fail('expected an ArgumentError');
      } on ArgumentError catch (error) {
        expect(error.toString(), isNot(contains('Secret Vault')));
        expect(error.toString(), contains('<redacted>'));
      }
    });

    test('every identifier constructor redacts its rejection message', () {
      // F9 tracked, deliberately NOT asserted here: MergeReviewSummary's count
      // guard still passes the raw value to ArgumentError.value. Asserting it
      // with a numeric count would be vacuous — the value is an int and echoes
      // nothing — so the follow-up is recorded in tasks.md instead of being
      // pinned by a test that cannot fail.
      for (final build in <void Function()>[
        () => MergeSessionId('/Users/me/Secret Vault.kdbx'),
        () => MergeDecisionId('/Users/me/Secret Vault.kdbx'),
        () => MergeDatabaseId('/Users/me/Secret Vault.kdbx'),
      ]) {
        try {
          build();
          fail('expected an ArgumentError');
        } on ArgumentError catch (error) {
          expect(error.toString(), contains('<redacted>'));
          expect(
            error.toString(),
            isNot(contains('Secret Vault')),
            reason: 'the rejected value was echoed: $error',
          );
        }
      }
    });

    test('a database id may not be a filesystem path', () {
      expect(
        () => MergeDatabaseId('/Users/me/Vault.kdbx'),
        throwsArgumentError,
      );
      expect(() => MergeDatabaseId('vault.kdbx'), throwsArgumentError);
      expect(() => MergeDatabaseId('   '), throwsArgumentError);
      expect(MergeDatabaseId('sha256:abc').value, 'sha256:abc');
    });
  });
}

RedactedMergeDecision _decision(int ordinal) => RedactedMergeDecision(
  decisionId: MergeDecisionId('md-${'b' * 32}'),
  ordinal: ordinal,
  kind: MergeDecisionKind.fieldConflict,
  category: MergeFieldCategory.password,
  presence: MergePresence.presentBoth,
  choice: MergeChoice.local,
  isDefault: true,
  timestampRelation: TimestampRelation.localNewer,
);

CompilationUnit _parse(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'missing source: $path');
  return parseString(content: file.readAsStringSync(), path: path).unit;
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
