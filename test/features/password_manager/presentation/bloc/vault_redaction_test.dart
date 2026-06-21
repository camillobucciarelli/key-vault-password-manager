import 'package:equatable/equatable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_state.dart';

void main() {
  const password = 'qa-password-do-not-log';
  const notes = 'qa-notes-do-not-log';
  const customSecret = 'qa-custom-field-do-not-log';
  const otpSecret = 'otpauth://totp/app?secret=QAOTPSECRET';
  late bool previousStringify;

  setUp(() {
    previousStringify = EquatableConfig.stringify;
    EquatableConfig.stringify = true;
  });

  tearDown(() {
    EquatableConfig.stringify = previousStringify;
  });

  group('vault redaction', () {
    test('VaultEntry redacts secrets from toString and props', () {
      final entry = _entry(
        password: password,
        notes: notes,
        customFieldValue: customSecret,
        otpUri: otpSecret,
      );

      expect(entry.toString(), isNot(contains(password)));
      expect(entry.toString(), isNot(contains(notes)));
      expect(entry.toString(), isNot(contains(customSecret)));
      expect(entry.toString(), isNot(contains(otpSecret)));
      expect(entry.toString(), contains('<redacted>'));

      final propsString = entry.props.toString();
      expect(propsString, isNot(contains(password)));
      expect(propsString, isNot(contains(notes)));
      expect(propsString, isNot(contains(customSecret)));
      expect(propsString, isNot(contains(otpSecret)));
    });

    test('VaultEntry equality still includes redacted fields', () {
      expect(_entry(password: 'same'), equals(_entry(password: 'same')));
      expect(
        _entry(password: 'first'),
        isNot(equals(_entry(password: 'second'))),
      );
      expect(_entry(notes: 'first'), isNot(equals(_entry(notes: 'second'))));
      expect(
        _entry(customFieldValue: 'first'),
        isNot(equals(_entry(customFieldValue: 'second'))),
      );
      expect(_entry(otpUri: 'first'), isNot(equals(_entry(otpUri: 'second'))));
    });

    test('sensitive VaultEvents redact secrets without weakening equality', () {
      final create = CreateVaultEntry(
        title: 'Example',
        username: 'alice',
        password: password,
        url: 'https://example.com',
        notes: notes,
        customFields: const [
          VaultCustomField(key: 'apiKey', value: customSecret),
        ],
      );
      final update = UpdateVaultEntry(
        entryId: 'entry-1',
        title: 'Example',
        username: 'alice',
        password: password,
        url: 'https://example.com',
        notes: notes,
        customFields: const [
          VaultCustomField(key: 'apiKey', value: customSecret),
        ],
      );

      for (final event in [create, update]) {
        expect(event.toString(), isNot(contains(password)));
        expect(event.toString(), isNot(contains(notes)));
        expect(event.toString(), isNot(contains(customSecret)));

        final propsString = event.props.toString();
        expect(propsString, isNot(contains(password)));
        expect(propsString, isNot(contains(notes)));
        expect(propsString, isNot(contains(customSecret)));
      }

      expect(
        create,
        isNot(
          equals(
            const CreateVaultEntry(
              title: 'Example',
              username: 'alice',
              password: 'different',
              url: 'https://example.com',
              notes: notes,
            ),
          ),
        ),
      );
      expect(
        update,
        isNot(
          equals(
            const UpdateVaultEntry(
              entryId: 'entry-1',
              title: 'Example',
              username: 'alice',
              password: 'different',
              url: 'https://example.com',
              notes: notes,
            ),
          ),
        ),
      );
    });

    test('VaultState redacts entries in toString and props', () {
      final entry = _entry(
        password: password,
        notes: notes,
        customFieldValue: customSecret,
        otpUri: otpSecret,
      );
      final state = VaultState(
        databasePath: '/tmp/vault.kdbx',
        entries: [entry],
        allEntries: [entry],
        visibleEntries: [entry],
        recycleBinEntries: [entry],
      );

      expect(state.toString(), isNot(contains(password)));
      expect(state.toString(), isNot(contains(notes)));
      expect(state.toString(), isNot(contains(customSecret)));
      expect(state.toString(), isNot(contains(otpSecret)));
      expect(state.toString(), contains('entries: 1'));

      final propsString = state.props.toString();
      expect(propsString, isNot(contains(password)));
      expect(propsString, isNot(contains(notes)));
      expect(propsString, isNot(contains(customSecret)));
      expect(propsString, isNot(contains(otpSecret)));
    });
  });
}

VaultEntry _entry({
  String password = 'password',
  String notes = 'notes',
  String customFieldValue = 'custom-value',
  String? otpUri = 'otpauth://totp/app?secret=DEFAULT',
}) {
  return VaultEntry(
    id: 'entry-1',
    groupId: 'group-1',
    title: 'Example',
    username: 'alice',
    password: password,
    url: 'https://example.com',
    notes: notes,
    customFields: [VaultCustomField(key: 'apiKey', value: customFieldValue)],
    otpUri: otpUri,
  );
}
