import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/vault_duplicate_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_attachment.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';

void main() {
  late VaultDuplicateService service;

  setUp(() => service = VaultDuplicateService());

  // ── Helper ────────────────────────────────────────────────────────────────

  VaultEntry entry({
    String id = 'id',
    String url = 'https://github.com',
    String username = 'alice',
    String password = 'pw',
    String notes = '',
    String? otpUri,
    List<VaultCustomField> customFields = const [],
    List<VaultAttachment> attachments = const [],
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    final allCustomFields = [
      ...customFields,
      if (otpUri != null) VaultCustomField(key: 'otp', value: otpUri),
    ];
    return VaultEntry(
      id: id,
      groupId: 'g1',
      title: 'Title',
      username: username,
      password: password,
      url: url,
      notes: notes,
      customFields: allCustomFields,
      attachments: attachments,
      otpUri: otpUri,
      updatedAt: updatedAt,
      createdAt: createdAt,
    );
  }

  // ── findDuplicates ────────────────────────────────────────────────────────

  group('findDuplicates', () {
    test('returns empty when no entries', () {
      expect(service.findDuplicates([]), isEmpty);
    });

    test('returns empty when all entries have unique url+username', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'bob', password: 'pw2'),
        entry(id: '3', url: 'https://gitlab.com', username: 'alice', password: 'pw3'),
      ];
      expect(service.findDuplicates(entries), isEmpty);
    });

    test('detects two entries with same url and username as one group', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'alice', password: 'pw2'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
      expect(groups.first.entries, hasLength(2));
    });

    test('normalizes scheme — https and http treated the same', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'alice'),
        entry(id: '2', url: 'http://github.com', username: 'alice', password: 'pw2'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('normalizes www prefix', () {
      final entries = [
        entry(id: '1', url: 'https://www.github.com', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'alice', password: 'pw2'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('strips trailing slash', () {
      final entries = [
        entry(id: '1', url: 'https://github.com/', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'alice', password: 'pw2'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('strips query string and fragment', () {
      final entries = [
        entry(
          id: '1',
          url: 'https://github.com?tab=repos#section',
          username: 'alice',
        ),
        entry(id: '2', url: 'https://github.com', username: 'alice', password: 'pw2'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('normalizes username case and whitespace', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'Alice'),
        entry(id: '2', url: 'https://github.com', username: '  alice  ', password: 'pw2'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('excludes entries with empty URL', () {
      final entries = [
        entry(id: '1', url: '', username: 'alice'),
        entry(id: '2', url: '   ', username: 'alice', password: 'pw2'),
      ];
      expect(service.findDuplicates(entries), isEmpty);
    });

    test('sorts entries newest first within a group', () {
      final old = DateTime(2023, 1, 1);
      final recent = DateTime(2024, 6, 1);
      final entries = [
        entry(
          id: 'old',
          url: 'https://github.com',
          username: 'alice',
          updatedAt: old,
        ),
        entry(
          id: 'new',
          url: 'https://github.com',
          username: 'alice',
          updatedAt: recent,
        ),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups.first.entries.first.id, 'new');
      expect(groups.first.entries.last.id, 'old');
    });

    test('exposes sharedUrl as normalized host+path', () {
      final entries = [
        entry(id: '1', url: 'https://www.GitHub.com/login', username: 'alice'),
        entry(
          id: '2',
          url: 'https://www.github.com/login',
          username: 'alice',
          password: 'pw2',
        ),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups.first.sharedUrl, 'github.com/login');
    });
  });

    test('same username + password across different URLs is one group', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'alice'),
        entry(id: '2', url: 'https://gitlab.com', username: 'alice'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
      expect(groups.first.sharedUrl, isNull);
      expect(groups.first.sharedUsername, 'alice');
      expect(groups.first.urls, ['github.com', 'gitlab.com']);
    });

    test('credentials group collects extra-URL custom fields into urls', () {
      final entries = [
        entry(
          id: '1',
          url: 'https://github.com',
          customFields: [
            const VaultCustomField(key: 'KP2A_URL_1', value: 'https://a.com'),
          ],
        ),
        entry(id: '2', url: 'https://gitlab.com'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups.first.urls, ['github.com', 'a.com', 'gitlab.com']);
    });

    test('same password but different username is not a duplicate', () {
      final entries = [
        entry(id: '1', url: 'https://a.com', username: 'alice'),
        entry(id: '2', url: 'https://b.com', username: 'bob'),
      ];
      expect(service.findDuplicates(entries), isEmpty);
    });

    test('empty username or password never forms a credentials group', () {
      final entries = [
        entry(id: '1', url: 'https://a.com', username: '', password: 'x'),
        entry(id: '2', url: 'https://b.com', username: '', password: 'x'),
        entry(id: '3', url: 'https://c.com', username: 'bob', password: ''),
        entry(id: '4', url: 'https://d.com', username: 'bob', password: ''),
      ];
      expect(service.findDuplicates(entries), isEmpty);
    });

    test('credentials group wins over site group for the same entries', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'alice'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
      expect(groups.first.sharedUrl, isNull);
    });

  // ── previewMerge ──────────────────────────────────────────────────────────

  group('previewMerge', () {
    test('copies notes when primary notes is empty', () {
      final primary = entry(id: 'p', notes: '');
      final secondary = entry(id: 's', notes: 'some notes');
      final preview = service.previewMerge(primary, secondary);
      expect(preview.willCopyNotes, isTrue);
    });

    test('does not copy notes when primary already has notes', () {
      final primary = entry(id: 'p', notes: 'existing');
      final secondary = entry(id: 's', notes: 'other');
      final preview = service.previewMerge(primary, secondary);
      expect(preview.willCopyNotes, isFalse);
    });

    test('copies OTP when primary has none', () {
      final primary = entry(id: 'p');
      final secondary = entry(
        id: 's',
        otpUri: 'otpauth://totp/test?secret=ABC',
      );
      final preview = service.previewMerge(primary, secondary);
      expect(preview.willCopyOtp, isTrue);
    });

    test('does not copy OTP when primary already has one', () {
      final primary = entry(id: 'p', otpUri: 'otpauth://totp/test?secret=XYZ');
      final secondary = entry(
        id: 's',
        otpUri: 'otpauth://totp/test?secret=ABC',
      );
      final preview = service.previewMerge(primary, secondary);
      expect(preview.willCopyOtp, isFalse);
    });

    test('lists non-OTP custom fields absent in primary', () {
      final primary = entry(
        id: 'p',
        customFields: [const VaultCustomField(key: 'PIN', value: '1234')],
      );
      final secondary = entry(
        id: 's',
        customFields: [
          const VaultCustomField(key: 'PIN', value: '9999'),
          const VaultCustomField(key: 'Recovery', value: 'abc'),
        ],
      );
      final preview = service.previewMerge(primary, secondary);
      expect(preview.customFieldKeysToCopy, ['Recovery']);
    });

    test('OTP custom field is not included in customFieldKeysToCopy', () {
      final primary = entry(id: 'p');
      final secondary = entry(
        id: 's',
        customFields: [
          const VaultCustomField(
            key: 'otp',
            value: 'otpauth://totp?secret=ABC',
          ),
        ],
      );
      final preview = service.previewMerge(primary, secondary);
      expect(preview.customFieldKeysToCopy, isEmpty);
    });

    test('detects attachments to copy', () {
      final primary = entry(
        id: 'p',
        attachments: [
          const VaultAttachment(key: 'a.pdf', name: 'a.pdf', size: 100),
        ],
      );
      final secondary = entry(
        id: 's',
        attachments: [
          const VaultAttachment(key: 'b.png', name: 'b.png', size: 200),
        ],
      );
      final preview = service.previewMerge(primary, secondary);
      expect(preview.willCopyAttachments, isTrue);
    });

    test('hasAnythingToCopy is false when secondary adds nothing', () {
      final primary = entry(id: 'p', notes: 'note');
      final secondary = entry(id: 's', notes: '');
      final preview = service.previewMerge(primary, secondary);
      expect(preview.hasAnythingToCopy, isFalse);
    });

    test('lists secondary URLs missing from primary', () {
      final primary = entry(id: 'p', url: 'https://github.com');
      final secondary = entry(
        id: 's',
        url: 'https://gitlab.com',
        customFields: [
          const VaultCustomField(key: 'KP2A_URL_1', value: 'https://a.com'),
          // Already on primary (normalized) — must not be listed.
          const VaultCustomField(key: 'KP2A_URL_2', value: 'http://github.com/'),
        ],
      );
      final preview = service.previewMerge(primary, secondary);
      expect(preview.urlsToCopy, ['https://gitlab.com', 'https://a.com']);
      expect(preview.hasAnythingToCopy, isTrue);
    });

    test('URL custom fields are excluded from customFieldKeysToCopy', () {
      final primary = entry(id: 'p');
      final secondary = entry(
        id: 's',
        customFields: [
          const VaultCustomField(key: 'KP2A_URL_1', value: 'https://a.com'),
        ],
      );
      final preview = service.previewMerge(primary, secondary);
      expect(preview.customFieldKeysToCopy, isEmpty);
    });
  });
}
