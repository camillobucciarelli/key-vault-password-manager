# Duplicate Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect vault entries that share the same normalized URL + username, and let the user resolve them by deleting or merging.

**Architecture:** A pure-Dart `VaultDuplicateService` handles detection and merge previewing; kdbx write operations (merge + delete-to-bin) live in the existing `VaultKdbxService`; `VaultBloc` wires events and state; a new `vault_duplicates.part.dart` provides the dialog UI; the sync strip gains an amber badge and the settings sheet gains a "Manage duplicates" item.

**Tech Stack:** Flutter, flutter_bloc, kdbx (Dart), equatable, phosphor_flutter, get_it DI.

---

## File Map

| Action | Path |
|--------|------|
| Create | `lib/features/password_manager/domain/models/duplicate_group.dart` |
| Create | `lib/features/password_manager/domain/models/merge_preview.dart` |
| Create | `lib/features/password_manager/data/services/vault_duplicate_service.dart` |
| Create | `test/features/password_manager/data/services/vault_duplicate_service_test.dart` |
| Modify | `lib/features/password_manager/data/services/vault_kdbx_service.dart` |
| Modify | `lib/features/password_manager/presentation/bloc/vault/vault_event.dart` |
| Modify | `lib/features/password_manager/presentation/bloc/vault/vault_state.dart` |
| Modify | `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart` |
| Modify | `lib/features/password_manager/di/password_manager_data_di.dart` |
| Modify | `lib/features/password_manager/di/password_manager_presentation_di.dart` |
| Create | `lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart` |
| Modify | `lib/features/password_manager/presentation/screens/vault_screen.dart` |
| Modify | `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart` |
| Modify | `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart` |

---

## Task 1: Domain Models — DuplicateGroup and MergePreview

**Files:**
- Create: `lib/features/password_manager/domain/models/duplicate_group.dart`
- Create: `lib/features/password_manager/domain/models/merge_preview.dart`

- [ ] **Step 1: Create `duplicate_group.dart`**

```dart
import 'package:equatable/equatable.dart';

import 'vault_entry.dart';

class DuplicateGroup extends Equatable {
  const DuplicateGroup({
    required this.sharedUrl,
    required this.sharedUsername,
    required this.entries,
  });

  /// Human-readable normalized URL shared by all entries in this group.
  final String sharedUrl;

  /// Normalized (lowercased, trimmed) username shared by all entries.
  final String sharedUsername;

  /// 2+ entries with the same sharedUrl + sharedUsername, newest first.
  final List<VaultEntry> entries;

  @override
  List<Object?> get props => [sharedUrl, sharedUsername, entries];
}
```

- [ ] **Step 2: Create `merge_preview.dart`**

```dart
import 'package:equatable/equatable.dart';

import 'vault_entry.dart';

class MergePreview extends Equatable {
  const MergePreview({
    required this.primary,
    required this.secondary,
    required this.willCopyNotes,
    required this.willCopyOtp,
    required this.customFieldKeysToCopy,
    required this.willCopyAttachments,
  });

  /// The entry that will be kept and enriched (newest by updatedAt/createdAt).
  final VaultEntry primary;

  /// The entry that will be moved to the recycle bin after merge.
  final VaultEntry secondary;

  /// True if primary.notes is empty and secondary.notes is not.
  final bool willCopyNotes;

  /// True if primary has no OTP URI but secondary does.
  final bool willCopyOtp;

  /// Non-OTP custom field keys present in secondary but absent in primary.
  final List<String> customFieldKeysToCopy;

  /// True if secondary has at least one attachment whose name is absent in primary.
  final bool willCopyAttachments;

  bool get hasAnythingToCopy =>
      willCopyNotes ||
      willCopyOtp ||
      customFieldKeysToCopy.isNotEmpty ||
      willCopyAttachments;

  @override
  List<Object?> get props => [
        primary,
        secondary,
        willCopyNotes,
        willCopyOtp,
        customFieldKeysToCopy,
        willCopyAttachments,
      ];
}
```

- [ ] **Step 3: Run analyzer to verify models compile**

```bash
flutter analyze lib/features/password_manager/domain/models/duplicate_group.dart lib/features/password_manager/domain/models/merge_preview.dart
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/password_manager/domain/models/duplicate_group.dart lib/features/password_manager/domain/models/merge_preview.dart
git commit -m "feat: add DuplicateGroup and MergePreview domain models"
```

---

## Task 2: VaultDuplicateService

**Files:**
- Create: `lib/features/password_manager/data/services/vault_duplicate_service.dart`

- [ ] **Step 1: Create the service file**

