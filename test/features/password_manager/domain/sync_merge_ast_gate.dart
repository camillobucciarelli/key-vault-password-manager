// spec-008 — the fail-closed AST judge behind the merge domain gates.
//
// **Why this file exists.** Two review rounds killed this gate the same way
// twice: round 1 enumerated *files* (a hardcoded list, so a new file was
// invisible), round 2 enumerated *declaration kinds* (`ClassDeclaration` only,
// so an enum, an extension, an extension type and a typedef were invisible).
// Both are the same defect — a walker that enumerates what it knows and lets
// everything else through. The tester's verdict was that this repeats forever
// until the walker inverts.
//
// So it is inverted here. **Anything the judge does not explicitly know how to
// evaluate is a violation.** A top-level declaration of an unrecognised kind,
// a class member of an unrecognised kind, a type annotation of an unrecognised
// shape and a directive of an unrecognised kind all fail. A Dart construct that
// does not exist yet therefore breaks this gate on the day it is first used,
// which is the intended outcome: a loud failure that a human resolves, rather
// than a silent hole.
//
// The cost is real and accepted: legitimate new constructs need a line here
// before they can be used in the merge module. That is the point.
import 'package:analyzer/dart/ast/ast.dart';

/// A judged violation, already formatted for the failure message.
typedef GateViolation = String;

/// How a type annotation is being used. Stored state is judged strictly;
/// a method's return type is judged slightly more loosely, because the port
/// legitimately returns `Future<MergeFieldDisplay>` while no *field* may hold
/// one.
enum TypePosition { stored, returned }

class SyncMergeAstGate {
  SyncMergeAstGate({
    required this.safeStoredTypes,
    required this.safeReturnedTypes,
    required this.allowedStringMembers,
    required this.allowedPrivateStaticTypes,
    required this.secretishName,
  });

  /// Types a field/getter/representation/typedef may resolve to. Deliberately
  /// EXCLUDES the transient plaintext types: they are not judged by these
  /// rules, so treating them as "safe" would let a strict-bucket field hold
  /// live plaintext (N1).
  final Set<String> safeStoredTypes;

  /// Types a method may return. Includes the transient types.
  final Set<String> safeReturnedTypes;

  /// `Class.member` pairs allowed to be a `String`.
  final Set<String> allowedStringMembers;

  /// Types a *private static* may additionally have (the shape validators).
  final Set<String> allowedPrivateStaticTypes;

  final RegExp secretishName;

  /// Container types whose element types are judged recursively. Anything else
  /// carrying type arguments is refused rather than unwrapped.
  static const _recursedContainers = {'List', 'Set'};
  static const _futureLike = {'Future', 'FutureOr'};

  final _violations = <GateViolation>[];

  List<GateViolation> get violations => List.unmodifiable(_violations);

  void _fail(String where, String message) =>
      _violations.add('$where: $message');

  // ---------------------------------------------------------------- directives

  /// Fail-closed over directives. `part` is refused outright (N4): a
  /// `part of 'sync_merge_models.dart'` file injects public declarations into a
  /// registered library while being invisible to the registry, to the parsed
  /// AST of the registered file and to the import walker. Refusing is chosen
  /// over resolving the part because it needs one rule instead of a second
  /// membership mechanism, and the module has no use for parts.
  ///
  /// `export` is refused for the same family of reasons: it republishes another
  /// library's declarations through a registered file without those
  /// declarations ever being judged.
  void judgeDirectives(String file, CompilationUnit unit) {
    for (final directive in unit.directives) {
      switch (directive) {
        case ImportDirective():
        case LibraryDirective():
          break;
        case PartDirective():
          _fail(
            file,
            'declares a `part`. A part injects public declarations into this '
            'library while escaping the registry and this judge. Inline the '
            'code or register it as its own file.',
          );
        case PartOfDirective():
          _fail(file, 'is a `part of` another library; register it directly.');
        case ExportDirective():
          _fail(
            file,
            'declares an `export`, which republishes unjudged declarations '
            'through a registered file.',
          );
        // ignore: unreachable_switch_default
        default:
          // Unreachable against today's sealed `Directive` hierarchy, and kept
          // deliberately: the day the analyzer adds a directive kind, this
          // becomes reachable and fails instead of letting it through. That is
          // the whole fail-closed premise.
          _fail(
            file,
            'declares an unhandled directive kind '
            '(${directive.runtimeType}). The judge refuses what it cannot '
            'evaluate — add a rule for it.',
          );
      }
    }
  }

  // -------------------------------------------------------------- declarations

