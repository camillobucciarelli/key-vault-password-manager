// spec 008 Gate 1 T111 — the on-device driver.
//
// Runs the eight required harness cases against the REAL filesystem of a real
// target device and emits a schema-valid artifact on stdout. Test
// infrastructure only: no CI job runs this and `flutter test` never collects
// `integration_test/` (AGENTS.md > Testing Guidelines).
//
// Do not invoke this by hand — `tool/run_safety_harness.sh` supplies the
// provenance this artifact is required to carry (git commit, Flutter version,
// the command itself) and captures the emitted artifact into
// `build/safety-evidence/<platform>/`. Run without it and the artifact is
// stamped `unknown`, which the schema rejects as an empty provenance field.
//
// The case bodies live in `tool/safe_vault_writer_harness.dart` and are shared
// with `test/tool/safe_vault_writer_harness_test.dart`, which runs the same
// eight cases on the CI host on every PR. That sharing is the point: this
// driver contributes the device, not the logic.
//
// WHERE IT WRITES. The workspace is a scratch directory under the app's own
// documents root, so on iOS and Android the cases run inside the real app
// container — the same perimeter a real vault lives in, with the real
// container filesystem. No real vault is opened, created or touched.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../tool/safe_vault_writer_harness.dart';
import '../tool/safety_evidence_schema.dart';

// Provenance the device cannot know. `tool/run_safety_harness.sh` passes all
// four; the defaults are deliberately values the schema REFUSES, so an
// artifact produced by a hand-run without provenance can never be filed as
// evidence.
const _commit = String.fromEnvironment('HARNESS_COMMIT');
const _flutterVersion = String.fromEnvironment('HARNESS_FLUTTER_VERSION');
const _command = String.fromEnvironment('HARNESS_COMMAND');
const _filesystem = String.fromEnvironment(
  'HARNESS_FILESYSTEM',
  defaultValue: 'unknown',
);
const _deviceOrRunner = String.fromEnvironment(
  'HARNESS_DEVICE',
  defaultValue: 'unknown',
);

void say(String key, Object? value) {
  // ignore: avoid_print
  print('QA|$key|$value');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('T111 safe vault writer platform harness', () async {
    final startedAt = DateTime.now().toUtc();
    say('PLATFORM', Platform.operatingSystem);
    say('OS_VERSION', Platform.operatingSystemVersion);

    // Under the app documents root, so iOS/Android exercise the real
    // container filesystem rather than a system temp that may be on a
    // different volume with different semantics.
    final docs = await getApplicationDocumentsDirectory();
    final workspace = Directory(
      p.join(docs.path, 'qa_t111_harness_${startedAt.microsecondsSinceEpoch}'),
    );
    await workspace.create(recursive: true);
    // Depth only — AGENTS.md forbids logging a path verbatim, and on a
    // password manager the container path is itself sensitive.
    say('WORKSPACE_DEPTH', p.split(workspace.path).length);

    try {
      final run = await runHarness(workspace, report: say);
      final artifact = buildArtifact(
        run: run,
        platform: Platform.operatingSystem,
        osVersion: Platform.operatingSystemVersion,
        deviceOrRunner: _deviceOrRunner,
        filesystem: _filesystem,
        flutterVersion: _flutterVersion,
        dartVersion: Platform.version,
        commit: _commit,
        command: _command,
        startedAtUtc: startedAt,
        completedAtUtc: DateTime.now().toUtc(),
      );

      say('STATUS', artifact['status']);
      say('CASES_PASSED', run.cases.where((c) => c.passed).length);
      say('CASES_TOTAL', run.cases.length);

      // Emitted BEFORE any assertion, so a `failed` artifact — the outcome
      // this gate most needs to be able to file — still reaches the runner
      // instead of being lost to a thrown expectation.
      // ignore: avoid_print
      print(encodeArtifactLine(artifact));

      // The run is reported, not judged, here: a platform that genuinely
      // cannot hold the writer's contract must produce a `failed` artifact
      // and a green harness, because that IS the finding. Only a harness that
      // could not produce a filable artifact at all is an error.
      final violations = validateArtifact(artifact);
      expect(
        violations,
        isEmpty,
        reason:
            'the harness assembled an artifact the Gate 0 schema rejects, so '
            'this run cannot be filed as evidence either way: '
            '${violations.join('; ')}',
      );
      expect(
        artifact['platform'],
        Platform.operatingSystem,
        reason: 'an artifact may only ever qualify the platform it ran on',
      );
    } finally {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    }
  });
}