```dart
import '../../domain/models/duplicate_group.dart';
import '../../domain/models/merge_preview.dart';
import '../../domain/models/vault_entry.dart';

class VaultDuplicateService {
  /// Groups [allEntries] by normalized URL + username.
  /// Returns only groups with 2+ entries, sorted by size desc then URL asc.
  /// Entries inside each group are sorted newest first (updatedAt, then createdAt).
  /// Entries with an empty URL are excluded.
  List<DuplicateGroup> findDuplicates(List<VaultEntry> allEntries) {
    final accumulator = <String, List<VaultEntry>>{};

    for (final entry in allEntries) {
      if (entry.url.trim().isEmpty) continue;
      final key =
          '${_normalizeUrl(entry.url)}\x00${_normalizeUsername(entry.username)}';
      accumulator.putIfAbsent(key, () => []).add(entry);
    }

    final result = <DuplicateGroup>[];
    for (final mapEntry in accumulator.entries) {
      if (mapEntry.value.length < 2) continue;

      final sorted = List<VaultEntry>.from(mapEntry.value)
        ..sort((a, b) {
          final aTime =
              a.updatedAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime =
              b.updatedAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime); // newest first
        });

      final parts = mapEntry.key.split('\x00');
      result.add(
        DuplicateGroup(
          sharedUrl: parts[0],
          sharedUsername: parts.length > 1 ? parts[1] : '',
          entries: sorted,
        ),
      );
    }

    result.sort((a, b) {
      final bySize = b.entries.length.compareTo(a.entries.length);
      if (bySize != 0) return bySize;
      return a.sharedUrl.compareTo(b.sharedUrl);
    });

    return result;
  }

  /// Computes which fields would be copied from [secondary] into [primary]
  /// without touching the kdbx file.
  MergePreview previewMerge(VaultEntry primary, VaultEntry secondary) {
    final willCopyNotes =
        primary.notes.trim().isEmpty && secondary.notes.trim().isNotEmpty;

    final willCopyOtp = primary.otpUri == null && secondary.otpUri != null;

    final primaryKeys = primary.customFields
        .map((f) => f.key.toLowerCase())
        .toSet();

    final customFieldKeysToCopy = secondary.customFields
        .where((f) => !_isOtpKey(f.key))
        .where((f) => !primaryKeys.contains(f.key.toLowerCase()))
        .map((f) => f.key)
        .toList(growable: false);

    final primaryAttachmentNames =
        primary.attachments.map((a) => a.name).toSet();
    final willCopyAttachments =
        secondary.attachments.any((a) => !primaryAttachmentNames.contains(a.name));

    return MergePreview(
      primary: primary,
      secondary: secondary,
      willCopyNotes: willCopyNotes,
      willCopyOtp: willCopyOtp,
      customFieldKeysToCopy: customFieldKeysToCopy,
      willCopyAttachments: willCopyAttachments,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _normalizeUrl(String url) {
    var result = url.toLowerCase();
    result = result.replaceFirst(RegExp(r'^https?://'), '');
    result = result.replaceFirst(RegExp(r'^ftp://'), '');
    result = result.replaceFirst(RegExp(r'^www\.'), '');
    if (result.endsWith('/')) result = result.substring(0, result.length - 1);
    final queryIdx = result.indexOf('?');
    if (queryIdx >= 0) result = result.substring(0, queryIdx);
    final fragmentIdx = result.indexOf('#');
    if (fragmentIdx >= 0) result = result.substring(0, fragmentIdx);
    return result;
  }

  String _normalizeUsername(String username) => username.trim().toLowerCase();

  bool _isOtpKey(String key) {
    final k = key.toLowerCase().trim();
    return k == 'otp' || k == 'totp' || k == 'otpauth' || k.contains('otp');
  }
}
```

- [ ] **Step 2: Run analyzer on the new file**

```bash
flutter analyze lib/features/password_manager/data/services/vault_duplicate_service.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/password_manager/data/services/vault_duplicate_service.dart
git commit -m "feat: add VaultDuplicateService (findDuplicates + previewMerge)"
```

---

## Task 3: Tests for VaultDuplicateService

