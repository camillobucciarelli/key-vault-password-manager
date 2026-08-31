// spec-004 T22: copy preservation comparison helper.
//
// Same pattern as strings_003_diff_test.dart: parses
// `strings_004_before.txt` (grouped by originating source file) and asserts
// every literal snapshot line still appears, byte-identical, in the current
// source of the file(s) that now render that surface — even though the
// content moved into new widgets/files during the restyle. Only failures
// are reported so a human can confirm each is on the reviewed
// approved-superseded list (or a genuine regression to fix).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Maps each snapshot section (source file name as it existed pre-spec-004)
/// to the current file(s) whose concatenated source must still contain
/// every literal from that section.
const _sectionToCurrentFiles = <String, List<String>>{
  'vault_entries_details.part.dart': [
    'lib/features/password_manager/presentation/screens/vault/vault_entries_details.part.dart',
    'lib/features/password_manager/presentation/screens/vault/vault_entry_detail.part.dart',
    'lib/features/password_manager/presentation/widgets/entry/revealed_password_row.dart',
    // spec-006 T4/T5: `_LockOverlay`/`_PrivacyOverlay` moved out of
    // vault_entries_details.part.dart into their own
    // vault_lock_overlay.part.dart — "Unlock vault" (the biometric
    // `authenticate(reason:)` string) now lives there.
    'lib/features/password_manager/presentation/screens/vault/vault_lock_overlay.part.dart',
    // spec-019 T026: the folder row left the records list for the folder
    // column and `Manage folders`, so the strings it carried now live in the
    // shared tree widget. Moved, not dropped.
    'lib/core/widgets/kv_folder_tree.dart',
  ],
  'vault_dialog_password.part.dart': [
    // spec-005: moved presentation/utils -> domain/utils (pure logic, no
    // Flutter dependency; the new vault_health_service.dart needed it from
    // domain, and domain code must not import presentation code).
    'lib/features/password_manager/domain/utils/password_strength.dart',
    'lib/features/password_manager/presentation/screens/vault/vault_generator.part.dart',
    'lib/features/password_manager/presentation/screens/vault/vault_entry_editor.part.dart',
  ],
  'vault_entries.part.dart': [
    'lib/features/password_manager/presentation/screens/vault/vault_entries.part.dart',
  ],
};

