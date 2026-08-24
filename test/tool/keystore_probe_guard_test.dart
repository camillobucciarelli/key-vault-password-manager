// spec 011 constitution principle I — the keystore probe may not leak a
// master password and may not exist in a release build.
//
// `integration_test/master_password_keystore_qa_test.dart` argues both
// properties structurally. An argument in a comment decays; these tests are
// the machine-checked version, and they run in the ordinary suite on every PR.
//
// What is being defended: the alternative design considered for this probe was
// a build-flavor-gated debug SCREEN inside `lib/`. That would have put a
// keystore reader on the release surface and made "is it gated correctly?" a
// permanent review question. These assertions fail the moment somebody starts
// down that road.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final probe = File('integration_test/master_password_keystore_qa_test.dart');
  final runner = File('tool/run_ios_keystore_qa.sh');
  late String source;
  late String runnerSource;

  setUpAll(() {
    expect(
      probe.existsSync(),
      isTrue,
      reason: 'the keystore probe is gone; docs/manual-qa.md still cites it',
    );
    source = probe.readAsStringSync();
    expect(
      runner.existsSync(),
      isTrue,
      reason: 'the cross-process runner is gone; phase pairs are unsafe',
    );
    // Git checks shell scripts out with CRLF on Windows. Compare logical lines.
    runnerSource = runner.readAsLinesSync().join('\n');
  });

  group('the keystore probe cannot print a secret', () {
    test('it never reads a master password VALUE', () {
      // `getMasterPassword` returns the plaintext. The probe must go through
      // `hasStoredMasterPassword`, which returns a bool, so that no code path
      // in it ever holds the secret in the first place.
      expect(
        source.contains('getMasterPassword('),
        isFalse,
        reason:
            'the probe calls getMasterPassword, which returns the plaintext '
            'master password. Use hasStoredMasterPassword (bool) instead: the '
            'probe must never be able to hold the secret.',
      );
    });

    test('it defines exactly two reporters, and neither takes a String', () {
      // A `sayString` would make leaking a secret a one-line mistake instead
      // of a compile error.
      final reporters = RegExp(
        r'^void say\w*\(String key, (\w+) value\)',
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)).toList();

      expect(
        reporters,
        unorderedEquals(<String>['bool', 'int']),
        reason:
            'the probe must expose reporters for bool and int only. A '
            'String-accepting reporter makes `say(key, secret)` compile.',
      );
    });

    test('every print site is inside one of those reporters', () {
      // Two `print(` calls, one per reporter. A third is an unreviewed
      // output path, which is how a key name or a value escapes.
      expect(
        'print('.allMatches(source).length,
        2,
        reason:
            'the probe has a print site outside sayBool/sayInt. All output '
            'must go through the typed reporters.',
      );
    });

    test('it never reports the raw key set', () {
      // `readAll()` is used for `.keys` only, reduced to counts. Printing the
      // set itself would put database ids into a transcript that gets pasted
      // into bug reports.
      expect(
        RegExp(r'say(Bool|Int)\([^)]*\bkeys\b').hasMatch(source),
        isFalse,
        reason: 'the probe reports a key set rather than a count',
      );
    });
  });

  group('the keystore probe is genuinely cross-process', () {
    test('the runner retains the app container between paired phases', () {
      expect(
        RegExp(
          r'^\s+--no-uninstall \\$',
          multiLine: true,
        ).hasMatch(runnerSource),
        isTrue,
        reason:
            'flutter test uninstalls after phase 1 by default, deleting the '
            'vault fixture and registry while iOS retains Keychain entries',
      );
      expect(
        runnerSource.contains('run_phase ac2_unlock\n  run_phase ac2_relaunch'),
        isTrue,
      );
      expect(
        runnerSource.contains('run_phase ac6_seed\n  run_phase ac6_upgrade'),
        isTrue,
      );
    });

    test('phase 2 pins same database identity and a new process', () {
      expect(source.contains('CROSS_PROCESS_MARKER_FOUND'), isTrue);
      expect(source.contains('marker.processId != pid'), isTrue);
      expect(
        source.contains('marker.databaseId == record.databaseId'),
        isTrue,
        reason:
            'registry count alone can accept a newly-created equivalent vault; '
            'AC-2 and AC-6 require the phase-1 database identity',
      );
      expect(source.contains('requirePriorPhase(_ac2Scenario)'), isTrue);
      expect(source.contains('requirePriorPhase(_ac6Scenario)'), isTrue);
    });
  });

  group('the keystore probe cannot reach a release build', () {
    test('it lives under integration_test/, which is never compiled into an '
        'app', () {
      expect(probe.path.startsWith('integration_test/'), isTrue);
    });

    test('nothing in lib/ references it', () {
      // The failure mode this guards: somebody "promotes" the probe into a
      // debug screen so it can be used without a test runner, and the gating
      // becomes a build-configuration question forever after.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('master_password_keystore_qa') ||
            text.contains('_KeystoreCensus')) {
          offenders.add(entity.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'the keystore probe has been pulled into lib/, which puts it on '
            'the release surface. It must stay in integration_test/.',
      );
    });

    test('lib/ gained no keystore-enumeration path', () {
      // `readAll()` enumerates every secret the app holds. The probe needs it;
      // production has never needed it, and a call appearing in lib/ is worth
      // a deliberate review rather than a silent merge.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('readAll(')) {
          offenders.add(entity.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'production code now enumerates the whole secure store via '
            'readAll(). If that is deliberate, review it and update this test '
            'with the reason.',
      );
    });
  });
}
