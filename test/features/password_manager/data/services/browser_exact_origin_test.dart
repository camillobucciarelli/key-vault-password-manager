import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/browser_exact_origin.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';

/// 009 / A009 — the Dart half of the shared exact-origin contract.
///
/// This suite consumes the very same fixture the Node harness consumes
/// (`desktop/browser_extension/test/fixtures/origin_canonicalization_v1.json`)
/// and asserts every case in it. There is deliberately **no Dart table of
/// expected canonical origins** here: duplicating the vectors is exactly what
/// the task forbids, because two tables drift and the drift is a security hole.
///
/// Two fixture cases cannot be satisfied by `Uri` alone; both are handled
/// explicitly below through [_dartDivergences] rather than skipped, so a
/// regression cannot hide behind "that case is special".
const _fixturePath =
    'desktop/browser_extension/test/fixtures/origin_canonicalization_v1.json';

/// Fixture cases where the Dart helper deliberately diverges from the JS half.
///
/// The value is the error code Dart must return. A divergence is only
/// acceptable when it is *fail-closed*: the Dart side must refuse the input,
/// never accept it with a different canonical form.
///
/// `idna-unicode` — Dart's `Uri` performs no IDNA/punycode conversion; it
/// percent-encodes the UTF-8 bytes instead (`bücher.example` ->
/// `b%C3%BCcher.example`). Implementing UTS-46 here would mean hand-rolling a
/// mapping table whose *failure mode is collapsing two distinct names onto one
/// identity* — the same class of bug `_cleanHost` already is. Refusing the
/// input costs a real but narrow feature gap (a vault entry whose URL field was
/// typed in Unicode never exact-matches) and costs nothing on the page side,
/// because browsers hand out `location.origin` already punycoded. The ASCII
/// form (`idna-ascii`) is fully supported, so the user-visible fix is to store
/// the punycode spelling.
const _dartDivergences = <String, String>{'idna-unicode': 'idna_unsupported'};