  /// Fail-closed over every top-level declaration.
  ///
  /// [strict] selects whether stored state is judged (bucket 1 and 3) or only
  /// the shape rules apply (bucket 2, the transient library, which is the one
  /// place plaintext may live).
  void judgeUnit(String file, CompilationUnit unit, {required bool strict}) {
    for (final declaration in unit.declarations) {
      switch (declaration) {
        case ClassDeclaration():
          _judgeMembers(
            file,
            declaration.namePart.typeName.lexeme,
            declaration.body.members,
            typeParams: _typeParams(declaration.namePart.typeParameters),
            strict: strict,
          );
        case EnumDeclaration():
          // An enum has constructors, fields, getters and methods. The module
          // declares eight of them straight onto the port surface.
          _judgeMembers(
            file,
            declaration.namePart.typeName.lexeme,
            declaration.body.members,
            typeParams: _typeParams(declaration.namePart.typeParameters),
            strict: strict,
          );
        case MixinDeclaration():
          _judgeMembers(
            file,
            declaration.name.lexeme,
            declaration.body.members,
            typeParams: _typeParams(declaration.typeParameters),
            strict: strict,
          );
        case ExtensionDeclaration():
          // An extension bolts members onto a type from OUTSIDE its body, so
          // an unjudged extension can add a plaintext getter to a class this
          // gate has already approved.
          _judgeMembers(
            file,
            'extension ${declaration.name?.lexeme ?? '<unnamed>'}',
            declaration.body.members,
            typeParams: _typeParams(declaration.typeParameters),
            strict: strict,
          );
        case ExtensionTypeDeclaration():
          final name = declaration.primaryConstructor.typeName.lexeme;
          if (strict) {
            // The representation parameter IS the stored state.
            for (final parameter
                in declaration.primaryConstructor.formalParameters.parameters) {
              _judgeRepresentation(file, name, parameter);
            }
          }
          _judgeMembers(
            file,
            name,
            declaration.body.members,
            typeParams: const {},
            strict: strict,
          );
        case GenericTypeAlias():
          if (strict) {
            _judgeType(
              file,
              '${declaration.name.lexeme} (typedef)',
              declaration.type,
              position: TypePosition.stored,
              typeParams: _typeParams(declaration.typeParameters),
              allowString: false,
            );
          }
        case FunctionDeclaration():
          if (strict) {
            _judgeType(
              file,
              '${declaration.name.lexeme} (top-level function)',
              declaration.returnType,
              position: TypePosition.returned,
              typeParams: _typeParams(
                declaration.functionExpression.typeParameters,
              ),
              allowString: false,
            );
          }
        case TopLevelVariableDeclaration():
          if (strict) {
            for (final variable in declaration.variables.variables) {
              _judgeType(
                file,
                '${variable.name.lexeme} (top-level variable)',
                declaration.variables.type,
                position: TypePosition.stored,
                typeParams: const {},
                allowString: false,
              );
            }
          }
        default:
          _fail(
            file,
            'declares an unhandled top-level construct '
            '(${declaration.runtimeType}). The judge refuses what it cannot '
            'evaluate — add a rule for it before using it here.',
          );
      }
    }
  }

  // ------------------------------------------------------------------ members

  void _judgeMembers(
    String file,
    String owner,
    List<ClassMember> members, {
    required Set<String> typeParams,
    required bool strict,
  }) {
    for (final member in members) {
      switch (member) {
        case ConstructorDeclaration():
          final name = member.name?.lexeme;
          if (name != null &&
              (name.startsWith('from') || name.contains('Json'))) {
            _fail(file, '$owner.$name is a deserializer');
          }
        case FieldDeclaration():
          if (!strict) break;
          for (final variable in member.fields.variables) {
            _judgeStoredMember(
              file: file,
              owner: owner,
              name: variable.name.lexeme,
              type: member.fields.type,
              isStatic: member.isStatic,
              typeParams: typeParams,
              what: member.isStatic ? 'static field' : 'field',
            );
          }
        case MethodDeclaration():
          _judgeMethod(
            file: file,
            owner: owner,
            method: member,
            typeParams: {...typeParams, ..._typeParams(member.typeParameters)},
            strict: strict,
          );
        default:
          _fail(
            file,
            '$owner declares an unhandled member kind '
            '(${member.runtimeType}). The judge refuses what it cannot '
            'evaluate.',
          );
      }
    }
  }

  void _judgeMethod({
    required String file,
    required String owner,
    required MethodDeclaration method,
    required Set<String> typeParams,
    required bool strict,
  }) {
    final name = method.name.lexeme;

    if (name == 'toString') return; // separately required to be redacted
    if (name == 'props' || name == 'hashCode') return;

    if (method.isGetter) {
      if (!strict) return;
      _judgeStoredMember(
        file: file,
        owner: owner,
        name: name,
        type: method.returnType,
        isStatic: method.isStatic,
        typeParams: typeParams,
        what: 'getter',
      );
      return;
    }

    if (method.isSetter) {
      if (!strict) return;
      for (final parameter in method.parameters?.parameters ?? const []) {
        _judgeStoredMember(
          file: file,
          owner: owner,
          name: name,
          type: _parameterType(parameter),
          isStatic: method.isStatic,
          typeParams: typeParams,
          what: 'setter parameter',
        );
      }
      return;
    }

    // Ordinary method: judged by RETURN TYPE, so a serialization or telemetry
    // channel is caught whatever it is called.
    _judgeType(
      file,
      '$owner.$name',
      method.returnType,
      position: TypePosition.returned,
      typeParams: typeParams,
      allowString: false,
    );
  }

