import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../../tool/safety_evidence_schema.dart';

// =============================================================================
// spec 008 Gate 0 (T006) — filesystem harness definition and artifact schema.
//
// SCOPE: definition only. Gate 0 defines WHAT a per-platform atomicity
// artifact must contain and WHICH failure/interruption cases the harness must
// cover. It deliberately executes nothing on any target platform — that is
// Gate 1 T111, whose runner is
// `integration_test/safe_vault_writer_harness_test.dart` driven by
// `tool/run_safety_harness.sh`.
//
// The schema itself now lives in `tool/safety_evidence_schema.dart` so that
// the runner which PRODUCES artifacts and the gate which JUDGES them cannot
// drift apart. This file keeps every behavioural assertion about it.
//
// Consequently every target platform is recorded `not-run` and the feature
// stays disabled everywhere. The tests below exist to make that state
// machine-checked rather than a promise in a markdown file:
//
//   * the schema validator is exercised against a well-formed sample and
//     against every way an artifact can be malformed;
//   * `no platform artifact exists yet` fails the moment somebody drops an
//     artifact in without updating the report — including one produced by
//     the Gate 1 runner (`tool/run_safety_harness.sh`), which is the
//     intended tripwire, not a bug;
//   * `host platform never qualifies another target` encodes the rule that
//     macOS host evidence is worth exactly one row.
// =============================================================================

