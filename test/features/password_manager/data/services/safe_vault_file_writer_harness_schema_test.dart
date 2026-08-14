import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// =============================================================================
// spec 008 Gate 0 (T006) — filesystem harness definition and artifact schema.
//
// SCOPE: definition only. Gate 0 defines WHAT a per-platform atomicity
// artifact must contain and WHICH failure/interruption cases the harness must
// cover. It deliberately executes nothing on any target platform — that is
// Gate 1 T111.
//
// Consequently every target platform is recorded `not-run` and the feature
// stays disabled everywhere. The tests below exist to make that state
// machine-checked rather than a promise in a markdown file:
//
//   * the schema validator is exercised against a well-formed sample and
//     against every way an artifact can be malformed;
//   * `no platform artifact exists yet` fails the moment somebody drops an
//     artifact in without updating the report;
//   * `host platform never qualifies another target` encodes the rule that
//     macOS host evidence is worth exactly one row.
// =============================================================================

void main() {
  group('harness schema', () {
    test('required harness cases are fixed and complete', () {
      // spec FR-9 + report "Required cases".
      expect(_requiredHarnessCases, hasLength(8));
      expect(_requiredHarnessCases.toSet(), hasLength(8));
      expect(_requiredHarnessCases, const <String>[
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
      expect(_validateArtifact(_sampleArtifact()), isEmpty);
    });

    test('artifact missing a required top-level field is rejected', () {
      for (final field in _requiredTopLevelFields) {
        final artifact = _sampleArtifact()..remove(field);
        expect(
          _validateArtifact(artifact),
          contains('missing field: $field'),
          reason: '$field must be mandatory',
        );
      }
    });

    test('artifact with an unknown platform is rejected', () {
      final artifact = _sampleArtifact()..['platform'] = 'fuchsia';
      expect(
        _validateArtifact(artifact),
        contains('unknown platform: fuchsia'),
      );
    });

    test('artifact missing a required case is rejected', () {
      final artifact = _sampleArtifact();
      (artifact['cases']! as List).removeLast();
      expect(
        _validateArtifact(artifact),
        contains(
          'missing case: interruption_before_and_after_replace_dispatch',
        ),
      );
    });

    test('artifact cannot pass while a case failed', () {
      final artifact = _sampleArtifact();
      ((artifact['cases']! as List).first as Map)['passed'] = false;
      expect(
        _validateArtifact(artifact),
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
        _validateArtifact(artifact),
        contains(
          'targetState must be old|new for backup_same_microsecond_collision',
        ),
      );
    });

    test('artifact cannot pass while claiming no atomic replace', () {
      final artifact = _sampleArtifact()..['atomicReplaceOverExisting'] = false;
      expect(
        _validateArtifact(artifact),
        contains('status=passed requires atomicReplaceOverExisting=true'),
      );
    });

    test('artifact cannot pass while claiming backup overwrite', () {
      final artifact = _sampleArtifact()..['backupNoOverwrite'] = false;
      expect(
        _validateArtifact(artifact),
        contains('status=passed requires backupNoOverwrite=true'),
      );
    });

    test('artifact without provenance is rejected', () {
      // An artifact that cannot be traced to a commit and a command is an
      // assumption, and an assumption may never become `passed`.
      for (final field in const ['commit', 'command', 'logPath']) {
        final artifact = _sampleArtifact()..[field] = '';
        expect(
          _validateArtifact(artifact),
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
          () => _validateArtifact(artifact),
          returnsNormally,
          reason: '$field must not throw when it is not a string',
        );
        expect(
          _validateArtifact(artifact),
          contains('field must be a string: $field'),
        );
      }
    });

    test('artifact whose cases is not a list is rejected', () {
      final artifact = _sampleArtifact()..['cases'] = 'not-a-list';
      expect(() => _validateArtifact(artifact), returnsNormally);
      expect(_validateArtifact(artifact), contains('cases must be a list'));
    });

    test('artifact with a non-object case entry is rejected', () {
      // `jsonDecode` yields `List<dynamic>`, so a non-map element is a real
      // shape a Gate 1 artifact can arrive in.
      final artifact = _sampleArtifact()
        ..['cases'] = <dynamic>['not-an-object'];
      expect(() => _validateArtifact(artifact), returnsNormally);
      expect(
        _validateArtifact(artifact),
        contains('cases[0] must be an object'),
      );
    });

    test('artifact with a non-string case name is rejected', () {
      final artifact = _sampleArtifact();
      ((artifact['cases']! as List)[0] as Map)['name'] = 7;
      expect(() => _validateArtifact(artifact), returnsNormally);
      expect(
        _validateArtifact(artifact),
        contains('cases[0] name must be a string'),
      );
    });

    test('a malformed artifact enables nothing', () {
      final artifact = _sampleArtifact()..['cases'] = 'not-a-list';
      expect(_qualifiedPlatforms(artifact), isEmpty);
    });
  });

  group('harness platform status', () {
    test('every target platform is not-run and disabled', () {
      for (final platform in _targetPlatforms) {
        final status = _platformStatus(platform);
        expect(status.status, 'not-run', reason: platform);
        expect(status.featureEnabled, isFalse, reason: platform);
      }
    });

    test('no platform artifact exists yet', () {
      for (final platform in _targetPlatforms) {
        expect(
          File(_artifactPath(platform)).existsSync(),
          isFalse,
          reason:
              'an artifact appeared for $platform; Gate 1 T111 must record it '
              'in feasibility-report.md before the feature may enable there',
        );
      }
    });

    test('host platform never qualifies another target', () {
      final macosArtifact = _sampleArtifact()..['platform'] = 'macos';
      expect(_validateArtifact(macosArtifact), isEmpty);

      // A passing macOS artifact enables exactly one row.
      expect(_qualifiedPlatforms(macosArtifact), const <String>['macos']);
      for (final platform in _targetPlatforms.where((p) => p != 'macos')) {
        expect(_qualifiedPlatforms(macosArtifact), isNot(contains(platform)));
      }
    });

    test('a failed artifact enables nothing', () {
      final artifact = _sampleArtifact()..['status'] = 'failed';
      expect(_qualifiedPlatforms(artifact), isEmpty);
    });

    test('an invalid artifact enables nothing', () {
      final artifact = _sampleArtifact()..remove('flutterVersion');
      expect(_validateArtifact(artifact), isNotEmpty);
      expect(_qualifiedPlatforms(artifact), isEmpty);
    });
  });
}

// =============================================================================
// Harness definition (Gate 0 output consumed by Gate 1 T111).
// =============================================================================

/// Failure and interruption cases every enabled platform must exercise.
///
/// Each case injects one failure at one phase of the backup/target sequence
/// from spec FR-9 and asserts the target is left either fully old or fully
/// new — never missing and never truncated.
const _requiredHarnessCases = <String>[
  // FR-9 step 2/3: collision-resistant, no-overwrite backup naming.
  'backup_same_microsecond_collision',
  'backup_preexisting_name_collision',
  // FR-9 step 1/4: backup must be created and verified before any target write.
  'backup_create_failure',
  'backup_write_flush_verify_failure',
  // FR-9 step 5: target temp write/flush/replace.
  'target_short_write_failure',
  'target_flush_failure',
  'target_rename_failure',
  // FR-8 lock semantics: pre-boundary abort vs post-boundary bookkeeping.
  'interruption_before_and_after_replace_dispatch',
];

const _targetPlatforms = <String>[
  'android',
  'ios',
  'macos',
  'windows',
  'linux',
];

const _requiredTopLevelFields = <String>[
  'schemaVersion',
  'platform',
  'osVersion',
  'deviceOrRunner',
  'filesystem',
  'flutterVersion',
  'dartVersion',
  'commit',
  'command',
  'startedAtUtc',
  'completedAtUtc',
  'status',
  'flushSupported',
  'directorySyncSupported',
  'atomicReplaceOverExisting',
  'backupNoOverwrite',
  'cases',
  'logPath',
];

String _artifactPath(String platform) =>
    'build/safety-evidence/$platform/safe-vault-writer.json';

class _PlatformStatus {
  const _PlatformStatus(this.status, {required this.featureEnabled});
  final String status;
  final bool featureEnabled;
}

/// Gate 0 state: nothing has been executed on any target, so every platform is
/// `not-run` and the feature is disabled. Gate 1 T111 replaces this by reading
/// real artifacts.
_PlatformStatus _platformStatus(String platform) {
  final file = File(_artifactPath(platform));
  if (!file.existsSync()) {
    return const _PlatformStatus('not-run', featureEnabled: false);
  }
  final artifact = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final valid = _validateArtifact(artifact).isEmpty;
  final passed = valid && artifact['status'] == 'passed';
  return _PlatformStatus(passed ? 'passed' : 'failed', featureEnabled: passed);
}

/// Which platforms a single artifact is allowed to enable: at most its own.
List<String> _qualifiedPlatforms(Map<String, dynamic> artifact) {
  if (_validateArtifact(artifact).isNotEmpty) {
    return const [];
  }
  if (artifact['status'] != 'passed') {
    return const [];
  }
  return [artifact['platform']! as String];
}

/// Returns the list of schema violations; empty means valid.
List<String> _validateArtifact(Map<String, dynamic> artifact) {
  final errors = <String>[];

  for (final field in _requiredTopLevelFields) {
    if (!artifact.containsKey(field)) {
      errors.add('missing field: $field');
    }
  }
  if (errors.isNotEmpty) {
    return errors;
  }

  // Type checks before any cast. A truncated or corrupted artifact must come
  // back as a readable schema violation, never as a stack trace.
  for (final field in const ['commit', 'command', 'logPath']) {
    if (artifact[field] is! String) {
      errors.add('field must be a string: $field');
    }
  }
  final rawCases = artifact['cases'];
  if (rawCases is! List) {
    errors.add('cases must be a list');
  } else {
    for (var i = 0; i < rawCases.length; i++) {
      final entry = rawCases[i];
      if (entry is! Map) {
        errors.add('cases[$i] must be an object');
      } else if (entry['name'] is! String) {
        errors.add('cases[$i] name must be a string');
      }
    }
  }
  if (errors.isNotEmpty) {
    return errors;
  }

  if (artifact['schemaVersion'] != 1) {
    errors.add('unsupported schemaVersion: ${artifact['schemaVersion']}');
  }
  final platform = artifact['platform'];
  if (!_targetPlatforms.contains(platform)) {
    errors.add('unknown platform: $platform');
  }
  final status = artifact['status'];
  if (status != 'passed' && status != 'failed') {
    errors.add('unknown status: $status');
  }

  for (final field in const ['commit', 'command', 'logPath']) {
    if ((artifact[field] as String).trim().isEmpty) {
      errors.add('empty provenance field: $field');
    }
  }

  final cases = artifact['cases']! as List;
  final byName = <String, Map<String, dynamic>>{
    for (final entry in cases.cast<Map<Object?, Object?>>())
      entry['name']! as String: Map<String, dynamic>.from(entry),
  };
  for (final required in _requiredHarnessCases) {
    if (!byName.containsKey(required)) {
      errors.add('missing case: $required');
    }
  }

  if (status == 'passed') {
    for (final field in const [
      'atomicReplaceOverExisting',
      'backupNoOverwrite',
    ]) {
      if (artifact[field] != true) {
        errors.add('status=passed requires $field=true');
      }
    }
    for (final entry in byName.entries) {
      if (entry.value['passed'] != true) {
        errors.add('status=passed but case failed: ${entry.key}');
      }
      final targetState = entry.value['targetState'];
      if (targetState != 'old' && targetState != 'new') {
        errors.add('targetState must be old|new for ${entry.key}');
      }
    }
  }

  return errors;
}

/// Shape reference only. Fabricated values; this is NOT evidence and is never
/// written to `build/safety-evidence/`.
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
    for (final name in _requiredHarnessCases)
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