/// Literals whose visible surface was intentionally superseded by a
/// spec-004 layout redesign (not an accidental drop). Each entry is
/// reviewed and justified here — see spec-004's spec.md FR-1/FR-2/FR-3/
/// FR-5/FR-6 for the corresponding mock/requirement.
const _approvedSupersededLiterals = <String>{
  // 2026-08-31, user-directed detail cleanup: custom fields render inline as
  // ordinary field rows of the detail, so the "Custom fields" sheet (and its
  // title) no longer exists. The fields themselves and their copy actions
  // survive on the rows.
  'Custom fields',
  // ── spec-019, journey 03 to navigation model 1a ────────────────────────
  // The records list stopped rendering the folder tree (FR-007, C-03-03), so
  // the folder row's own chrome went with it. Each of these described a
  // folder row inside the list, and there is no longer such a thing:
  //
  //   * the chevron tooltips are now per-folder in the column
  //     ("Expand Work" / "Collapse Work"), because a tree of folders needs to
  //     say WHICH folder it is offering to unfold;
  //   * the `ROOT` badge marked the root folder among the list's rows; the
  //     column's first row is `All items` and needs no badge to say so;
  //   * " folders • " was part of the folder row's subtitle, and management
  //     rows carry no subtitle at all (FR-006b).
  'Expand folder',
  'Collapse folder',
  'ROOT',
  ' folders • ',
  // FR-008 / C-03-05: the search field's placeholder carries the count of what
  // it searches ("Search 42 items"). It also no longer searches folders, since
  // folders are not in the list.
  'Search records and folders',
  // The empty state pointed at affordances that no longer exist. "the folder
  // menu" was the folder row's ••• , deleted with the folder rows; the copy
  // now points at the add button. And a search that finds nothing finds no
  // records — it was never going to find a folder, because the list holds
  // none.
  'Use the folder menu to add records or subfolders.',
  'No records or folders found',
  // FR-7: the tablet metadata grid uses the spec's own literal labels
  // ("Created", "Updated", "Last password change") instead of the old
  // Record-info dialog's ("Last modified", "Password changed").
  'Last modified',
  'Password changed',
  // FR-1/T3: attachments and custom fields are now reached through a
  // "More" chip (count + tap) instead of an always-expanded section with
  // its own "Manage" button / descriptive caption.
  'Manage',
  'Stored separately from standard record fields.',
  // Dead default value in the old `_EntryFieldCard(emptyLabel: 'Not set')`
  // — every call site always passed an explicit override, so this string
  // was never actually rendered; dropped with the widget rewrite.
  'Not set',
  // FR-2: the TOTP row's remaining-seconds count moved from the field
  // label's parenthetical ("One-time code (18s)") into the leading circle
  // badge (mock: 38px circle showing "18s"), so the label is now the
  // fixed string "One-time code" without a trailing "(".
  'One-time code (',
  // FR-6: the generator is now a bottom sheet (dismissed by swipe/tap-
  // outside, per the mock, which shows no Cancel button on the generator
  // sheet) instead of an AlertDialog with explicit Cancel/Generate
  // actions; the primary action is the mock's literal "Use this password".
  'Cancel',
  'Generate',
  // T3: copy affordances are now a permanently-visible 36-circle icon per
  // row (PIXEL_SPEC "Field row") instead of an implicit "tap to open a
  // copy menu" hint.
  'Tap a field to open copy action',
  // FR-1: Website/Notes rows are only rendered when the entry actually has
  // a value (matching the mock, whose example entries always have data);
  // Username/Password still always render with their "not set" fallback.
  'URL not set',
  'Notes not set',
  // The "Record info" dialog (with its own "Close" button) is gone —
  // metadata is inline in the tablet detail pane only (FR-7); there is no
  // mobile equivalent trigger/dialog to preserve.
  'Close',
};

void main() {
  test('every pre-spec-004 literal still appears in its surface\'s current '
      'source, or is on the reviewed approved-superseded list', () {
    final projectRoot = _findProjectRoot();
    final fixtureFile = File(
      p.join(projectRoot, 'test', 'fixtures', 'strings_004_before.txt'),
    );
    expect(fixtureFile.existsSync(), isTrue);

    final lines = fixtureFile.readAsLinesSync();
    String? currentSection;
    final missing = <String>[];
    var checked = 0;

    for (final rawLine in lines) {
      final sectionMatch = RegExp(r'^## (.+)$').firstMatch(rawLine);
      if (sectionMatch != null) {
        currentSection = sectionMatch.group(1);
        continue;
      }
      if (rawLine.startsWith('#') || rawLine.trim().isEmpty) {
        continue;
      }
      final section = currentSection;
      if (section == null) {
        continue;
      }
      final files = _sectionToCurrentFiles[section];
      if (files == null) {
        continue;
      }

      final haystack = files
          .map(
            (relative) =>
                File(p.join(projectRoot, relative)).readAsStringSync(),
          )
          .join('\n');
      checked += 1;
      if (!haystack.contains(rawLine) &&
          !_approvedSupersededLiterals.contains(rawLine)) {
        missing.add('[$section] "$rawLine"');
      }
    }

    expect(
      checked,
      greaterThan(50),
      reason: 'Sanity check: the fixture should have parsed >50 literals.',
    );

    expect(
      missing,
      isEmpty,
      reason:
          'Copy preservation violation(s) — each of these pre-spec-004 '
          'literals must still exist verbatim in its mapped file(s), '
          'unless newly approved by the spec-004 copy contract:\n'
          '${missing.join('\n')}',
    );
  });
}

String _findProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate project root (pubspec.yaml).');
    }
    dir = parent;
  }
}