**Files:**
- Create: `test/features/password_manager/data/services/vault_duplicate_service_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
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
      password: 'pw',
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
        entry(id: '2', url: 'https://github.com', username: 'bob'),
        entry(id: '3', url: 'https://gitlab.com', username: 'alice'),
      ];
      expect(service.findDuplicates(entries), isEmpty);
    });

    test('detects two entries with same url and username as one group', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'alice'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
      expect(groups.first.entries, hasLength(2));
    });

    test('normalizes scheme — https and http treated the same', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'alice'),
        entry(id: '2', url: 'http://github.com', username: 'alice'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('normalizes www prefix', () {
      final entries = [
        entry(id: '1', url: 'https://www.github.com', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'alice'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('strips trailing slash', () {
      final entries = [
        entry(id: '1', url: 'https://github.com/', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'alice'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('strips query string and fragment', () {
      final entries = [
        entry(id: '1', url: 'https://github.com?tab=repos#section', username: 'alice'),
        entry(id: '2', url: 'https://github.com', username: 'alice'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('normalizes username case and whitespace', () {
      final entries = [
        entry(id: '1', url: 'https://github.com', username: 'Alice'),
        entry(id: '2', url: 'https://github.com', username: '  alice  '),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups, hasLength(1));
    });

    test('excludes entries with empty URL', () {
      final entries = [
        entry(id: '1', url: '', username: 'alice'),
        entry(id: '2', url: '   ', username: 'alice'),
      ];
      expect(service.findDuplicates(entries), isEmpty);
    });

    test('sorts entries newest first within a group', () {
      final old = DateTime(2023, 1, 1);
      final recent = DateTime(2024, 6, 1);
      final entries = [
        entry(id: 'old', url: 'https://github.com', username: 'alice', updatedAt: old),
        entry(id: 'new', url: 'https://github.com', username: 'alice', updatedAt: recent),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups.first.entries.first.id, 'new');
      expect(groups.first.entries.last.id, 'old');
    });

    test('exposes sharedUrl as normalized host+path', () {
      final entries = [
        entry(id: '1', url: 'https://www.GitHub.com/login', username: 'alice'),
        entry(id: '2', url: 'https://www.github.com/login', username: 'alice'),
      ];
      final groups = service.findDuplicates(entries);
      expect(groups.first.sharedUrl, 'github.com/login');
    });
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
      final secondary = entry(id: 's', otpUri: 'otpauth://totp/test?secret=ABC');
      final preview = service.previewMerge(primary, secondary);
      expect(preview.willCopyOtp, isTrue);
    });

    test('does not copy OTP when primary already has one', () {
      final primary = entry(id: 'p', otpUri: 'otpauth://totp/test?secret=XYZ');
      final secondary = entry(id: 's', otpUri: 'otpauth://totp/test?secret=ABC');
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
        customFields: [const VaultCustomField(key: 'otp', value: 'otpauth://totp?secret=ABC')],
      );
      final preview = service.previewMerge(primary, secondary);
      expect(preview.customFieldKeysToCopy, isEmpty);
    });

    test('detects attachments to copy', () {
      final primary = entry(
        id: 'p',
        attachments: [const VaultAttachment(key: 'a.pdf', name: 'a.pdf', size: 100)],
      );
      final secondary = entry(
        id: 's',
        attachments: [const VaultAttachment(key: 'b.png', name: 'b.png', size: 200)],
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
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/features/password_manager/data/services/vault_duplicate_service_test.dart
```

Expected: FAIL — `VaultDuplicateService` class not found (test can't import it yet — Task 2 was done, so they should actually pass. Run now to confirm.)

- [ ] **Step 3: Run tests — expect all green**

```bash
flutter test test/features/password_manager/data/services/vault_duplicate_service_test.dart --reporter expanded
```

Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add test/features/password_manager/data/services/vault_duplicate_service_test.dart
git commit -m "test: add VaultDuplicateService unit tests"
```

---

## Task 4: VaultKdbxService — mergeEntries

**Files:**
- Modify: `lib/features/password_manager/data/services/vault_kdbx_service.dart`

The method copies missing notes, custom fields (including OTP), and attachments from the secondary kdbx entry into the primary, then moves the secondary to the recycle bin. A single `_save` is called at the end.

- [ ] **Step 1: Add test for `mergeEntries` to the existing test file**

Open `test/features/password_manager/data/services/vault_kdbx_service_test.dart` and add this test group at the bottom of `main()`, before the closing `}`:

```dart
  group('mergeEntries', () {
    test('copies notes from secondary to primary when primary notes is empty',
        () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      final primaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Primary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
      );
      final secondaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Secondary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: 'important note',
      );

      await service.mergeEntries(
        databasePath: databasePath,
        password: password,
        primaryId: primaryId,
        secondaryId: secondaryId,
      );

      final all = await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      );
      final primary = all.firstWhere((e) => e.id == primaryId);
      expect(primary.notes, 'important note');
    });

    test('does not overwrite primary notes when already set', () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      final primaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Primary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: 'keep me',
      );
      final secondaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Secondary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: 'do not copy',
      );

      await service.mergeEntries(
        databasePath: databasePath,
        password: password,
        primaryId: primaryId,
        secondaryId: secondaryId,
      );

      final all = await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      );
      final primary = all.firstWhere((e) => e.id == primaryId);
      expect(primary.notes, 'keep me');
    });

    test('copies custom field from secondary absent in primary', () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      final primaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Primary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
        customFields: [
          const VaultCustomField(key: 'PIN', value: '1234'),
        ],
      );
      final secondaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Secondary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
        customFields: [
          const VaultCustomField(key: 'Recovery', value: 'abc123'),
        ],
      );

      await service.mergeEntries(
        databasePath: databasePath,
        password: password,
        primaryId: primaryId,
        secondaryId: secondaryId,
      );

      final all = await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      );
      final primary = all.firstWhere((e) => e.id == primaryId);
      final fieldKeys = primary.customFields.map((f) => f.key).toList();
      expect(fieldKeys, containsAll(['PIN', 'Recovery']));
    });

    test('moves secondary to recycle bin after merge', () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      final primaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Primary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
      );
      final secondaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Secondary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
      );

      await service.mergeEntries(
        databasePath: databasePath,
        password: password,
        primaryId: primaryId,
        secondaryId: secondaryId,
      );

      final recycleBinEntries = await service.loadRecycleBinEntries(
        databasePath: databasePath,
        password: password,
      );
      expect(recycleBinEntries.map((e) => e.id), contains(secondaryId));

      final all = await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      );
      final activeIds = all.map((e) => e.id).toSet();
      expect(activeIds, contains(primaryId));
      expect(activeIds, isNot(contains(secondaryId)));
    });
  });
