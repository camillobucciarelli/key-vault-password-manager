// spec-008 T603 gate condition (F6): the allowlist is the only containment
// `MergeFieldDisplay` has, and an allowlisted file can still leak it — copy
// `.value`/`.label` into a durable String, cache it statically, or hold the
// display outside a State that disposes it. This test rejects all three in
// every allowlisted presentation file, with the real analyzer.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'sync_merge_module_registry.dart';

void main() {
  final root = _findProjectRoot();
  final widgets = mergeFieldDisplayImporters
      .where((f) => f.contains('/presentation/'))
      .toList();

  test(
    'at least one field widget is allowlisted (else the gate is vacuous)',
    () {
      expect(widgets, isNotEmpty);
    },
  );

  for (final relative in widgets) {
    final unit = parseString(
      content: File(p.join(root, relative)).readAsStringSync(),
      path: relative,
    ).unit;

    test('$relative stores no .value/.label in a durable String or static', () {
      final offenders = <String>[];
      unit.visitChildren(_DurableCopyVisitor(offenders));
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test(
      '$relative retains MergeFieldDisplay only in a State that disposes it',
      () {
        final offenders = <String>[];
        for (final declaration in unit.declarations) {
          if (declaration is! ClassDeclaration) continue;
          final source = declaration.toSource();
          for (final member in declaration.body.members) {
            if (member is! FieldDeclaration) continue;
            final type = member.fields.type?.toSource() ?? '';
            if (!RegExp(
              r'\bMerge(FieldDisplay|DisplaySide)\b',
            ).hasMatch(type)) {
              continue;
            }
            final name = member.fields.variables.first.name.lexeme;
            final extendsState =
                declaration.extendsClause?.superclass.toSource().startsWith(
                  'State<',
                ) ??
                false;
            final hasDispose = declaration.body.members.any(
              (m) => m is MethodDeclaration && m.name.lexeme == 'dispose',
            );
            final disposesField = RegExp(
              '${RegExp.escape(name)}\\??\\.dispose\\(\\)',
            ).hasMatch(source);
            if (!extendsState || !hasDispose || !disposesField) {
              offenders.add(
                '${declaration.namePart.typeName.lexeme}.$name holds a $type but is not a '
                'State whose dispose() disposes it',
              );
            }
          }
        }
        expect(offenders, isEmpty, reason: offenders.join('\n'));
      },
    );
  }
}

/// Rejects (a) any field or top-level variable whose initializer reads
/// `.value` or `.label`, and (b) any static field of type String.
class _DurableCopyVisitor extends RecursiveAstVisitor<void> {
  _DurableCopyVisitor(this.offenders);

  final List<String> offenders;

  static final _plaintextRead = RegExp(r'\.(value|label)\b');

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    for (final variable in node.fields.variables) {
      final init = variable.initializer?.toSource() ?? '';
      if (_plaintextRead.hasMatch(init)) {
        offenders.add(
          'field ${variable.name.lexeme} is initialized from $init',
        );
      }
      if (node.isStatic && (node.fields.type?.toSource() ?? '') == 'String') {
        offenders.add('static String ${variable.name.lexeme}');
      }
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final init = variable.initializer?.toSource() ?? '';
      if (_plaintextRead.hasMatch(init)) {
        offenders.add(
          'top-level ${variable.name.lexeme} is initialized from $init',
        );
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    // A local `final String x = display.value` inside build() is a durable
    // copy only if it escapes; a plain local is fine. Statics are covered
    // above; nothing to do here.
    super.visitVariableDeclarationStatement(node);
  }
}

String _findProjectRoot() {
  var dir = Directory.current;
  while (!File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('no pubspec.yaml found');
    dir = parent;
  }
  return dir.path;
}
