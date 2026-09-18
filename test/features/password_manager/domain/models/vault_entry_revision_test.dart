import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_attachment.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry_revision.dart';

void main() {
  final replacedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);

  VaultEntryRevision revision({
    String title = 'Mail',
    String username = 'ada',
    String password = 'hunter2',
    String url = 'https://mail.example',
    String notes = 'secret notes',
    List<VaultCustomField> customFields = const [],
    List<String> attachmentNames = const [],
    String? otpUri,
    DateTime? at,
  }) {
    return VaultEntryRevision(
      entryId: 'entry-1',
      replacedAt: at ?? replacedAt,
      title: title,
      username: username,
      password: password,
      url: url,
      notes: notes,
      customFields: customFields,
      attachmentNames: attachmentNames,
      otpUri: otpUri,
    );
  }

  VaultEntry entry({
    String title = 'Mail',
    String username = 'ada',
    String password = 'hunter2',
    String url = 'https://mail.example',
    String notes = 'secret notes',
    List<VaultCustomField> customFields = const [],
    List<VaultAttachment> attachments = const [],
    String? otpUri,
  }) {
    return VaultEntry(
      id: 'entry-1',
      groupId: 'group-1',
      title: title,
      username: username,
      password: password,
      url: url,
      notes: notes,
      customFields: customFields,
      attachments: attachments,
      otpUri: otpUri,
    );
  }

  group('T101 redaction', () {
    test('never renders the password in props or toString', () {
      final subject = revision(
        customFields: const [VaultCustomField(key: 'PIN', value: 'hunter2')],
        otpUri: 'otpauth://totp/Mail?secret=hunter2',
      );

      expect(subject.toString(), isNot(contains('hunter2')));
      expect(subject.props.join(' '), isNot(contains('hunter2')));
      expect(subject.toString(), contains('password: <redacted>'));
    });

    test('never renders the notes in props or toString', () {
      final subject = revision(notes: 'recovery codes');

      expect(subject.toString(), isNot(contains('recovery codes')));
      expect(subject.props.join(' '), isNot(contains('recovery codes')));
    });

    test('reports otpUri presence only', () {
      expect(revision(otpUri: null).toString(), contains('otpUri: null'));
      expect(
        revision(otpUri: 'otpauth://totp/Mail?secret=hunter2').toString(),
        contains('otpUri: <redacted>'),
      );
      expect(
        revision(otpUri: 'otpauth://totp/Mail?secret=hunter2').props.join(' '),
        isNot(contains('otpauth')),
      );
    });

    test('redacted values still take part in equality', () {
      expect(revision(password: 'a'), equals(revision(password: 'a')));
      expect(revision(password: 'a'), isNot(equals(revision(password: 'b'))));
      expect(revision(notes: 'a'), isNot(equals(revision(notes: 'b'))));
      expect(
        revision(otpUri: 'otpauth://a'),
        isNot(equals(revision(otpUri: 'otpauth://b'))),
      );
    });
  });

  group('T102 changedFieldsForRevision', () {
    test('a title-only edit reports title and not password', () {
      final changed = changedFieldsForRevision(
        revision: revision(title: 'Old title'),
        currentEntry: entry(title: 'New title'),
      );

      expect(changed, {VaultEntryField.title});
    });

    test('an identical password across two revisions is not reported', () {
      final changed = changedFieldsForRevision(
        revision: revision(username: 'ada'),
        replacedBy: revision(username: 'grace'),
        currentEntry: entry(password: 'something-else-entirely'),
      );

      expect(changed, {VaultEntryField.username});
      expect(changed, isNot(contains(VaultEntryField.password)));
    });

    test('the newest revision is compared against the current entry', () {
      final changed = changedFieldsForRevision(
        revision: revision(password: 'old-password'),
        currentEntry: entry(password: 'new-password'),
      );

      expect(changed, {VaultEntryField.password});
    });

    test('custom fields and the otp derived from them are both reported', () {
      final changed = changedFieldsForRevision(
        revision: revision(
          customFields: const [
            VaultCustomField(key: 'otp', value: 'otpauth://totp/old'),
          ],
          otpUri: 'otpauth://totp/old',
        ),
        currentEntry: entry(
          customFields: const [
            VaultCustomField(key: 'otp', value: 'otpauth://totp/new'),
          ],
          otpUri: 'otpauth://totp/new',
        ),
      );

      expect(changed, {VaultEntryField.customFields, VaultEntryField.otpUri});
    });

    test('custom field order does not count as a change', () {
      final changed = changedFieldsForRevision(
        revision: revision(
          customFields: const [
            VaultCustomField(key: 'a', value: '1'),
            VaultCustomField(key: 'b', value: '2'),
          ],
        ),
        currentEntry: entry(
          customFields: const [
            VaultCustomField(key: 'b', value: '2'),
            VaultCustomField(key: 'a', value: '1'),
          ],
        ),
      );

      expect(changed, isEmpty);
    });

    test('a custom field losing its protection counts as a change', () {
      // spec 023 US1b (T103): same key, same text, only the flag moved.
      final changed = changedFieldsForRevision(
        revision: revision(
          customFields: const [
            VaultCustomField(key: 'Seed', value: 'x', isProtected: true),
          ],
        ),
        currentEntry: entry(
          customFields: const [VaultCustomField(key: 'Seed', value: 'x')],
        ),
      );

      expect(changed, {VaultEntryField.customFields});
    });

    test('an attachment the entry no longer has is reported by name', () {
      final changed = changedFieldsForRevision(
        revision: revision(attachmentNames: const ['key.pem']),
        currentEntry: entry(),
      );

      expect(changed, {VaultEntryField.attachments});
    });

    test('an unchanged revision reports nothing', () {
      expect(
        changedFieldsForRevision(revision: revision(), currentEntry: entry()),
        isEmpty,
      );
    });
  });

  group('VaultEntryRevisionSummary', () {
    test('hasSecretChange follows password and otpUri only', () {
      VaultEntryRevisionSummary summary(Set<VaultEntryField> fields) =>
          VaultEntryRevisionSummary(
            replacedAt: replacedAt,
            changedFields: fields,
          );

      expect(summary({VaultEntryField.password}).hasSecretChange, isTrue);
      expect(summary({VaultEntryField.otpUri}).hasSecretChange, isTrue);
      expect(summary({VaultEntryField.title}).hasSecretChange, isFalse);
      expect(summary(const {}).hasSecretChange, isFalse);
    });
  });
}