```

Note: the test calls `service.loadAllEntries(...)`. Check whether this method exists in `VaultKdbxService` — looking at the existing test file (line 40-43) it does: `service.loadAllEntries(databasePath:, password:)`. Also need `VaultCustomField` import in the test file.

- [ ] **Step 2: Run tests to confirm they fail (method not yet implemented)**

```bash
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart --reporter expanded 2>&1 | tail -20
```

Expected: FAIL — `mergeEntries` not found.

- [ ] **Step 3: Add `mergeEntries` to `VaultKdbxService`**

In `lib/features/password_manager/data/services/vault_kdbx_service.dart`, add after the `updateEntry` method (after line ~213):

```dart
  Future<void> mergeEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String primaryId,
    required String secondaryId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final allEntries = file.body.rootGroup.getAllEntries();
    final primary = _findEntryById(allEntries, primaryId);
    final secondary = _findEntryById(allEntries, secondaryId);

    // Copy notes if primary notes is empty.
    final primaryNotes = primary.getString(_notesKey)?.getText() ?? '';
    final secondaryNotes = secondary.getString(_notesKey)?.getText() ?? '';
    if (primaryNotes.trim().isEmpty && secondaryNotes.trim().isNotEmpty) {
      primary.setString(_notesKey, PlainValue(secondaryNotes));
    }

    // Copy custom fields present in secondary but absent in primary.
    final primaryStringKeys = primary.stringEntries
        .map((e) => e.key.key.toLowerCase())
        .toSet();
    for (final stringEntry in secondary.stringEntries) {
      final key = stringEntry.key.key;
      if (_standardEntryKeys.contains(key.toLowerCase())) continue;
      if (!primaryStringKeys.contains(key.toLowerCase())) {
        primary.setString(KdbxKey(key), stringEntry.value ?? PlainValue(''));
      }
    }

    // Copy attachments present in secondary but absent in primary.
    final primaryAttachmentKeys =
        primary.binaryEntries.map((e) => e.key.key).toSet();
    for (final binaryEntry in secondary.binaryEntries) {
      final key = binaryEntry.key.key;
      if (!primaryAttachmentKeys.contains(key)) {
        primary.createBinary(
          isProtected: binaryEntry.value.isProtected,
          name: key,
          bytes: binaryEntry.value.value,
        );
      }
    }

    // Move secondary to recycle bin.
    file.deleteEntry(secondary);

    await _save(databasePath, file);
  }
```

- [ ] **Step 4: Run tests — expect green**

```bash
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart --reporter expanded 2>&1 | tail -30
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/password_manager/data/services/vault_kdbx_service.dart test/features/password_manager/data/services/vault_kdbx_service_test.dart
git commit -m "feat: add VaultKdbxService.mergeEntries + tests"
```

---

## Task 5: BLoC Layer — Events, State, Handlers, DI

**Files:**
- Modify: `lib/features/password_manager/presentation/bloc/vault/vault_event.dart`
- Modify: `lib/features/password_manager/presentation/bloc/vault/vault_state.dart`
- Modify: `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart`
- Modify: `lib/features/password_manager/di/password_manager_data_di.dart`
- Modify: `lib/features/password_manager/di/password_manager_presentation_di.dart`

- [ ] **Step 1: Add three new events to `vault_event.dart`**

At the end of the file, before the closing of `vault_event.dart`, add:

```dart
class LoadDuplicates extends VaultEvent {
  const LoadDuplicates();
}

class DeleteDuplicateEntry extends VaultEvent {
  const DeleteDuplicateEntry(this.entryId);

  final String entryId;

  @override
  List<Object?> get props => [entryId];
}

class MergeDuplicateEntries extends VaultEvent {
  const MergeDuplicateEntries({
    required this.primaryId,
    required this.secondaryId,
  });

  final String primaryId;
  final String secondaryId;

  @override
  List<Object?> get props => [primaryId, secondaryId];
}
```

- [ ] **Step 2: Add `duplicateGroups` and `isDuplicatesLoading` to `VaultState`**

Add the import at the top of `vault_state.dart`:
```dart
import '../../../domain/models/duplicate_group.dart';
```

In the constructor, add two new named params after `isSyncReloadPending`:
```dart
    this.duplicateGroups = const [],
    this.isDuplicatesLoading = false,
```

Add the fields to the class body (after `isSyncReloadPending`):
```dart
  final List<DuplicateGroup> duplicateGroups;
  final bool isDuplicatesLoading;
```

Add the convenience getter (after `breadcrumbs()`):
```dart
  int get duplicateGroupCount => duplicateGroups.length;