void main() {
  group('harness schema', () {
    test('required harness cases are fixed and complete', () {
      // spec FR-9 + report "Required cases".
      expect(requiredHarnessCases, hasLength(8));
      expect(requiredHarnessCases.toSet(), hasLength(8));
      expect(requiredHarnessCases, const <String>[
        'backup_same_microsecond_collision',
        'backup_preexisting_name_collision',
        'backup_create_failure',
        'backup_write_flush_verify_failure',
        'target_short_write_failure',
        'target_flush_failure',
        'target_rename_failure',
        'interruption_before_and_after_replace_dispatch',
      ]);
    });

    test('a well-formed artifact validates', () {
      expect(validateArtifact(_sampleArtifact()), isEmpty);
    });

    test('artifact missing a required top-level field is rejected', () {
      for (final field in requiredTopLevelFields) {
        final artifact = _sampleArtifact()..remove(field);
        expect(
          validateArtifact(artifact),
          contains('missing field: $field'),
          reason: '$field must be mandatory',
        );
      }
    });

    test('artifact with an unknown platform is rejected', () {
      final artifact = _sampleArtifact()..['platform'] = 'fuchsia';
      expect(
        validateArtifact(artifact),
        contains('unknown platform: fuchsia'),
      );
    });

    test('artifact missing a required case is rejected', () {
      final artifact = _sampleArtifact();
      (artifact['cases']! as List).removeLast();
      expect(
        validateArtifact(artifact),
        contains(
          'missing case: interruption_before_and_after_replace_dispatch',
        ),
      );
    });

    test('artifact cannot pass while a case failed', () {
      final artifact = _sampleArtifact();
      ((artifact['cases']! as List).first as Map)['passed'] = false;
      expect(
        validateArtifact(artifact),
        contains(
          'status=passed but case failed: '
          'backup_same_microsecond_collision',
        ),
      );
    });

    test('artifact cannot pass with a truncated or missing target', () {
      final artifact = _sampleArtifact();
      ((artifact['cases']! as List).first as Map)['targetState'] = 'missing';
      expect(
        validateArtifact(artifact),
        contains(
          'targetState must be old|new for backup_same_microsecond_collision',
        ),
      );
    });

    test('artifact cannot pass while claiming no atomic replace', () {
      final artifact = _sampleArtifact()..['atomicReplaceOverExisting'] = false;
      expect(
        validateArtifact(artifact),
        contains('status=passed requires atomicReplaceOverExisting=true'),
      );
    });

    test('artifact cannot pass while claiming backup overwrite', () {
      final artifact = _sampleArtifact()..['backupNoOverwrite'] = false;
      expect(
        validateArtifact(artifact),
        contains('status=passed requires backupNoOverwrite=true'),
      );
    });

    test('artifact without provenance is rejected', () {
      // An artifact that cannot be traced to a commit and a command is an
      // assumption, and an assumption may never become `passed`.
      for (final field in const ['commit', 'command', 'logPath']) {
        final artifact = _sampleArtifact()..[field] = '';
        expect(
          validateArtifact(artifact),
          contains('empty provenance field: $field'),
        );
      }
    });

    // A Gate 1 artifact can arrive corrupted or truncated from any of the five
    // target platforms. The validator's contract is to *return* violations, so
    // a wrong type must read as a schema error, never as a thrown cast.
    test('artifact with a non-string provenance field is rejected', () {
      for (final field in const ['commit', 'command', 'logPath']) {
        final artifact = _sampleArtifact()..[field] = 42;
        expect(
          () => validateArtifact(artifact),
          returnsNormally,
          reason: '$field must not throw when it is not a string',
        );
        expect(
          validateArtifact(artifact),
          contains('field must be a string: $field'),
        );
      }
    });

    test('artifact whose cases is not a list is rejected', () {
      final artifact = _sampleArtifact()..['cases'] = 'not-a-list';
      expect(() => validateArtifact(artifact), returnsNormally);
      expect(validateArtifact(artifact), contains('cases must be a list'));
    });

    test('artifact with a non-object case entry is rejected', () {
      // `jsonDecode` yields `List<dynamic>`, so a non-map element is a real
      // shape a Gate 1 artifact can arrive in.
      final artifact = _sampleArtifact()
        ..['cases'] = <dynamic>['not-an-object'];
      expect(() => validateArtifact(artifact), returnsNormally);
      expect(
        validateArtifact(artifact),
        contains('cases[0] must be an object'),
      );
    });

    test('artifact with a non-string case name is rejected', () {
      final artifact = _sampleArtifact();
      ((artifact['cases']! as List)[0] as Map)['name'] = 7;
      expect(() => validateArtifact(artifact), returnsNormally);
      expect(
        validateArtifact(artifact),
        contains('cases[0] name must be a string'),
      );
    });

    test('artifact with duplicate case names is rejected', () {
      // A re-run harness that concatenates its output is the realistic source:
      // without this violation the second copy overwrites the first, and the
      // required-case check still passes while the first copy is never read.
      final artifact = _sampleArtifact();
      final cases = artifact['cases']! as List;
      final duplicated = Map<String, dynamic>.from(
        cases.first as Map<String, dynamic>,
      )..['passed'] = false;
      artifact['cases'] = [...cases, duplicated];

      expect(() => validateArtifact(artifact), returnsNormally);
      expect(
        validateArtifact(artifact),
        contains('duplicate case name: ${requiredHarnessCases.first}'),
      );
    });

    test('a duplicate-case artifact enables nothing', () {
      final artifact = _sampleArtifact();
      final cases = artifact['cases']! as List;
      artifact['cases'] = [...cases, cases.first];
      expect(qualifiedPlatforms(artifact), isEmpty);
    });

    test('a malformed artifact enables nothing', () {
      final artifact = _sampleArtifact()..['cases'] = 'not-a-list';
      expect(qualifiedPlatforms(artifact), isEmpty);
    });
  });

  group('harness platform status', () {
    test('every target platform is not-run and disabled', () {
      for (final platform in targetPlatforms) {
        final status = _platformStatus(platform);
        expect(status.status, 'not-run', reason: platform);
        expect(status.featureEnabled, isFalse, reason: platform);
      }
    });

    test('no platform artifact exists yet', () {
      for (final platform in targetPlatforms) {
        expect(
          File(artifactPath(platform)).existsSync(),
          isFalse,
          reason:
              'an artifact appeared for $platform; Gate 1 T111 must record it '
              'in feasibility-report.md before the feature may enable there',
        );
      }
    });

    test('host platform never qualifies another target', () {
      final macosArtifact = _sampleArtifact()..['platform'] = 'macos';
      expect(validateArtifact(macosArtifact), isEmpty);

      // A passing macOS artifact enables exactly one row.
      expect(qualifiedPlatforms(macosArtifact), const <String>['macos']);
      for (final platform in targetPlatforms.where((p) => p != 'macos')) {
        expect(qualifiedPlatforms(macosArtifact), isNot(contains(platform)));
      }
    });

    test('a failed artifact enables nothing', () {
      final artifact = _sampleArtifact()..['status'] = 'failed';
      expect(qualifiedPlatforms(artifact), isEmpty);
    });

    test('an invalid artifact enables nothing', () {
      final artifact = _sampleArtifact()..remove('flutterVersion');
      expect(validateArtifact(artifact), isNotEmpty);
      expect(qualifiedPlatforms(artifact), isEmpty);
    });

    // A Gate 1 harness can be killed mid-write, so the artifact on disk is not
    // guaranteed to be parseable JSON at all. That must read as a violation,
    // not as an exception out of `jsonDecode`.
    test('a truncated artifact fails with a readable reason', () {
      final status = statusFromArtifactJson('{"platform": "linux", "cas');
      expect(status.status, 'failed');
      expect(status.featureEnabled, isFalse);
      expect(status.reason, contains('not valid JSON'));
    });

    test('a non-JSON artifact fails with a readable reason', () {
      final status = statusFromArtifactJson('harness crashed: signal 9');
      expect(status.status, 'failed');
      expect(status.featureEnabled, isFalse);
      expect(status.reason, contains('not valid JSON'));
    });

    test('an empty artifact fails with a readable reason', () {
      final status = statusFromArtifactJson('');
      expect(status.status, 'failed');
      expect(status.featureEnabled, isFalse);
      expect(status.reason, contains('not valid JSON'));
    });

    // Valid JSON that is not an object: the old cast blew up on these too.
    test('a JSON list artifact fails with a readable reason', () {
      final status = statusFromArtifactJson('[{"platform": "linux"}]');
      expect(status.status, 'failed');
      expect(status.featureEnabled, isFalse);
      expect(status.reason, contains('must be a JSON object'));
    });

    test('a JSON scalar artifact fails with a readable reason', () {
      for (final source in const ['42', '"passed"', 'true', 'null']) {
        final status = statusFromArtifactJson(source);
        expect(status.status, 'failed', reason: source);
        expect(status.featureEnabled, isFalse, reason: source);
        expect(
          status.reason,
          contains('must be a JSON object'),
          reason: source,
        );
      }
    });

    test('a schema-violating artifact fails with a readable reason', () {
      final artifact = _sampleArtifact()..remove('flutterVersion');
      final status = statusFromArtifactJson(jsonEncode(artifact));
      expect(status.status, 'failed');
      expect(status.featureEnabled, isFalse);
      expect(status.reason, contains('flutterVersion'));
    });

    test('a well-formed non-passing artifact reports its status', () {
      final artifact = _sampleArtifact()..['status'] = 'failed';
      final status = statusFromArtifactJson(jsonEncode(artifact));
      expect(status.status, 'failed');
      expect(status.featureEnabled, isFalse);
      expect(status.reason, contains('not passed'));
    });

    test('a well-formed passing artifact enables its platform', () {
      final status = statusFromArtifactJson(jsonEncode(_sampleArtifact()));
      expect(status.status, 'passed');
      expect(status.featureEnabled, isTrue);
      expect(status.reason, isNull);
    });
  });
}

