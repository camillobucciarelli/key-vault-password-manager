// spec-003 T1/T21: copy preservation comparison helper.
//
// Parses `strings_003_before.txt` (grouped by originating source file) and
// asserts every literal snapshot line still appears, byte-identical, in the
// current source of the file(s) that now render that surface — even if the
// literal moved to a new widget/file during the restyle. Only failures are
// reported so a human can confirm each is on the approved-additions list
// (or a genuine regression to fix).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Maps each snapshot section (source file name as it existed pre-spec-003)
/// to the current file(s) whose concatenated source must still contain
/// every literal from that section.
const _sectionToCurrentFiles = <String, List<String>>{
  'database_selection_screen.dart': [
    'lib/features/password_manager/presentation/screens/database_selection_screen.dart',
    'lib/features/password_manager/presentation/screens/welcome_screen.dart',
    'lib/features/password_manager/presentation/widgets/database/database_selection_sheets.dart',
    'lib/features/password_manager/presentation/widgets/database/drive_picker_sheet.dart',
    'lib/features/password_manager/presentation/widgets/database/recent_databases_section.dart',
  ],
  'create_database_dialog.dart': [
    'lib/features/password_manager/presentation/screens/create_database_screen.dart',
  ],
  'database_unlock_screen.dart': [
    'lib/features/password_manager/presentation/screens/database_unlock_screen.dart',
    'lib/features/password_manager/presentation/screens/database_unlock_widgets.part.dart',
    'lib/features/password_manager/presentation/widgets/database/face_id_prompt_sheet.dart',
  ],
  'database_unlock_widgets.part.dart': [
    'lib/features/password_manager/presentation/screens/database_unlock_widgets.part.dart',
  ],
  'internal_key_file_manager_dialog.dart': [
    // Unchanged: still used by the (out-of-scope) vault-shell key-file
    // manager entry point. spec-003 adds a second, sheet-based surface
    // (`internal_key_file_manager_sheet.dart`) for the unlock screen only.
    'lib/features/password_manager/presentation/widgets/internal_key_file_manager_dialog.dart',
    'lib/features/password_manager/presentation/widgets/internal_key_file_manager_sheet.dart',
  ],
  'recent_databases_section.dart': [
    'lib/features/password_manager/presentation/widgets/database/recent_databases_section.dart',
  ],
  'database_item_tile.dart': [
    'lib/features/password_manager/presentation/widgets/database/database_item_tile.dart',
  ],
  'database_action_menu.dart': [
    'lib/features/password_manager/presentation/widgets/database/database_action_menu.dart',
  ],
};

/// Literals whose visible surface was intentionally superseded by a
/// spec-003 layout redesign (not an accidental drop). Each entry is
/// reviewed and justified in `specs/003-database-and-unlock/spec.md`'s
/// FR-1/FR-3/FR-5 sections: the old "picker dialog"/"two-step unlock
/// narrative" UI those strings belonged to no longer exists as a surface.
const _approvedSupersededLiterals = <String>{
  // FR-3: Drive picker is now a tap-to-select sheet (skeleton loading, no
  // blocking "connecting" dialog, no separate list-then-Continue dialog,
  // no per-row modified date).
  'Connecting to Google Drive...',
  'No .kdbx files found in your Google Drive.',
  'Select Drive database',
  'Choose a .kdbx file from Google Drive.',
  'Unknown date',
  'Modified: ',
  'Continue',
  // FR-1: recent-list header/rows redesigned per spec ("Recent" label,
  // active-row accent tint instead of a "Most recent" text badge).
  'Managed databases',
  'Most recent',
  // spec 015 FR-1..FR-14: the create wizard collapsed to two steps with a
  // single credentials step — optional password, a three-way exclusive key
  // control replacing the switch-plus-button pair, and generation at
  // submit. The "Prepare generated key file" button, its picker dialogs,
  // the 'database.key' on-disk name (opaque since spec 014 FR-3) and the
  // snackbar tied to the deleted control were retired with the surface.
  'Please enter a password or choose a Key File.',
  'Key File (optional)',
  'Generate key file automatically',
  'On native platforms it will be saved in app internal storage.',
  'Choose the generated key file option to continue.',
  'Prepare generated key file',
  'Choose key file destination',
  'Generated key file will be saved in app internal storage',
  'Remove generated key file path',
  'Select Key File',
  'Select destination for generated key file',
  'Select destination folder for generated key file',
  'database.key',
  // FR-2: create wizard has per-step titles ("Step N of 3" + step-specific
  // heading) instead of one dialog title.
  'New Database Credentials',
  // FR-5: unlock is no longer a two-step "Step 1 of 2 / Step 2 of 2"
  // narrative inside one card — biometric gate, ready and decrypting are
  // now distinct phase-driven screens (C-4).
  'Unlock active vault by choosing at least one credential method.',
  'You can use the master password, a key file, or both.',
  'Step 1 of 2 - Verify identity',
  'Complete biometric verification before manual unlock.',
  'Biometric check completed.',
  'Biometric check not required for this vault.',
  'Step 2 of 2 - Provide unlock credentials',
  'Ready to unlock with: ',
  ' + ',
  'no credentials selected',
  'Select a key file or enter your master password to continue.',
  'Biometric verification is still required before unlocking.',
  // FR-5 explicitly approves new Face ID copy replacing these two exact
  // strings (spec-003 copy contract: "decrypting and Face ID strings").
  'Enable biometric protection?',
  'This database came from Google Drive. Do you want to require biometric authentication before unlock when available?',
  // FR-5 mock alignment (post-round mock delivery): the always-visible
  // "Select key file" outlined button is superseded by the "Use a key
  // file" inline link shown only when no key file is selected yet;
  // `_KeyFileSelector` is now only built once a key file exists.
  'Select key file',
  // OAuth env-key rename (refactor/oauth-env-key-names): dart-define keys now
  // map 1:1 to GCP OAuth client types, so the error copy references the new
  // key names (GOOGLE_WEB_CLIENT_ID / GOOGLE_IOS_CLIENT_ID).
  'Android Google Sign-In is not configured. Check GOOGLE_ANDROID_SERVER_CLIENT_ID.',
  'iOS Google Sign-In is not configured. Check GOOGLE_MOBILE_CLIENT_ID.',
  // Approved post-spec reconnect UX: the Drive surface stays open and exposes
  // an inline Reconnect CTA, so telling the user to open the surface again is
  // stale. The frozen pre-spec fixture remains unchanged as evidence.
  'Google Drive session expired or unavailable. Tap "Open from Google Drive" again and complete reconnection.',
};

void main() {
  test('every pre-spec-003 literal still appears in its surface\'s current '
      'source, or is on the reviewed approved-superseded list', () {
    final projectRoot = _findProjectRoot();
    final fixtureFile = File(
      p.join(projectRoot, 'test', 'fixtures', 'strings_003_before.txt'),
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
          'Copy preservation violation(s) — each of these pre-spec-003 '
          'literals must still exist verbatim in its mapped file(s), '
          'unless newly approved by the spec-003 copy contract:\n'
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