```

In `copyWith`, add two new optional params:
```dart
    List<DuplicateGroup>? duplicateGroups,
    bool? isDuplicatesLoading,
```

In the `VaultState(...)` constructor call inside `copyWith`, add:
```dart
      duplicateGroups: duplicateGroups ?? this.duplicateGroups,
      isDuplicatesLoading: isDuplicatesLoading ?? this.isDuplicatesLoading,
```

In `props`, add at the end of the list:
```dart
    duplicateGroups,
    isDuplicatesLoading,
```

- [ ] **Step 3: Run analyzer on state file**

```bash
flutter analyze lib/features/password_manager/presentation/bloc/vault/vault_state.dart
```

Expected: no issues.

- [ ] **Step 4: Update `VaultBloc`**

a. Add the import at the top of `vault_bloc.dart`:
```dart
import '../../../data/services/vault_duplicate_service.dart';
import '../../../domain/models/duplicate_group.dart';
```

b. Add `vaultDuplicateService` to the constructor parameter list (after `vaultCsvImportService`):
```dart
    required this.vaultDuplicateService,
```

c. Add the field declaration (after `vaultCsvImportService`):
```dart
  final VaultDuplicateService vaultDuplicateService;
```

d. Register the three new handlers inside the constructor body (after the existing `on<>` registrations):
```dart
    on<LoadDuplicates>(_onLoadDuplicates);
    on<DeleteDuplicateEntry>(_onDeleteDuplicateEntry);
    on<MergeDuplicateEntries>(_onMergeDuplicateEntries);
```

e. Add the `_computeDuplicates` helper method (add near other private helpers, before `_computeVisibleEntries`):
```dart
  void _computeDuplicates(Emitter<VaultState> emit) {
    final groups = vaultDuplicateService.findDuplicates(state.allEntries);
    _safeEmit(
      emit,
      state.copyWith(duplicateGroups: groups, isDuplicatesLoading: false),
    );
  }
```

f. Add the three new event handlers (add after `_onClearVaultInfo`):
```dart
  void _onLoadDuplicates(
    LoadDuplicates event,
    Emitter<VaultState> emit,
  ) {
    _safeEmit(emit, state.copyWith(isDuplicatesLoading: true));
    _computeDuplicates(emit);
  }

  Future<void> _onDeleteDuplicateEntry(
    DeleteDuplicateEntry event,
    Emitter<VaultState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.deleteEntry(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
      _computeDuplicates(emit);
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed deleting duplicate entry.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to delete duplicate.',
        ),
      );
    }
  }

  Future<void> _onMergeDuplicateEntries(
    MergeDuplicateEntries event,
    Emitter<VaultState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.mergeEntries(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        primaryId: event.primaryId,
        secondaryId: event.secondaryId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
      _computeDuplicates(emit);
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed merging duplicate entries.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to merge entries.',
        ),
      );
    }
  }
```

g. Add `_computeDuplicates(emit)` call at the end of `_onInitializeVault` (inside the `try` block, after `_loadRecycleBinEntries`):

Find `add(const BackgroundDriveSync());` in `_onInitializeVault` and add the call just before it:
```dart
      _computeDuplicates(emit);
      add(const BackgroundDriveSync());
```

h. Add `_computeDuplicates(emit)` at the end of `_onRefreshVault` (inside, after `_loadRecycleBinEntries`):
```dart
    _computeDuplicates(emit);
```

i. Add `_computeDuplicates(emit)` in `_onImportVaultEntriesFromCsv`, after the `await _reload(...)` and before `await _scheduleAutoSync(emit)`:
```dart
      _computeDuplicates(emit);
      await _scheduleAutoSync(emit);
```

- [ ] **Step 5: Run analyzer on the bloc**

```bash
flutter analyze lib/features/password_manager/presentation/bloc/vault/
```

Expected: no issues.

- [ ] **Step 6: Register `VaultDuplicateService` in DI**

In `lib/features/password_manager/di/password_manager_data_di.dart`, add import:
```dart
import '../data/services/vault_duplicate_service.dart';
```

Add registration (alongside `VaultCsvImportService` and `VaultKdbxService`):
```dart
  sl.registerLazySingleton(() => VaultDuplicateService());
```

- [ ] **Step 7: Wire `vaultDuplicateService` into VaultBloc factory in DI**

In `lib/features/password_manager/di/password_manager_presentation_di.dart`, add `vaultDuplicateService: sl()` to the `VaultBloc` factory (after `vaultCsvImportService: sl()`):
```dart
      vaultDuplicateService: sl(),
```

- [ ] **Step 8: Run full analyzer and tests**

```bash
flutter analyze
flutter test
```

Expected: no analysis errors, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add \
  lib/features/password_manager/presentation/bloc/vault/vault_event.dart \
  lib/features/password_manager/presentation/bloc/vault/vault_state.dart \
  lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart \
  lib/features/password_manager/di/password_manager_data_di.dart \
  lib/features/password_manager/di/password_manager_presentation_di.dart
git commit -m "feat: wire duplicate management into VaultBloc (events, state, handlers)"
```