void main() {
  final fixture = _loadFixture();
  final cases = fixture.cases;

  group('origin_canonicalization_v1 fixture integrity', () {
    test('version, required ids, and unique ids are as declared', () {
      expect(fixture.version, 1);
      final ids = cases.map((c) => c.id).toList(growable: false);
      expect(ids.toSet().length, ids.length, reason: 'case ids must be unique');
      for (final requiredId in fixture.requiredIds) {
        expect(
          ids,
          contains(requiredId),
          reason: 'required fixture id is missing',
        );
      }
      expect(cases.length, greaterThanOrEqualTo(fixture.requiredIds.length));
    });

    test('every declared divergence names a real case', () {
      for (final id in _dartDivergences.keys) {
        expect(cases.map((c) => c.id), contains(id));
      }
    });
  });

  group('canonicalizeBrowserExactOrigin — every fixture case', () {
    for (final testCase in cases) {
      test(testCase.id, () {
        final result = canonicalizeBrowserExactOrigin(testCase.input);
        final divergence = _dartDivergences[testCase.id];

        if (divergence != null) {
          // Fail closed, and loudly: a divergence that silently produced some
          // other canonical origin would be far worse than a refusal.
          expect(
            result.ok,
            isFalse,
            reason: 'declared divergence must be refused, never reinterpreted',
          );
          expect(result.error, divergence);
          return;
        }

        if (!testCase.valid) {
          expect(result.ok, isFalse);
          expect(result.error, testCase.error);
          expect(result.origin, isNull);
          return;
        }

        expect(result.ok, isTrue, reason: 'expected a valid origin');
        expect(result.origin!.serialized, testCase.canonicalOrigin);
        expect(result.origin!.effectivePort, testCase.effectivePort);
        expect(
          browserExactOriginOrNull(testCase.input),
          testCase.canonicalOrigin,
        );
      });
    }
  });

  group('fixture equality and distinctness groups', () {
    for (final group in fixture.equalGroups) {
      test('equal: ${group.id}', () {
        final inputs = group.caseIds.map((id) => _caseById(cases, id));
        final divergent = inputs.where(
          (c) => _dartDivergences.containsKey(c.id),
        );
        final comparable = inputs.where(
          (c) => !_dartDivergences.containsKey(c.id),
        );
        // A divergent member is refused, so it is equal to nothing — assert
        // that rather than quietly dropping it from the group.
        for (final testCase in divergent) {
          for (final other in comparable) {
            expect(
              browserExactOriginsEqual(testCase.input, other.input),
              isFalse,
            );
          }
        }
        final serialized = comparable
            .map((c) => browserExactOriginOrNull(c.input))
            .toSet();
        expect(serialized, hasLength(1), reason: group.reason);
        expect(serialized.single, isNotNull);
      });
    }

    for (final group in fixture.distinctGroups) {
      test('distinct: ${group.id}', () {
        final serialized = group.caseIds
            .map((id) => browserExactOriginOrNull(_caseById(cases, id).input))
            .toList(growable: false);
        expect(serialized, everyElement(isNotNull));
        expect(
          serialized.toSet(),
          hasLength(serialized.length),
          reason: group.reason,
        );
        for (var i = 0; i < serialized.length; i += 1) {
          for (var j = i + 1; j < serialized.length; j += 1) {
            expect(
              browserExactOriginsEqual(serialized[i], serialized[j]),
              isFalse,
              reason: group.reason,
            );
          }
        }
      });
    }
  });

  group('exact-origin authorization is not the popup reveal policy', () {
    test('exactOrigin identifier authorizes its own origin only', () {
      final identifiers = _identifiersFor('https://example.com:8443/login');
      expect(
        isExactOriginAuthorized(
          serviceIdentifiers: identifiers,
          origin: 'https://example.com:8443',
        ),
        isTrue,
      );
      for (final other in const [
        'http://example.com:8443',
        'https://example.com',
        'https://example.com:8444',
        'https://example.com.evil.test:8443',
      ]) {
        expect(
          isExactOriginAuthorized(
            serviceIdentifiers: identifiers,
            origin: other,
          ),
          isFalse,
          reason: '$other must not be authorized',
        );
      }
    });

    test('implicit and explicit default ports authorize each other', () {
      final identifiers = _identifiersFor('https://example.com:443/login');
      expect(
        isExactOriginAuthorized(
          serviceIdentifiers: identifiers,
          origin: 'https://example.com',
        ),
        isTrue,
      );
    });

    test(
      'no http -> https upgrade on the overlay path, unlike the popup policy',
      () {
        final identifiers = _identifiersFor('http://example.com/login');
        // The popup policy (#39) allows this widening. The overlay policy must
        // not: the two rules are deliberately different.
        expect(
          DesktopBrowserAutofillMetadataMapper.isRevealAuthorizedOrigin(
            serviceIdentifiers: identifiers,
            origin: 'https://example.com',
          ),
          isTrue,
          reason: 'popup policy is unchanged',
        );
        expect(
          isExactOriginAuthorized(
            serviceIdentifiers: identifiers,
            origin: 'https://example.com',
          ),
          isFalse,
          reason: 'overlay policy is exact-origin only',
        );
      },
    );

    test('domain-only entry is never authorized for fill', () {
      final identifiers = _identifiersFor('example.com');
      expect(
        identifiers.any((i) => i.type == 'domain'),
        isTrue,
        reason: 'still usable as possible metadata',
      );
      expect(
        identifiers.any((i) => i.type == exactOriginServiceIdentifierType),
        isFalse,
      );
      for (final origin in const [
        'https://example.com',
        'http://example.com',
      ]) {
        expect(
          isExactOriginAuthorized(
            serviceIdentifiers: identifiers,
            origin: origin,
          ),
          isFalse,
        );
      }
    });

    test(
      'www./m./mobile. label stripping cannot become fill authorization',
      () {
        for (final label in const ['www', 'm', 'mobile']) {
          final identifiers = _identifiersFor('https://$label.example.com/');
          expect(
            isExactOriginAuthorized(
              serviceIdentifiers: identifiers,
              origin: 'https://$label.example.com',
            ),
            isTrue,
          );
          expect(
            isExactOriginAuthorized(
              serviceIdentifiers: identifiers,
              origin: 'https://example.com',
            ),
            isFalse,
            reason: '$label. is a distinct host and must stay distinct',
          );
          // The bare-host entry must not be filled on the prefixed host either.
          final bare = _identifiersFor('https://example.com/');
          expect(
            isExactOriginAuthorized(
              serviceIdentifiers: bare,
              origin: 'https://$label.example.com',
            ),
            isFalse,
          );
        }
      },
    );

    test('a url identifier alone never authorizes a fill', () {
      // `url` identifiers are produced by `normalizedOrigin`, which routes
      // through `_cleanHost` and has therefore already lost `www.`/`m.`/
      // `mobile.` labels. Only `exactOrigin` identifiers may authorize.
      const identifiers = [
        DesktopBrowserAutofillServiceIdentifier(
          type: 'url',
          value: 'https://example.com',
        ),
        DesktopBrowserAutofillServiceIdentifier(
          type: 'domain',
          value: 'example.com',
        ),
      ];
      expect(
        isExactOriginAuthorized(
          serviceIdentifiers: identifiers,
          origin: 'https://example.com',
        ),
        isFalse,
      );
    });
  });
}

