// spec-008 T202/T203/T206 — the redaction gate for the merge domain module.
//
// Structural, not a spot check: the sources are parsed with the real Dart
// analyzer and every declared class, field, getter, static and method is
// judged. The scope comes from `sync_merge_module_registry.dart`, whose
// completeness is enforced by `sync_merge_domain_architecture_test.dart`, so a
// file nobody remembered to add is a failure rather than a blind spot.
//
// Four holes found by an adversarial pass on the first version, all closed
// here and each re-verified against the surviving mutant:
//
//   F1 the scope was a hardcoded literal, so a new file was inspected by
//      nothing -> scope now derives from the registry;
//   F2 the field rules ran on the models file only, so `SyncMergeFailure` —
//      the object that reaches logs and crash telemetry — could carry a master
//      password -> the rules run on every strictly-redacted module file;
//   F3 only `FieldDeclaration` was walked and statics were skipped, so a
//      `String get canonicalPath => value` and a process-wide
//      `static Map<String, String> plaintextByToken` both passed -> getters
//      and statics are walked too;
//   F4 the serializer gate was a six-name blacklist, so
//      `Map<String, dynamic> asTelemetryPayload()` passed -> methods are
//      judged by RETURN TYPE.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/merge_field_display.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_merge_models.dart';
import 'package:path/path.dart' as p;

import '../sync_merge_module_registry.dart';

/// Types a strictly-redacted member may have, on top of every class and enum
/// the module itself declares (those are gated by these same rules).
const _safeMemberTypes = <String>{'int', 'bool', 'int?', 'bool?', 'void'};

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

/// A `List`/`Set` of a safe type is safe; `List<dynamic>` is not. Recursive so
/// the element type is judged by the same rules, never waved through.
bool _isSafeType(String type, Set<String> safeTypes) {
  final t = type.replaceAll(' ', '');
  if (safeTypes.contains(t)) return true;
  final container = RegExp(r'^(List|Set)<(.+)>\??$').firstMatch(t);
  if (container != null) return _isSafeType(container.group(2)!, safeTypes);
  return false;
}

/// A method returning one of these is a serialization/telemetry channel
/// whatever it is called. `toString` is exempt and separately required to be a
/// redacted constant.
bool _isSerializerReturnType(String? returnType) {
  if (returnType == null) return true; // untyped: unknowable, therefore refused
  final t = returnType.replaceAll(' ', '');
  return t.startsWith('Map<') ||
      t.startsWith('List<dynamic>') ||
      t.startsWith('Iterable<dynamic>') ||
      t == 'dynamic' ||
      t == 'Object' ||
      t == 'String';
}

void main() {
  final root = _findProjectRoot();
  final modelsPaths = [
    for (final relative in mergeSafeModelFiles) p.join(root, relative),
  ];
  final displayPaths = [
    for (final relative in mergeTransientFiles) p.join(root, relative),
  ];

  /// Every type the module declares is itself gated, so a member typed by one
  /// is safe.
  Set<String> moduleDeclaredTypes() {
    final names = <String>{};
    for (final relative in mergeModuleFiles) {
      final unit = _parse(p.join(root, relative));
      for (final declaration in unit.declarations) {
        switch (declaration) {
          case ClassDeclaration():
            names.add(declaration.namePart.typeName.lexeme);
          case EnumDeclaration():
            names.add(declaration.namePart.typeName.lexeme);
          case GenericTypeAlias():
            names.add(declaration.name.lexeme);
          default:
            break;
        }
      }
    }
    return names;
  }

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

    test('every field, getter and static in the module has a safe type and a '
        'safe name (F2/F3)', () {
      final safeTypes = {..._safeMemberTypes, ...moduleDeclaredTypes()};
      final violations = <String>[];

      for (final relative in mergeStrictlyRedactedFiles) {
        final unit = _parse(p.join(root, relative));
        final file = p.basename(relative);

        for (final cls in unit.declarations.whereType<ClassDeclaration>()) {
          final className = cls.namePart.typeName.lexeme;

          void judge({
            required String memberName,
            required String? type,
            required bool isStatic,
            required bool isPrivate,
            required String what,
          }) {
            final qualified = '$className.$memberName';
            if (type == null) {
              violations.add('$file: $qualified ($what) has no declared type');
              return;
            }
            if (type == 'String' || type == 'String?') {
              if (!_allowedStringMembers.contains(qualified)) {
                violations.add(
                  '$file: $qualified ($what) is a String; only the three '
                  'shape-validated opaque ids may be String',
                );
              }
              return;
            }
            final staticallyAllowed =
                isStatic &&
                isPrivate &&
                _allowedPrivateStaticTypes.contains(type);
            if (!_isSafeType(type, safeTypes) && !staticallyAllowed) {
              violations.add(
                '$file: $qualified ($what) has unsafe type "$type"',
              );
            }
            if (_secretishName.hasMatch(memberName)) {
              violations.add(
                '$file: $qualified ($what) has a secret-bearing name',
              );
            }
          }

          for (final field in cls.body.members.whereType<FieldDeclaration>()) {
            final type = field.fields.type?.toSource();
            for (final variable in field.fields.variables) {
              final name = variable.name.lexeme;
              judge(
                memberName: name,
                type: type,
                isStatic: field.isStatic,
                isPrivate: name.startsWith('_'),
                what: field.isStatic ? 'static field' : 'field',
              );
            }
          }

          for (final method
              in cls.body.members.whereType<MethodDeclaration>().where(
                (m) => m.isGetter,
              )) {
            final name = method.name.lexeme;
            if (name == 'props' || name == 'hashCode') continue;
            judge(
              memberName: name,
              type: method.returnType?.toSource(),
              isStatic: method.isStatic,
              isPrivate: name.startsWith('_'),
              what: 'getter',
            );
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
      'no member of the module can serialize, judged by return type (F4)',
      () {
        final violations = <String>[];

        for (final relative in mergeModuleFiles) {
          final unit = _parse(p.join(root, relative));
          final file = p.basename(relative);

          for (final cls in unit.declarations.whereType<ClassDeclaration>()) {
            final className = cls.namePart.typeName.lexeme;

            for (final method
                in cls.body.members.whereType<MethodDeclaration>()) {
              final name = method.name.lexeme;
              if (name == 'toString' || method.isGetter || method.isSetter) {
                continue;
              }
              if (_isSerializerReturnType(method.returnType?.toSource())) {
                violations.add(
                  '$file: $className.$name returns '
                  '"${method.returnType?.toSource() ?? '<untyped>'}" — a '
                  'serialization/telemetry channel',
                );
              }
            }

            for (final ctor
                in cls.body.members.whereType<ConstructorDeclaration>()) {
              final name = ctor.name?.lexeme;
              if (name != null &&
                  (name.startsWith('from') || name.contains('Json'))) {
                violations.add('$file: $className.$name is a deserializer');
              }
            }
          }
        }

        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );
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