---

## Task 6: vault_duplicates.part.dart — Dialog UI

**Files:**
- Create: `lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart`
- Modify: `lib/features/password_manager/presentation/screens/vault_screen.dart`

- [ ] **Step 1: Add the part declaration to `vault_screen.dart`**

In `vault_screen.dart` after the last `part` directive (line ~51), add:
```dart
part 'vault/vault_duplicates.part.dart';
```

- [ ] **Step 2: Create `vault_duplicates.part.dart`**

```dart
part of '../vault_screen.dart';

Future<void> _showDuplicatesDialog(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  bloc.add(const LoadDuplicates());

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return BlocProvider.value(value: bloc, child: const _DuplicatesDialog());
    },
  );
}

// ── Main dialog ───────────────────────────────────────────────────────────────

class _DuplicatesDialog extends StatelessWidget {
  const _DuplicatesDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Duplicate records'),
      insetPadding: _dialogInsetPadding(context),
      contentPadding: _dialogContentPadding(context),
      content: SizedBox(
        width: _dialogContentWidth(context, 620),
        height: _dialogContentHeight(context, 460),
        child: BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            if (state.isDuplicatesLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.duplicateGroups.isEmpty) {
              return const _DuplicatesEmptyState();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${state.duplicateGroups.length} '
                    '${state.duplicateGroups.length == 1 ? 'pair' : 'groups'} '
                    'with same URL and username',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: state.duplicateGroups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _DuplicateGroupCard(
                        group: state.duplicateGroups[index],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ── Group card ────────────────────────────────────────────────────────────────

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({required this.group});

  final DuplicateGroup group;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPair = group.entries.length == 2;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.6 : 0.5,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.55 : 0.7,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: URL + username
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.sharedUrl.isEmpty ? '(No URL)' : group.sharedUrl,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (group.sharedUsername.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    group.sharedUsername,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.45 : 0.6,
            ),
          ),
          // Entry sub-cards
          ...group.entries.map((entry) => _DuplicateEntrySubCard(
                entry: entry,
                showDeleteButton: !isPair,
              )),
          // Actions row
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    context.read<VaultBloc>().add(
                      DeleteDuplicateEntry(group.entries.last.id),
                    );
                  },
                  icon: const Icon(AppIcons.delete, size: 16),
                  label: const Text('Delete older'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                ),
                if (isPair) ...[
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () async {
                      final preview = VaultDuplicateService().previewMerge(
                        group.entries.first,
                        group.entries.last,
                      );
                      if (!context.mounted) return;
                      final confirmed =
                          await _showMergeConfirmDialog(context, preview);
                      if (confirmed == true && context.mounted) {
                        context.read<VaultBloc>().add(
                          MergeDuplicateEntries(
                            primaryId: group.entries.first.id,
                            secondaryId: group.entries.last.id,
                          ),
                        );
                      }
                    },
                    child: const Text('Merge'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateEntrySubCard extends StatelessWidget {
  const _DuplicateEntrySubCard({
    required this.entry,
    required this.showDeleteButton,
  });

  final VaultEntry entry;
  final bool showDeleteButton;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final modifiedAt = entry.updatedAt ?? entry.createdAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: _InteractiveItemSurface(
        radius: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title.isEmpty ? '(Untitled)' : entry.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '••••••••  •  ${_formatEntryDateTime(modifiedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.58),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (showDeleteButton)
                TextButton(
                  onPressed: () {
                    context.read<VaultBloc>().add(
                      DeleteDuplicateEntry(entry.id),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  child: const Text('Delete'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Merge confirm dialog ──────────────────────────────────────────────────────

Future<bool?> _showMergeConfirmDialog(
  BuildContext context,
  MergePreview preview,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final primaryTitle = preview.primary.title.isEmpty
          ? '(Untitled)'
          : preview.primary.title;
      final secondaryTitle = preview.secondary.title.isEmpty
          ? '(Untitled)'
          : preview.secondary.title;

      return AlertDialog(
        title: const Text('Merge records'),
        insetPadding: _dialogInsetPadding(dialogContext),
        contentPadding: _dialogContentPadding(dialogContext),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        content: SizedBox(
          width: _dialogContentWidth(dialogContext, 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Keep: $primaryTitle'),
              const SizedBox(height: 2),
              Text('Delete after merge: $secondaryTitle'),
              const SizedBox(height: 14),
              if (!preview.hasAnythingToCopy)
                const Text(
                  'No additional data — the older entry will be deleted.',
                )
              else ...[
                const Text('Fields to copy from older entry:'),
                const SizedBox(height: 6),
                if (preview.willCopyNotes)
                  const Text('• Notes'),
                if (preview.willCopyOtp)
                  const Text('• OTP code'),
                ...preview.customFieldKeysToCopy
                    .map((key) => Text('• $key')),
                if (preview.willCopyAttachments)
                  const Text('• Attachments'),
              ],
            ],
          ),
        ),
        actions: _adaptiveDialogActions(dialogContext, [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Merge'),
          ),
        ]),
      );
    },
  );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _DuplicatesEmptyState extends StatelessWidget {
  const _DuplicatesEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: isDark ? 0.68 : 0.9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.65 : 0.86,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(
                  alpha: isDark ? 0.45 : 0.58,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                AppIcons.check,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No duplicates found',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'No entries share the same URL and username.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Add missing imports to `vault_screen.dart`**

The part file uses `VaultDuplicateService`, `DuplicateGroup`, and `MergePreview`. Add imports to `vault_screen.dart`:

```dart
import '../../data/services/vault_duplicate_service.dart';
import '../../domain/models/duplicate_group.dart';
import '../../domain/models/merge_preview.dart';
```

- [ ] **Step 4: Run analyzer on the new file**

```bash
flutter analyze lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart
```

Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add \
  lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart \
  lib/features/password_manager/presentation/screens/vault_screen.dart
git commit -m "feat: add vault_duplicates.part.dart — duplicate management dialog"
```

