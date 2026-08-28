// spec 008 Gate 0/Gate 1 — the safe-vault-writer platform artifact schema.
//
// This file is the SINGLE definition of what a per-platform atomicity
// artifact must contain. Three consumers share it, and that sharing is the
// point:
//
//   * `test/features/password_manager/data/services/
//      safe_vault_file_writer_harness_schema_test.dart` (Gate 0) pins the
//     schema's behaviour — every rejection below is asserted there;
//   * `integration_test/safe_vault_writer_harness_test.dart` (Gate 1 T111)
//     builds an artifact on a real target device and self-validates it
//     before emitting it;
//   * `tool/validate_safety_evidence.dart` re-validates whatever landed in
//     `build/safety-evidence/` from the host.
//
// A second copy of these rules living next to the runner is how a runner
// starts certifying artifacts the gate would reject, so there is exactly one
// copy and the runner imports it. Plain Dart on purpose: no Flutter import,
// so `dart run` can execute the CLI without a device attached.

import 'dart:convert';

/// Failure and interruption cases every enabled platform must exercise.
///
/// Each case injects one failure at one phase of the backup/target sequence
/// from spec FR-9 and asserts the target is left either fully old or fully
/// new — never missing and never truncated.
const requiredHarnessCases = <String>[
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

const targetPlatforms = <String>['android', 'ios', 'macos', 'windows', 'linux'];

const requiredTopLevelFields = <String>[
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

/// Where a [platform]'s artifact is expected, relative to the repository root.
String artifactPath(String platform) =>
    'build/safety-evidence/$platform/safe-vault-writer.json';

/// Where a [platform]'s harness transcript is expected.
String artifactLogPath(String platform) =>
    'build/safety-evidence/$platform/safe-vault-writer.log';

class PlatformStatus {
  const PlatformStatus(
    this.status, {
    required this.featureEnabled,
    this.reason,
  });

  final String status;
  final bool featureEnabled;

  /// Why the artifact was rejected; `null` when there is nothing to report.
  final String? reason;
}

/// Decodes one artifact payload into a platform status.
///
/// Malformed input must come back as a readable `failed`, never as a stack
/// trace — same rule [validateArtifact] already applies to type violations.
/// In Gate 1 T111 these files are written by real harnesses on five platforms,
/// where a truncated or half-flushed artifact is a concrete outcome: a crash
/// here would hide the very evidence the gate exists to collect.
PlatformStatus statusFromArtifactJson(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    return PlatformStatus(
      'failed',
      featureEnabled: false,
      reason: 'artifact is not valid JSON: ${error.message}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    return PlatformStatus(
      'failed',
      featureEnabled: false,
      reason: 'artifact root must be a JSON object, got ${decoded.runtimeType}',
    );
  }
  final violations = validateArtifact(decoded);
  if (violations.isNotEmpty) {
    return PlatformStatus(
      'failed',
      featureEnabled: false,
      reason: 'schema violations: ${violations.join('; ')}',
    );
  }
  if (decoded['status'] != 'passed') {
    return PlatformStatus(
      'failed',
      featureEnabled: false,
      reason: 'artifact status is ${decoded['status']}, not passed',
    );
  }
  return const PlatformStatus('passed', featureEnabled: true);
}

/// Which platforms a single artifact is allowed to enable: at most its own.
List<String> qualifiedPlatforms(Map<String, dynamic> artifact) {
  if (validateArtifact(artifact).isNotEmpty) {
    return const [];
  }
  if (artifact['status'] != 'passed') {
    return const [];
  }
  return [artifact['platform']! as String];
}

/// Returns the list of schema violations; empty means valid.
List<String> validateArtifact(Map<String, dynamic> artifact) {
  final errors = <String>[];

  for (final field in requiredTopLevelFields) {
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
  if (!targetPlatforms.contains(platform)) {
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

  // Keyed by name so the required-case check is a lookup, but a duplicate name
  // must NOT silently overwrite: two same-named cases would leave the earlier
  // one unverified while `missing case:` still passes, letting a concatenated
  // or re-run harness log enable a platform on half-checked evidence.
  final cases = artifact['cases']! as List;
  final byName = <String, Map<String, dynamic>>{};
  for (final entry in cases.cast<Map<Object?, Object?>>()) {
    final name = entry['name']! as String;
    if (byName.containsKey(name)) {
      errors.add('duplicate case name: $name');
      continue;
    }
    byName[name] = Map<String, dynamic>.from(entry);
  }
  for (final required in requiredHarnessCases) {
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

// =============================================================================
// Artifact transport.
//
// The device emits its artifact on stdout because that is the only retrieval
// path that exists identically on all five targets — there is no `adb pull`
// for iOS.
// =============================================================================

/// Marker the runner script greps for. The payload is base64 so that no
/// artifact content can be confused with, or broken up by, ordinary log lines
/// interleaved into the same stdout.
const artifactMarker = 'QA|ARTIFACT_B64|';

String encodeArtifactLine(Map<String, dynamic> artifact) =>
    '$artifactMarker${base64Encode(utf8.encode(jsonEncode(artifact)))}';

/// Inverse of [encodeArtifactLine]; returns `null` when [line] is not one.
Map<String, dynamic>? decodeArtifactLine(String line) {
  final index = line.indexOf(artifactMarker);
  if (index < 0) {
    return null;
  }
  final payload = line.substring(index + artifactMarker.length).trim();
  try {
    final decoded = jsonDecode(utf8.decode(base64Decode(payload)));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
