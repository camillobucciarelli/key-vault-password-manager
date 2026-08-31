import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec 019 T003 — the inventory of every action the vault offers, pinned
/// before journey 03 is restructured.
///
/// Spec 019 moves folder management out of the records list and into its own
/// surface, and rehomes the sync strip's actions. FR-021 and US3 say that not
/// one action may be *lost* on the way: a move is allowed, a disappearance is
/// not. A widget test cannot say that, because it can only assert about the
/// surfaces it happens to mount — the action that quietly stops being built is
/// exactly the one no test opens.
///
/// So the inventory is taken from the source instead, mechanically: every
/// string literal passed to a "tooltip:" or "label:" parameter under the vault
/// screens. That is a superset of the action labels (it also catches field and
/// settings labels), which is the safe direction to err in — it fails when copy
/// disappears, never when it merely moves between files.
///
/// **When this test fails**: if the string moved to another vault file, the set
/// is unchanged and the test stays green — nothing to do. If the set shrank,
/// an action was dropped; restore it. Only edit the pinned list below when the
/// spec deliberately removes copy, and say which requirement allows it.
/// Constitution VI: copy is preserved verbatim unless a spec changes it.
void main() {
  // The one string removed since this inventory was taken, and the section
  // that authorises it: spec 019 §"Behaviour this spec deliberately changes",
  // FR-006e — `Add subfolder` is retired. A folder is created with
  // `New folder` and given a parent with `Move…`, so there is one way to
  // nest instead of two that could disagree. Nothing else may leave this
  // list without the same kind of note (T049, SC-004).
  const inventory = <String>[
    'Add record',
    'Android autofill',
    'Appearance',
    'Apply',
    'Attachment',
    'Attachments',
    'Auto-sync',
    'Back',
    'Cancel',
    'Change database',
    'Check again',
    'Close',
    'Connect Google Drive',
    'Copy',
    // 2026-08-31: the `Copy password` / `Copy username` pills were removed
    // at the user's direction — every field row carries its own copy button
    // (tooltip 'Copy', pinned above), so the capability survives; only the
    // redundant pills left.
    'Custom field',
    'Database settings',
    'Delete',
    'Desktop browser extension',
    'Discard',
    'Disconnect Google Drive',
    'Dismiss',
    'Drive',
    'Edit',
    'Empty bin',
    'Entry',
    'Export database backup',
    'Export key file',
    'Folder actions',
    'Generate secure password',
    'Google Drive',
    'Import from CSV',
    'Keep editing',
    'Keep local',
    'KeyVault is backgrounded',
    'Link',
    'Link database to Drive',
    'Lock vault',
    'Lowercase letters (a-z)',
    'Manage duplicates',
    'Merge and move duplicate',
    'Move',
    'Move this record to recycle bin?',
    'Notes',
    'Numbers (0-9)',
    'One-time code',
    'Open system settings',
    'Password',
    'Password generator',
    'Paste the URI instead',
    'Permanently delete this empty folder?',
    'Reconnect',
    'Record actions',
    'Recycle bin',
    'Refresh recycle bin',
    'Regenerate',
    'Remove attachment',
    'Remove field',
    'Rename',
    'Reset to defaults',
    'Save the URI',
    'Scan QR',
    'Show password',
    'Special characters (!@#...)',
    'Target',
    'This device',
    'Tools',
    'Unlock with biometrics',
    'Unlock with Face ID',
    'Uppercase letters (A-Z)',
    'Use password',
    'Use remote',
    'Username',
    'Vault',
    'Website',
  ];

  test('every vault action present at spec 019 HEAD survives', () {
    final dir = Directory(
      'lib/features/password_manager/presentation/screens/vault',
    );
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'run from the package root; vault screens directory not found',
    );

    // Spec 019 moves the folder actions into `KvFolderTree` and rehomes the
    // sync strip's, so the shared widgets are part of the search space: an
    // action that moved there has not been lost.
    final sources = <File>[
      ...dir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.dart'),
      ),
      ...Directory('lib/core/widgets')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      File(
        'lib/features/password_manager/presentation/screens/vault_screen.dart',
      ),
    ];

    // Single-quoted literals with no escapes and no interpolation: a label
    // built from an expression is not a fixed string, so it cannot be pinned.
    // Named `tooltip:`/`label:` arguments, plus the bare `Text('…')` a menu
    // item is built from — spec 019 moved the folder actions into a widget
    // that builds its items that way.
    final pattern = RegExp(
      r"(?:(?:tooltip|label): |Text\()'([^'\\$]*)'",
    );
    final found = <String>{};
    for (final file in sources) {
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        found.add(match.group(1)!);
      }
    }

    final missing = inventory.where((a) => !found.contains(a)).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'these vault actions existed before spec 019 and are now gone. '
          'Moving one to another vault file keeps this green; only a deletion '
          'fails it.',
    );
  });
}