---

## Task 7: Badge in Sync Strip + Settings Menu Item

**Files:**
- Modify: `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart`
- Modify: `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart`

### Part A — Badge in Sync Strip

The badge is a small amber `ActionChip` placed right of the database-name column. It shows only when `state.duplicateGroupCount > 0`. Tapping it dispatches `LoadDuplicates` and opens the dialog.

- [ ] **Step 1: Add `_DuplicateBadge` widget at the bottom of `vault_navigation.part.dart`** (after `_ThemePicker`)

```dart
class _DuplicateBadge extends StatelessWidget {
  const _DuplicateBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: '$count duplicate ${count == 1 ? 'group' : 'groups'} found',
        ignorePointer: true,
        child: ActionChip(
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          visualDensity: VisualDensity.compact,
          avatar: const Icon(AppIcons.copy, size: 13, color: AppColors.warning),
          label: Text(
            '$count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
          side: BorderSide(
            color: AppColors.warning.withValues(alpha: 0.42),
          ),
          backgroundColor: AppColors.warning.withValues(alpha: 0.12),
          onPressed: onTap,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Add `onOpenDuplicates` callback to `_SyncStatusStrip`**

In `vault_navigation.part.dart`, find the `_SyncStatusStrip` class declaration and add the new parameter:

```dart
class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip({
    required this.state,
    required this.onRefresh,
    required this.onOpenRecycleBin,
    required this.onChangeDatabase,
    required this.onOpenDuplicates,   // ADD THIS
  });

  final VaultState state;
  final VoidCallback onRefresh;
  final VoidCallback onOpenRecycleBin;
  final Future<void> Function() onChangeDatabase;
  final VoidCallback onOpenDuplicates;  // ADD THIS
```

- [ ] **Step 3: Insert the badge in both header rows of `_SyncStatusStrip.build`**

The header row appears twice in `_SyncStatusStrip.build` (once for non-compact, once for compact). In both `Row` widgets that contain the primary-action `IconButton` and the `_SyncStripMenuButton`, insert the badge just before the primary-action `Tooltip`:

```dart
// In BOTH Row(...) blocks that contain the primary action IconButton:
if (state.duplicateGroupCount > 0)
  _DuplicateBadge(
    count: state.duplicateGroupCount,
    onTap: onOpenDuplicates,
  ),
// (existing) Tooltip(message: effectivePrimaryTooltip, ...)
```

The non-compact row currently looks like:
```
Row(children: [
  Expanded(child: Row(...)),       // db icon + db name
  Tooltip(..., child: IconButton), // primary action
  SizedBox(width: 2),
  _SyncStripMenuButton(...),
])
```

After the change it should be:
```
Row(children: [
  Expanded(child: Row(...)),
  if (state.duplicateGroupCount > 0)
    _DuplicateBadge(count: state.duplicateGroupCount, onTap: onOpenDuplicates),
  Tooltip(..., child: IconButton),
  SizedBox(width: 2),
  _SyncStripMenuButton(...),
])
```

Apply the same insertion to the compact `Row` inside the `else Column`.

- [ ] **Step 4: Wire `onOpenDuplicates` in `vault_shell.part.dart`**

In `vault_shell.part.dart`, update `_VaultSyncStatusStrip`:

```dart
class _VaultSyncStatusStrip extends StatelessWidget {
  const _VaultSyncStatusStrip({
    required this.onOpenRecycleBin,
    required this.onChangeDatabase,
    required this.onOpenDuplicates,   // ADD THIS
  });