  void _judgeStoredMember({
    required String file,
    required String owner,
    required String name,
    required TypeAnnotation? type,
    required bool isStatic,
    required Set<String> typeParams,
    required String what,
  }) {
    final qualified = '$owner.$name';
    final allowString = allowedStringMembers.contains(qualified);

    final privateStaticEscape =
        isStatic &&
        name.startsWith('_') &&
        type is NamedType &&
        allowedPrivateStaticTypes.contains(type.name.lexeme);

    if (!privateStaticEscape) {
      _judgeType(
        file,
        '$qualified ($what)',
        type,
        position: TypePosition.stored,
        typeParams: typeParams,
        allowString: allowString,
      );
    }

    if (!allowString && secretishName.hasMatch(name)) {
      _fail(file, '$qualified ($what) has a secret-bearing name');
    }
  }

  void _judgeRepresentation(
    String file,
    String owner,
    FormalParameter parameter,
  ) {
    final name = parameter.name?.lexeme ?? '<unnamed>';
    _judgeStoredMember(
      file: file,
      owner: owner,
      name: name,
      type: _parameterType(parameter),
      isStatic: false,
      typeParams: const {},
      what: 'extension type representation',
    );
  }

  // -------------------------------------------------------------------- types

  /// Fail-closed over type annotations. An unrecognised annotation shape, an
  /// unrecognised name, a function type or a bare generic parameter in a stored
  /// position are all violations.
  void _judgeType(
    String file,
    String where,
    TypeAnnotation? type, {
    required TypePosition position,
    required Set<String> typeParams,
    required bool allowString,
  }) {
    if (type == null) {
      _fail(file, '$where has no declared type; the judge cannot evaluate it');
      return;
    }

    switch (type) {
      case NamedType():
        final name = type.name.lexeme;
        final args = type.typeArguments?.arguments ?? const <TypeAnnotation>[];

        if (name == 'String') {
          if (!allowString) {
            _fail(
              file,
              '$where is a String; only the shape-validated opaque ids may be '
              'String',
            );
          }
          return;
        }

        if (_recursedContainers.contains(name) ||
            (position == TypePosition.returned && _futureLike.contains(name))) {
          if (args.isEmpty) {
            _fail(file, '$where is a raw $name with no element type');
            return;
          }
          for (final arg in args) {
            _judgeType(
              file,
              where,
              arg,
              position: position,
              typeParams: typeParams,
              allowString: false,
            );
          }
          return;
        }

        if (position == TypePosition.returned && name == 'void') return;

        if (typeParams.contains(name)) {
          if (position == TypePosition.returned) return;
          _fail(
            file,
            '$where is the bare type parameter "$name"; a stored member typed '
            'by a type parameter can hold anything',
          );
          return;
        }

        final allowed = position == TypePosition.stored
            ? safeStoredTypes
            : safeReturnedTypes;
        if (!allowed.contains(name)) {
          _fail(file, '$where has unsafe type "${type.toSource()}"');
          return;
        }
        if (args.isNotEmpty) {
          _fail(
            file,
            '$where parameterises "$name", which the judge does not know how '
            'to unwrap',
          );
        }

      case RecordTypeAnnotation():
        for (final field in type.positionalFields) {
          _judgeType(
            file,
            where,
            field.type,
            position: position,
            typeParams: typeParams,
            allowString: false,
          );
        }
        for (final field in type.namedFields?.fields ?? const []) {
          _judgeType(
            file,
            where,
            field.type,
            position: position,
            typeParams: typeParams,
            allowString: false,
          );
        }

      case GenericFunctionType():
        _fail(
          file,
          '$where is a function type; a callable member is a capability handle '
          'that can return anything, including plaintext',
        );

      // ignore: unreachable_switch_default
      default:
        // Same reasoning as the directive switch: unreachable today, retained
        // so a future `TypeAnnotation` subtype fails loudly.
        _fail(
          file,
          '$where has an unhandled type annotation shape '
          '(${type.runtimeType}). The judge refuses what it cannot evaluate.',
        );
    }
  }

  // ------------------------------------------------------------------ helpers

  static Set<String> _typeParams(TypeParameterList? list) => {
    for (final parameter in list?.typeParameters ?? const <TypeParameter>[])
      parameter.name.lexeme,
  };

  static TypeAnnotation? _parameterType(FormalParameter parameter) =>
      parameter.type;
}

/// The names a unit declares, so a member typed by another *judged* type can be
/// accepted. Callers decide which files contribute — the transient library
/// deliberately does not (N1).
Set<String> declaredTypeNames(CompilationUnit unit) {
  final names = <String>{};
  for (final declaration in unit.declarations) {
    switch (declaration) {
      case ClassDeclaration():
        names.add(declaration.namePart.typeName.lexeme);
      case EnumDeclaration():
        names.add(declaration.namePart.typeName.lexeme);
      case ExtensionTypeDeclaration():
        names.add(declaration.primaryConstructor.typeName.lexeme);
      case MixinDeclaration():
        names.add(declaration.name.lexeme);
      case GenericTypeAlias():
        names.add(declaration.name.lexeme);
      default:
        break; // judgeUnit is what refuses unknown kinds; this only names them
    }
  }
  return names;
}
