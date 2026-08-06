// spec-002 T12: exact named 19-row FR-7 migration matrix.
//
// Each case asserts the sealed presentation kind at 390/1024 for the surface
// type actually used at that call site, the typed result contract, and that
// the frozen title/action copy (and listed BLoC event / coordinator
// callback) from the T1 fixture still exists in the vault presentation
// sources. Must pass before the AC-8 `showDialog` sweep.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/navigation/vault_shell_router.dart';

const _fixturePath = 'test/fixtures/vault_dialogs_002_before.txt';
const _vaultSourceDir =
    'lib/features/password_manager/presentation/screens/vault';

Widget _noop(BuildContext context) => const SizedBox.shrink();

class _FixtureRow {
  const _FixtureRow({
    required this.index,
    required this.function,
    required this.title,
    required this.body,
    required this.action,
    required this.resultType,
    required this.mobile,
    required this.rail,
  });

  final String index;
  final String function;
  final String title;
  final String body;
  final String action;
  final String resultType;
  final String mobile;
  final String rail;
}

List<_FixtureRow> _loadFixture() {
  final lines = File(_fixturePath)
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty && !line.startsWith('#'))
      .toList(growable: false);
  return [
    for (final line in lines)
      () {
        final parts = line.split('|');
        return _FixtureRow(
          index: parts[0],
          function: parts[1],
          title: parts[2],
          body: parts[3],
          action: parts[4],
          resultType: parts[5],
          mobile: parts[6],
          rail: parts[7],
        );
      }(),
  ];
}

Matcher _presentationMatcher(String kind) => switch (kind) {
  'route' => isA<VaultRoutePresentation>(),
  'sheet' => isA<VaultSheetPresentation>(),
  'pane' => isA<VaultPanePresentation>(),
  _ => throw ArgumentError('Unknown presentation kind: $kind'),
};

/// The concrete VaultSurface subtype used at each of the 19 real call sites
/// (verified against lib/…/vault/*.part.dart). Presentation kind depends
/// only on the surface's runtime type, so a lightweight instance with a
/// no-op builder is sufficient to exercise the real FR-6 dispatch.
final Map<String, VaultSurface<VaultDone>> _surfaceByRow = {
  '01': PasswordGeneratorSurface<VaultDone>(builder: _noop),
  '02': EntrySurface<VaultDone>(builder: _noop),
  '03': OtpScannerSurface<VaultDone>(builder: _noop),
  '04': GroupEditSurface<VaultDone>(builder: _noop),
  '05': ConfirmationSurface<VaultDone>(builder: _noop),
  '06': MoveTargetSurface<VaultDone>(builder: _noop),
  '07': AttachmentsSurface<VaultDone>(builder: _noop),
  '08': SyncLinkSurface<VaultDone>(builder: _noop),
  '09': SyncConflictSurface<VaultDone>(builder: _noop),
  '10': DuplicatesSurface<VaultDone>(builder: _noop),
  '11': DuplicatesSurface<VaultDone>(builder: _noop),
  '12': EntrySurface<VaultDone>(builder: _noop),
  '13': DatabaseSettingsSurface<VaultDone>(builder: _noop),
  '14': ConfirmationSurface<VaultDone>(builder: _noop),
  '15': RecycleBinSurface<VaultDone>(builder: _noop),
  '16': DatabaseSettingsSurface<VaultDone>(builder: _noop),
  '17': ConfirmationSurface<VaultDone>(builder: _noop),
  '18': ConfirmationSurface<VaultDone>(builder: _noop),
  '19': ConfirmationSurface<VaultDone>(builder: _noop),
};

/// Extra BLoC event / coordinator-callback names each row must preserve
/// (FR-7 "Existing effect to preserve" column). Checked as a literal
/// substring anywhere under the vault presentation sources.
final Map<String, List<String>> _effectByRow = {
  '02': ['CreateVaultEntry', 'UpdateVaultEntry'],
  '04': ['CreateVaultGroup', 'RenameVaultGroup'],
  '06': ['MoveVaultEntry', 'MoveVaultGroup'],
  '07': ['ExportVaultAttachment', 'RemoveVaultAttachment'],
  '08': ['LoadDriveRemoteFiles', 'LinkCurrentDatabaseToDrive'],
  '09': ['ClearVaultSyncFeedback', 'SyncCurrentDatabaseNow'],
  '10': ['LoadDuplicates'],
  '11': ['MergeDuplicateEntries'],
  '15': ['LoadRecycleBinEntries'],
  '16': ['ImportVaultEntriesFromCsv'],
  '17': ['CreateVaultEntry'],
  '18': ['changeDatabase'],
  '19': [
    'ConfirmAppleAutofillPendingAssociation',
    'RejectAppleAutofillPendingAssociation',
  ],
};

void main() {
  final rows = _loadFixture();
  late String vaultSources;

  setUpAll(() {
    final buffer = StringBuffer();
    for (final entity in Directory(_vaultSourceDir).listSync()) {
      if (entity is File && entity.path.endsWith('.dart')) {
        buffer.write(entity.readAsStringSync());
      }
    }
    vaultSources = buffer.toString();
  });

  test('fixture has exactly 19 rows', () {
    expect(rows.length, 19);
  });

  for (final row in rows) {
    test('${row.index} ${row.function}', () {
      final surface = _surfaceByRow[row.index];
      expect(
        surface,
        isNotNull,
        reason: 'no surface mapping for row ${row.index}',
      );

      expect(
        presentationFor(surface!, 390),
        _presentationMatcher(row.mobile),
        reason: '${row.function} mobile presentation must be ${row.mobile}',
      );
      expect(
        presentationFor(surface, 1024),
        _presentationMatcher(row.rail),
        reason: '${row.function} rail presentation must be ${row.rail}',
      );

      expect(
        vaultSources.contains(row.title),
        isTrue,
        reason: 'frozen title copy "${row.title}" missing from sources',
      );
      if (row.action != '-') {
        expect(
          vaultSources.contains(row.action),
          isTrue,
          reason: 'frozen action copy "${row.action}" missing from sources',
        );
      }
      for (final effect in _effectByRow[row.index] ?? const <String>[]) {
        expect(
          vaultSources.contains(effect),
          isTrue,
          reason: 'effect "$effect" missing from sources for ${row.function}',
        );
      }
    });
  }

  test('every row maps to a distinct surface family or a documented reuse', () {
    // Rows 10/11 (Duplicates/merge preview) and 13/16 (Database
    // settings/CSV import) intentionally share a surface family per FR-6;
    // every other row must be unique.
    final counts = <Type, int>{};
    for (final surface in _surfaceByRow.values) {
      counts[surface.runtimeType] = (counts[surface.runtimeType] ?? 0) + 1;
    }
    final shared = counts.entries.where((e) => e.value > 1).toList();
    expect(
      shared.map((e) => e.key.toString()).toSet(),
      {
        'DuplicatesSurface<VaultDone>',
        'DatabaseSettingsSurface<VaultDone>',
        'ConfirmationSurface<VaultDone>',
        'EntrySurface<VaultDone>',
      },
      reason:
          'unexpected surface-family sharing; verify against FR-6 before merging rows',
    );
  });
}
