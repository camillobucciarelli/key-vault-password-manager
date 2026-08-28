// spec 008 Gate 1 T111 — file a harness transcript as platform evidence.
//
// Invoked by `tool/run_safety_harness.sh`; usable by hand on a saved
// transcript. Reads the artifact the device emitted, validates it against the
// SAME schema the Gate 0 test pins, and only then writes it under
// `build/safety-evidence/<platform>/`.
//
// Refusing to file is the important half. An artifact that does not validate
// must never reach the evidence directory, because everything downstream —
// the feasibility report, the platform enablement decision — reads that
// directory and would otherwise be reading something the gate rejects.
//
// Exit codes:
//   0  a `passed` artifact was filed
//   2  a `failed` artifact was filed (a real, recordable finding)
//   1  nothing could be filed (no artifact, or it violates the schema)
//  64  usage error
//
// Pure Dart on purpose: `dart run` with no device and no Flutter binding.

import 'dart:convert';
import 'dart:io';

import 'safety_evidence_schema.dart';

// `exit()` rather than a returned int: the VM IGNORES whatever `main`
// returns, so a `return 1` here would hand the runner script a 0 and every
// refusal below would read as "filed successfully".
Future<void> main(List<String> args) async => exit(await _run(args));

Future<int> _run(List<String> args) async {
  if (args.isEmpty || args.length > 3) {
    stderr.writeln(
      'usage: dart run tool/file_safety_evidence.dart '
      '<transcript> [outRoot] [expectedPlatform]',
    );
    return 64;
  }
  final transcript = File(args[0]);
  final outRoot = args.length > 1 && args[1].trim().isNotEmpty
      ? args[1]
      : 'build/safety-evidence';
  final expectedPlatform = args.length > 2 ? args[2].trim() : '';

  if (!transcript.existsSync()) {
    stderr.writeln('error: transcript not found: ${args[0]}');
    return 64;
  }

  final lines = const LineSplitter().convert(transcript.readAsStringSync());

  // Last one wins: a re-run appended to the same transcript must be filed as
  // the run that actually happened last, not the stale first one.
  Map<String, dynamic>? artifact;
  var seen = 0;
  for (final line in lines) {
    final decoded = decodeArtifactLine(line);
    if (decoded != null) {
      artifact = decoded;
      seen++;
    }
  }

  if (artifact == null) {
    stderr.writeln(
      'error: no artifact in the transcript. The harness did not reach the '
      'point of emitting one, so there is no result to record — that is '
      '"could not run", not "this platform failed".',
    );
    return 1;
  }
  if (seen > 1) {
    stdout.writeln(
      'note: $seen artifacts in the transcript; filing the last one.',
    );
  }

  final violations = validateArtifact(artifact);
  if (violations.isNotEmpty) {
    stderr.writeln('error: the artifact violates the Gate 0 schema:');
    for (final v in violations) {
      stderr.writeln('  - $v');
    }
    stderr.writeln(
      'Nothing was filed. An artifact the gate rejects may not sit in the '
      'evidence directory looking like a result.',
    );
    return 1;
  }

  final platform = artifact['platform']! as String;
  if (expectedPlatform.isNotEmpty && expectedPlatform != platform) {
    stderr.writeln(
      'error: expected a $expectedPlatform artifact but the harness ran on '
      '$platform. Nothing was filed: host evidence never qualifies another '
      'target.',
    );
    return 1;
  }

  final dir = Directory('$outRoot/$platform');
  await dir.create(recursive: true);
  final jsonFile = File('${dir.path}/safe-vault-writer.json');
  final logFile = File('${dir.path}/safe-vault-writer.log');
  await jsonFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(artifact)}\n',
    flush: true,
  );
  await transcript.copy(logFile.path);

  final status = artifact['status'];
  final cases = (artifact['cases']! as List).cast<Map<String, dynamic>>();
  final failed = cases.where((c) => c['passed'] != true).toList();

  stdout
    ..writeln('')
    ..writeln('==> filed $platform evidence: $status')
    ..writeln('    ${jsonFile.path}')
    ..writeln('    ${logFile.path}')
    ..writeln(
      '    cases: ${cases.length - failed.length}/${cases.length} passed',
    )
    ..writeln(
      '    atomicReplaceOverExisting: '
      '${artifact['atomicReplaceOverExisting']}',
    )
    ..writeln('    backupNoOverwrite:         ${artifact['backupNoOverwrite']}')
    ..writeln('    flushSupported:            ${artifact['flushSupported']}')
    ..writeln(
      '    directorySyncSupported:    '
      '${artifact['directorySyncSupported']}',
    );

  for (final c in failed) {
    stdout.writeln('    FAILED ${c['name']}: ${c['detail'] ?? 'no detail'}');
  }

  stdout
    ..writeln('')
    ..writeln(
      'Next: update the $platform row of '
      'specs/008-per-field-conflict-resolution/feasibility-report.md with '
      'this result and the artifact metadata (T111).',
    )
    ..writeln(
      'Note: `flutter test` will now FAIL the Gate 0 assertion "no platform '
      'artifact exists yet" until that row is updated. That tripwire is '
      'deliberate — it is what stops an artifact from enabling a platform '
      'silently.',
    );

  return status == 'passed' ? 0 : 2;
}
