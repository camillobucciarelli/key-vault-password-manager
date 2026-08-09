// Copilot review fix (spec-005 PR #9): `_selectedId` in
// `_RemoteFilePickerScreenState` used to only ever be assigned once
// (`_selectedId ??= state.remoteDriveFiles.first.id`). If the user typed a
// search query that removed the currently-selected file from the list, the
// stale id survived — no row showed as selected, yet "Link" stayed enabled
// and would have completed with an id no longer visible to the user.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_account_summary.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/presentation/widgets/sync/remote_file_row.dart';

import '../../coordinators/fake_database_ports.dart';
import 'vault_shell_test_utils.dart';

const _fileA = DriveRemoteFile(id: 'a1', name: 'Alpha.kdbx');
const _fileB = DriveRemoteFile(id: 'b1', name: 'Beta.kdbx');

/// Connected but not-yet-linked repo so the Sync tab renders the "Pick an
/// existing .kdbx" entry point. `listRemoteFiles` filters by query the same
/// way the real Drive API search would, so typing in the search box can
/// remove a file from the list — the scenario the fix targets.
class _FakeUnlinkedSyncRepository extends FakeDatabaseSyncRepository {
  @override
  Future<bool> isConnected() async => true;

  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) async => null;

  @override
  Future<List<DatabaseSyncMapping>> getAllMappings() async => const [];

  @override
  Future<DriveAccountSummary> getConnectedAccount() async =>
      DriveAccountSummary.fallback;

  @override
  Future<List<DriveRemoteFile>> listRemoteFiles({String? query}) async {
    const all = [_fileA, _fileB];
    if (query == null || query.isEmpty) return all;
    return all
        .where((f) => f.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() async {
    await (FontLoader(
      'Caprasimo',
    )..addFont(rootBundle.load('assets/fonts/Caprasimo-Regular.ttf'))).load();
    await (FontLoader('Figtree')
          ..addFont(rootBundle.load('assets/fonts/Figtree-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Figtree-Bold.ttf')))
        .load();
  });

  testWidgets(
    'stale selection is dropped when the filtered list no longer contains it',
    (tester) async {
      addTearDown(resetVaultShellTestDi);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        await pumpableVaultShell(
          databaseSyncRepository: _FakeUnlinkedSyncRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pick an existing .kdbx'));
      await tester.pumpAndSettle();

      // Default selection is the first row (Alpha, id a1).
      expect(
        tester
            .widgetList<RemoteFileRow>(find.byType(RemoteFileRow))
            .where((r) => r.selected)
            .single
            .file
            .id,
        'a1',
      );

      // User selects Beta instead.
      await tester.tap(find.text('Beta.kdbx'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<RemoteFileRow>(find.byType(RemoteFileRow))
            .where((r) => r.selected)
            .single
            .file
            .id,
        'b1',
      );

      // User types a query that filters Beta out of the results.
      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();

      // Beta's row is gone entirely — the stale id must not survive.
      expect(find.text('Beta.kdbx'), findsNothing);
      final rows = tester.widgetList<RemoteFileRow>(find.byType(RemoteFileRow));
      expect(rows, hasLength(1));
      // The fix re-selects the first (only) visible file rather than
      // leaving a phantom selection pointing at the now-invisible 'b1'.
      expect(rows.single.file.id, 'a1');
      expect(rows.single.selected, isTrue);

      // "Link" is enabled and, if tapped, can only ever complete with a
      // file id that is actually visible in the current list.
      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Link')).onPressed,
        isNotNull,
      );
    },
  );
}