  final VoidCallback onOpenRecycleBin;
  final Future<void> Function() onChangeDatabase;
  final VoidCallback onOpenDuplicates;  // ADD THIS
```

In `_VaultSyncStatusStrip.build`, pass through to `_SyncStatusStrip`:

```dart
        return _SyncStatusStrip(
          state: state,
          onRefresh: () {
            context.read<VaultBloc>().add(const RefreshVault());
          },
          onOpenRecycleBin: onOpenRecycleBin,
          onChangeDatabase: onChangeDatabase,
          onOpenDuplicates: onOpenDuplicates,   // ADD THIS
        );
```

Update `_syncStatusStripBuildWhen` to rebuild when `duplicateGroupCount` changes:

```dart
bool _syncStatusStripBuildWhen(VaultState previous, VaultState current) {
  return previous.databasePath != current.databasePath ||
      previous.isDriveConnected != current.isDriveConnected ||
      previous.isDriveLinked != current.isDriveLinked ||
      previous.linkedDriveFileName != current.linkedDriveFileName ||
      previous.syncStatus != current.syncStatus ||
      previous.lastSyncAt != current.lastSyncAt ||
      previous.autoSyncEnabled != current.autoSyncEnabled ||
      previous.isSyncing != current.isSyncing ||
      previous.duplicateGroupCount != current.duplicateGroupCount; // ADD THIS
}
```

Update the `_VaultSyncStatusStrip` usage site in `_VaultViewState.build`:

```dart
_VaultSyncStatusStrip(
  onOpenRecycleBin: () {
    _showRecycleBinDialog(context);
  },
  onChangeDatabase: _closeCurrentDatabaseAndSelectAnother,
  onOpenDuplicates: () {            // ADD THIS
    context.read<VaultBloc>().add(const LoadDuplicates());
    _showDuplicatesDialog(context);
  },
),
```

### Part B — Settings Menu Item

- [ ] **Step 5: Add `manageDuplicates` case to `handleSelection` in `_SyncStripMenuButton.build`**

In `vault_navigation.part.dart`, find the `handleSelection` function inside `_SyncStripMenuButton.build` and add a new case:

```dart
        case 'manageDuplicates':
          if (context.mounted) await _showDuplicatesDialog(context);
          break;
```

Add it before the closing `}` of the `switch`.

- [ ] **Step 6: Add "Manage duplicates" item to the Tools section of `_VaultSettingsSheet`**

In `_VaultSettingsSheet.build`, in the `Tools` `_SheetSection`, add after the `recycleBin` item and before the autofill items:

```dart
                        _SheetItem(
                          icon: AppIcons.copy,
                          iconContainerColor:
                              colorScheme.tertiaryContainer.withValues(
                                alpha: 0.55,
                              ),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Manage duplicates',
                          subtitle: state.duplicateGroupCount > 0
                              ? '${state.duplicateGroupCount} ${state.duplicateGroupCount == 1 ? 'group' : 'groups'} found'
                              : 'No duplicates',
                          onTap: () => onSelect('manageDuplicates'),
                        ),
```

- [ ] **Step 7: Run analyzer on modified files**

```bash
flutter analyze \
  lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart \
  lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart
```

Expected: no issues.

- [ ] **Step 8: Run full test suite**

```bash
flutter test
```

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add \
  lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart \
  lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart
git commit -m "feat: add duplicate badge in sync strip and Manage duplicates in settings"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| DuplicateGroup model | Task 1 |
| MergePreview model | Task 1 |
| URL normalization (lowercase, strip scheme/www/slash, keep host+path) | Task 2 |
| Username normalization (trim, lowercase) | Task 2 |
| Exclude empty-URL entries | Task 2 |
| findDuplicates — groups by key, 2+ entries, sort size desc → URL asc, entries newest first | Task 2 |
| previewMerge — notes, OTP, custom fields, attachments | Task 2 |
| VaultKdbxService.mergeEntries — copy fields, delete secondary | Task 4 |
| LoadDuplicates / DeleteDuplicateEntry / MergeDuplicateEntries events | Task 5 |
| VaultState.duplicateGroups + isDuplicatesLoading + duplicateGroupCount | Task 5 |
| Auto-recompute after InitializeVault / RefreshVault / ImportVaultEntriesFromCsv | Task 5 |
| DI registration | Task 5 |
| Dialog: title, subtitle, scrollable group list | Task 6 |
| _DuplicateGroupCard: header URL+username, entry sub-cards, actions row | Task 6 |
| "Delete older" button | Task 6 |
| "Merge" button (pairs only) + _MergeConfirmDialog | Task 6 |
| Groups of 3+: per-entry Delete, no Merge | Task 6 (showDeleteButton param) |
| Badge in sync strip | Task 7 |
| Settings "Manage duplicates" item with count subtitle | Task 7 |

**Placeholder scan:** None found.

**Type consistency check:**
- `DuplicateGroup.entries` — `List<VaultEntry>` — consistent across all tasks ✓
- `MergePreview.primary/.secondary` — `VaultEntry` ✓
- `VaultDuplicateService.findDuplicates` returns `List<DuplicateGroup>` — used in `_computeDuplicates` ✓
- `VaultDuplicateService().previewMerge(group.entries.first, group.entries.last)` matches signature ✓
- `DeleteDuplicateEntry(entry.id)` / `MergeDuplicateEntries(primaryId:, secondaryId:)` match event constructors ✓
- `state.duplicateGroups` and `state.duplicateGroupCount` used in badge and settings — added to state ✓
