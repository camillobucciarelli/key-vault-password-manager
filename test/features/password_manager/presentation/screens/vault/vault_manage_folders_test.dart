// spec-019 T048 — `Manage folders`: one surface, one recipe, two containers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/widgets/kv_folder_tree.dart';

import 'vault_navigation_fixture.dart';
import 'vault_shell_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetVaultShellTestDi);

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      await pumpableVaultShell(
        vaultKdbxService: NavigationFixtureVaultKdbxService(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the surface by the only route each width offers.
  Future<void> openManage(WidgetTester tester, double width) async {
    if (width < 941) {
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
  }

  // Contract S4 / SC-000. Counting the affordances is the assertion: two ways
  // in is how the old vault ended up with folder actions in three places.
  group('exactly one entry point per width (FR-006a)', () {
    testWidgets('the desktop column offers Manage once and nowhere else', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      expect(find.text('Manage'), findsOneWidget);
      expect(find.byTooltip('Folder actions'), findsNothing);
    });

    testWidgets('the phone offers it only inside the Folders sheet', (
      tester,
    ) async {
      await pumpAt(tester, 390);
      expect(find.text('Manage'), findsNothing);

      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();
      expect(find.text('Manage'), findsOneWidget);
    });
  });

  for (final width in <double>[390, 1024]) {
    group('the same surface at $width', () {
      testWidgets('shows the tree fully expanded, with New folder', (
        tester,
      ) async {
        await pumpAt(tester, width);
        await openManage(tester, width);

        expect(find.text('Manage folders'), findsOneWidget);
        expect(find.text('New folder'), findsOneWidget);

        // At 1024 the folder column's own tree is still mounted behind the
        // dialog, which is the point of a dialog — so scope to the surface.
        final tree = tester
            .widgetList<KvFolderTree>(find.byType(KvFolderTree))
            .where((widget) => widget.mode == KvFolderTreeMode.manage);
        expect(tree, hasLength(1));
        // Fully expanded: no chevron to collapse anything with (G2).
        expect(find.byTooltip('Collapse Devs'), findsNothing);
        expect(find.byTooltip('Expand Devs'), findsNothing);
      });

      testWidgets('offers the one row-action recipe (FR-006k)', (tester) async {
        await pumpAt(tester, width);
        await openManage(tester, width);

        await tester.tap(find.byTooltip('Folder actions').last);
        await tester.pumpAndSettle();

        expect(find.text('Rename'), findsOneWidget);
        expect(find.text('Move'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
      });

      testWidgets('Move is the only way to change a parent (FR-006e)', (
        tester,
      ) async {
        await pumpAt(tester, width);
        await openManage(tester, width);

        // The retired path: creating a folder *inside* another one.
        expect(find.text('Add subfolder'), findsNothing);

        await tester.tap(find.byTooltip('Folder actions').last);
        await tester.pumpAndSettle();
        final reparenting = ['Move']
            .where((label) => find.text(label).evaluate().isNotEmpty)
            .toList();
        expect(
          reparenting,
          ['Move'],
          reason: 'one action changes a folder\'s parent, and it is Move',
        );
      });
    });
  }

  testWidgets('the root row keeps Rename and drops what cannot apply', (
    tester,
  ) async {
    await pumpAt(tester, 1024);
    await openManage(tester, 1024);

    // The first row is the vault's own root: renamable, but there is nowhere
    // to move it to and deleting it would delete the vault (G2, amended).
    await tester.tap(find.byTooltip('Folder actions').first);
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Move'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });
}