// =============================================================================
// Shape reference for the tests above.
//
// The schema, the required-case list, the target platforms and the validator
// all live in `tool/safety_evidence_schema.dart` — imported above. Only the
// fabricated sample stays here, deliberately: a sample artifact is a shape,
// never evidence, and a library that both defines the rules and can hand out
// a ready-made "passing" artifact is one import away from writing one into
// `build/safety-evidence/`.
// =============================================================================

/// Shape reference only. Fabricated values; this is NOT evidence and is never
/// written to `build/safety-evidence/`.
/// Reads the artifact a Gate 1 run would have left on disk for [platform].
///
/// Test-local rather than shared: the production consumers of the schema are
/// handed a payload they already hold, and a library function that silently
/// reads a well-known path is how "no artifact" and "unreadable artifact"
/// stop being distinguishable at the call site.
PlatformStatus _platformStatus(String platform) {
  final file = File(artifactPath(platform));
  if (!file.existsSync()) {
    return const PlatformStatus('not-run', featureEnabled: false);
  }
  return statusFromArtifactJson(file.readAsStringSync());
}

Map<String, dynamic> _sampleArtifact() => <String, dynamic>{
  'schemaVersion': 1,
  'platform': 'linux',
  'osVersion': 'sample',
  'deviceOrRunner': 'sample',
  'filesystem': 'sample',
  'flutterVersion': 'sample',
  'dartVersion': 'sample',
  'commit': 'sample',
  'command': 'sample',
  'startedAtUtc': '2026-01-01T00:00:00Z',
  'completedAtUtc': '2026-01-01T00:00:01Z',
  'status': 'passed',
  'flushSupported': true,
  'directorySyncSupported': true,
  'atomicReplaceOverExisting': true,
  'backupNoOverwrite': true,
  'cases': [
    for (final name in requiredHarnessCases)
      <String, dynamic>{
        'name': name,
        'injectedFailurePhase': name,
        'oldChecksum': 'sample-old',
        'candidateChecksum': 'sample-candidate',
        'finalChecksum': 'sample-old',
        'backupChecksum': 'sample-old',
        'targetState': 'old',
        'passed': true,
      },
  ],
  'logPath': 'build/safety-evidence/linux/safe-vault-writer.log',
};
