// 009 / B001–B002 — app-owned generator settings repository contract.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/repositories/shared_preferences_password_generator_settings_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/password_generator_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = SharedPreferencesPasswordGeneratorSettingsRepository.storageKey;

Future<SharedPreferences> _prefs([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

Map<String, Object?> _storedJson(SharedPreferences prefs) {
  return (jsonDecode(prefs.getString(_key)!) as Map).cast<String, Object?>();
}

String _validJson({int revision = 3, int length = 24}) {
  return jsonEncode({
    'schemaVersion': 1,
    'revision': revision,
    'length': length,
    'includeLowercase': true,
    'includeUppercase': false,
    'includeDigits': true,
    'includeSymbols': false,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('first install', () {
    test(
      'read persists length 16 with all four sets enabled, revision 1',
      () async {
        final prefs = await _prefs();
        final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
          sharedPreferences: prefs,
        );

        final snapshot = await repository.read();

        expect(snapshot, const GeneratorSettingsSnapshot.defaults());
        expect(snapshot.revision, 1);
        expect(snapshot.length, 16);
        expect(snapshot.enabledSetsCount, 4);
        // Persisted once under the versioned key.
        expect(_storedJson(prefs), {
          'schemaVersion': 1,
          'revision': 1,
          'length': 16,
          'includeLowercase': true,
          'includeUppercase': true,
          'includeDigits': true,
          'includeSymbols': true,
        });
      },
    );
  });

  group('read/save/watch', () {
    test('read returns the committed snapshot', () async {
      final prefs = await _prefs({_key: _validJson(revision: 3, length: 24)});
      final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
        sharedPreferences: prefs,
      );

      final snapshot = await repository.read();

      expect(snapshot.revision, 3);
      expect(snapshot.length, 24);
      expect(snapshot.includeUppercase, isFalse);
      expect(snapshot.includeSymbols, isFalse);
    });

    test(
      'save increments revision, persists, and publishes exactly once',
      () async {
        final prefs = await _prefs();
        final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
          sharedPreferences: prefs,
        );
        final loaded = await repository.read();
        final events = <GeneratorSettingsSnapshot>[];
        final subscription = repository.watch().listen(events.add);
        addTearDown(subscription.cancel);

        final committed = await repository.save(
          loaded.copyWith(length: 32, includeSymbols: false),
          expectedRevision: loaded.revision,
        );
        await Future<void>.delayed(Duration.zero);

        expect(committed.revision, loaded.revision + 1);
        expect(committed.length, 32);
        expect(_storedJson(prefs)['revision'], committed.revision);
        expect(_storedJson(prefs)['length'], 32);
        expect(events, [committed], reason: 'consumers update exactly once');
        // Generation snapshots the latest committed revision.
        expect((await repository.read()).revision, committed.revision);
      },
    );

    test(
      'stale-revision save is rejected until reload, no persist, no event',
      () async {
        final prefs = await _prefs();
        final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
          sharedPreferences: prefs,
        );
        final loaded = await repository.read();
        // Concurrent commit bumps the revision under the open draft.
        await repository.save(
          loaded.copyWith(length: 20),
          expectedRevision: loaded.revision,
        );
        final events = <GeneratorSettingsSnapshot>[];
        final subscription = repository.watch().listen(events.add);
        addTearDown(subscription.cancel);

        await expectLater(
          repository.save(
            loaded.copyWith(length: 40),
            expectedRevision: loaded.revision,
          ),
          throwsA(isA<GeneratorSettingsStaleRevisionException>()),
        );
        await Future<void>.delayed(Duration.zero);

        expect(_storedJson(prefs)['length'], 20);
        expect(events, isEmpty);

        // Reload picks up the committed revision; re-apply then succeeds.
        final reloaded = await repository.read();
        final committed = await repository.save(
          reloaded.copyWith(length: 40),
          expectedRevision: reloaded.revision,
        );
        expect(committed.length, 40);
      },
    );

    test('invalid drafts are rejected: range and no enabled set', () async {
      final prefs = await _prefs();
      final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
        sharedPreferences: prefs,
      );
      final loaded = await repository.read();

      for (final draft in [
        loaded.copyWith(length: GeneratorSettingsSnapshot.minLength - 1),
        loaded.copyWith(length: GeneratorSettingsSnapshot.maxLength + 1),
        loaded.copyWith(
          includeLowercase: false,
          includeUppercase: false,
          includeDigits: false,
          includeSymbols: false,
        ),
      ]) {
        await expectLater(
          repository.save(draft, expectedRevision: loaded.revision),
          throwsA(isA<GeneratorSettingsValidationException>()),
        );
      }
      expect(_storedJson(prefs)['revision'], loaded.revision);
    });

    test(
      'failed write keeps last valid snapshot active and publishes nothing',
      () async {
        final prefs = await _prefs();
        var failWrites = false;
        final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
          sharedPreferences: prefs,
          debugWriteOverride: (key, value) async {
            if (failWrites) return false;
            return prefs.setString(key, value);
          },
        );
        final loaded = await repository.read();
        final events = <GeneratorSettingsSnapshot>[];
        final subscription = repository.watch().listen(events.add);
        addTearDown(subscription.cancel);

        failWrites = true;
        await expectLater(
          repository.save(
            loaded.copyWith(length: 48),
            expectedRevision: loaded.revision,
          ),
          throwsA(isA<GeneratorSettingsWriteException>()),
        );
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty, reason: 'no partial listener update');
        expect((await repository.read()).length, loaded.length);
        expect(_storedJson(prefs)['length'], loaded.length);
      },
    );
  });

  group('corruption fallback (redacted)', () {
    for (final (name, storedValue) in [
      ('malformed JSON', 'not-json{{{'),
      ('wrong top-level type', jsonEncode(['x'])),
      (
        'wrong field types',
        jsonEncode({
          'schemaVersion': 1,
          'revision': 'x',
          'length': '16',
          'includeLowercase': 1,
          'includeUppercase': true,
          'includeDigits': true,
          'includeSymbols': true,
        }),
      ),
      (
        'out-of-range length',
        jsonEncode({
          'schemaVersion': 1,
          'revision': 2,
          'length': 4096,
          'includeLowercase': true,
          'includeUppercase': true,
          'includeDigits': true,
          'includeSymbols': true,
        }),
      ),
      (
        'no enabled set',
        jsonEncode({
          'schemaVersion': 1,
          'revision': 2,
          'length': 16,
          'includeLowercase': false,
          'includeUppercase': false,
          'includeDigits': false,
          'includeSymbols': false,
        }),
      ),
      (
        'unknown extra keys cannot smuggle native/extension overrides',
        jsonEncode({
          'schemaVersion': 1,
          'revision': 2,
          'length': 16,
          'includeLowercase': true,
          'includeUppercase': true,
          'includeDigits': true,
          'includeSymbols': true,
          'extensionOverride': true,
        }),
      ),
    ]) {
      test('$name falls back to persisted defaults', () async {
        final prefs = await _prefs({_key: storedValue});
        final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
          sharedPreferences: prefs,
        );

        final snapshot = await repository.read();

        expect(snapshot, const GeneratorSettingsSnapshot.defaults());
        // Defaults are persisted; the corrupt content is gone and nothing
        // of it survives in storage.
        expect(_storedJson(prefs), {
          'schemaVersion': 1,
          'revision': 1,
          'length': 16,
          'includeLowercase': true,
          'includeUppercase': true,
          'includeDigits': true,
          'includeSymbols': true,
        });
      });
    }
  });

  group('unknown future schema version', () {
    final futureValue = jsonEncode({
      'schemaVersion': 2,
      'revision': 9,
      'length': 20,
      'someFutureField': 'kept-verbatim',
    });

    test('read returns defaults in memory without overwriting', () async {
      final prefs = await _prefs({_key: futureValue});
      final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
        sharedPreferences: prefs,
      );

      final snapshot = await repository.read();

      expect(snapshot, const GeneratorSettingsSnapshot.defaults());
      expect(
        prefs.getString(_key),
        futureValue,
        reason: 'future value must survive a downgrade untouched',
      );
    });

    test('save refuses to overwrite a future version', () async {
      final prefs = await _prefs({_key: futureValue});
      final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
        sharedPreferences: prefs,
      );
      final snapshot = await repository.read();

      await expectLater(
        repository.save(
          snapshot.copyWith(length: 32),
          expectedRevision: snapshot.revision,
        ),
        throwsA(isA<GeneratorSettingsUnsupportedVersionException>()),
      );
      expect(prefs.getString(_key), futureValue);
    });

    test('explicit reset commits defaults with the next revision', () async {
      final prefs = await _prefs({_key: futureValue});
      final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
        sharedPreferences: prefs,
      );
      await repository.read();
      final events = <GeneratorSettingsSnapshot>[];
      final subscription = repository.watch().listen(events.add);
      addTearDown(subscription.cancel);

      final committed = await repository.reset();
      await Future<void>.delayed(Duration.zero);

      expect(committed.length, 16);
      expect(
        committed.revision,
        10,
        reason: 'next revision after the stored future revision 9',
      );
      expect(_storedJson(prefs)['schemaVersion'], 1);
      expect(events, [committed]);
    });
  });

  group('explicit reset', () {
    test(
      'commits defaults through the repository and publishes once',
      () async {
        final prefs = await _prefs({_key: _validJson(revision: 5, length: 40)});
        final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
          sharedPreferences: prefs,
        );
        await repository.read();
        final events = <GeneratorSettingsSnapshot>[];
        final subscription = repository.watch().listen(events.add);
        addTearDown(subscription.cancel);

        final committed = await repository.reset();
        await Future<void>.delayed(Duration.zero);

        expect(committed.revision, 6);
        expect(committed.length, 16);
        expect(committed.enabledSetsCount, 4);
        expect(events, [committed]);
      },
    );
  });

  group('settings ownership', () {
    test(
      'snapshot mirrors PasswordGeneratorOptions for the reused service',
      () {
        final options = const GeneratorSettingsSnapshot.defaults().toOptions();
        expect(options.length, 16);
        expect(options.enabledSetsCount, 4);
      },
    );

    test('stored value never contains secrets or site data fields', () async {
      final prefs = await _prefs();
      final repository = SharedPreferencesPasswordGeneratorSettingsRepository(
        sharedPreferences: prefs,
      );
      final loaded = await repository.read();
      await repository.save(
        loaded.copyWith(length: 21),
        expectedRevision: loaded.revision,
      );

      expect(_storedJson(prefs).keys, {
        'schemaVersion',
        'revision',
        'length',
        'includeLowercase',
        'includeUppercase',
        'includeDigits',
        'includeSymbols',
      });
    });
  });
}