List<DesktopBrowserAutofillServiceIdentifier> _identifiersFor(String url) {
  final metadata = const DesktopBrowserAutofillMetadataMapper().mapEntry(
    VaultEntry(
      id: 'entry-1',
      groupId: 'group-1',
      title: 'Example',
      username: 'alice',
      password: 'test-only-secret',
      url: url,
      notes: '',
    ),
    updatedAtEpochMs: 1,
  );
  return metadata!.serviceIdentifiers;
}

_FixtureCase _caseById(List<_FixtureCase> cases, String id) {
  return cases.firstWhere(
    (c) => c.id == id,
    orElse: () => throw StateError('fixture case $id is missing'),
  );
}

_Fixture _loadFixture() {
  final file = File(_fixturePath);
  if (!file.existsSync()) {
    throw StateError('shared origin fixture not found at $_fixturePath');
  }
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return _Fixture(
    version: decoded['version']! as int,
    requiredIds: (decoded['requiredIds']! as List<Object?>).cast<String>(),
    cases: (decoded['cases']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(_FixtureCase.fromJson)
        .toList(growable: false),
    // A0 added `equalGroups`/`distinctGroups` after the schema in
    // data-model.md was written; read them when present instead of failing on
    // an unknown top-level key.
    equalGroups: _groups(decoded['equalGroups']),
    distinctGroups: _groups(decoded['distinctGroups']),
  );
}

List<_FixtureGroup> _groups(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return raw
      .cast<Map<String, Object?>>()
      .map(
        (json) => _FixtureGroup(
          id: json['id']! as String,
          reason: json['reason'] as String? ?? '',
          caseIds: (json['caseIds']! as List<Object?>).cast<String>(),
        ),
      )
      .toList(growable: false);
}

class _Fixture {
  const _Fixture({
    required this.version,
    required this.requiredIds,
    required this.cases,
    required this.equalGroups,
    required this.distinctGroups,
  });

  final int version;
  final List<String> requiredIds;
  final List<_FixtureCase> cases;
  final List<_FixtureGroup> equalGroups;
  final List<_FixtureGroup> distinctGroups;
}

class _FixtureCase {
  const _FixtureCase({
    required this.id,
    required this.input,
    required this.valid,
    required this.canonicalOrigin,
    required this.effectivePort,
    required this.error,
  });

  factory _FixtureCase.fromJson(Map<String, Object?> json) {
    return _FixtureCase(
      id: json['id']! as String,
      input: json['input']! as String,
      valid: json['valid']! as bool,
      canonicalOrigin: json['canonicalOrigin'] as String?,
      effectivePort: json['effectivePort'] as int?,
      error: json['error'] as String?,
    );
  }

  final String id;
  final String input;
  final bool valid;
  final String? canonicalOrigin;
  final int? effectivePort;
  final String? error;
}

class _FixtureGroup {
  const _FixtureGroup({
    required this.id,
    required this.reason,
    required this.caseIds,
  });

  final String id;
  final String reason;
  final List<String> caseIds;
}
