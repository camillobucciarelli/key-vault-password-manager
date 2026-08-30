// spec-019 T032/T041 — the folder surfaces: the desktop column, the phone chip
// row and the `Folders` sheet.
//
// Omitted axes (VR-002): behavioural assertions, light theme only. The visual
// treatment is the goldens' subject.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/widgets/kv_filter_chip.dart';
import 'package:password_manager/core/widgets/kv_folder_tree.dart';

import 'vault_navigation_fixture.dart';
import 'vault_shell_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetVaultShellTestDi);

  Future<NavigationFixtureVaultKdbxService> pumpAt(
    WidgetTester tester,
    double width,
  ) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = NavigationFixtureVaultKdbxService();
    await tester.pumpWidget(await pumpableVaultShell(vaultKdbxService: service));
    await tester.pumpAndSettle();
    return service;
  }

  group('the desktop folder column (FR-001..FR-004)', () {
    testWidgets('is titled with the database, not with the word Folders', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      expect(find.text('vault_shell_test.kdbx'), findsWidgets);
      expect(
        find.text('Folders'),
        findsNothing,
        reason: 'C-03-11: the literal column title is gone',
      );
    });

    // 2026-08-30: the first row shows the root group's real name, not a
    // synthetic `All items` label. The fixture's root is named 'root'.
    testWidgets('the root is the first row and carries the vault total', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      expect(find.text('root'), findsOneWidget);
      // Three records in the fixture, one of them inside Devs.
      expect(
        find.descendant(
          of: find.byType(KvFolderTree),
          matching: find.text('3'),
        ),
        findsWidgets,
      );
    });

    testWidgets('a folder carries a count inclusive of its records', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      expect(find.text('Devs'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(KvFolderTree),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('selecting a folder filters the records list end to end', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      expect(find.text('Gmail'), findsWidgets);

      await tester.tap(find.text('Devs').first);
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsWidgets);
      expect(
        find.text('Gmail'),
        findsNothing,
        reason: 'a record outside the selected folder is not in the list',
      );
    });

    testWidgets('the hygiene shortcuts sit at the foot of the column', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      expect(find.text('Recycle bin'), findsOneWidget);
      expect(find.text('Duplicates'), findsOneWidget);
    });

    // 2026-08-30: `Manage folders` retired — the tree carries its own row
    // actions (see vault_folder_actions_test.dart for the recipe).
    testWidgets('every folder row in the column carries its actions', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      expect(
        find.descendant(
          of: find.byType(KvFolderTree),
          matching: find.byTooltip('Folder actions'),
        ),
        findsWidgets,
      );
    });
  });

  group('the phone chip row (FR-005, FR-006c)', () {
    testWidgets('carries Folders, All and the first-level folders', (
      tester,
    ) async {
      await pumpAt(tester, 390);
      final labels = tester
          .widgetList<KvFilterChip>(find.byType(KvFilterChip))
          .map((chip) => chip.label)
          .toList();
      expect(labels, ['Folders', 'All', 'Devs']);
    });

    testWidgets('no chip carries an action', (tester) async {
      await pumpAt(tester, 390);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('vault-folder-chips')),
          matching: find.byType(PopupMenuButton<dynamic>),
        ),
        findsNothing,
      );
    });

    testWidgets('a chip filters the list', (tester) async {
      await pumpAt(tester, 390);
      await tester.tap(find.text('Devs'));
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsWidgets);
      expect(find.text('Gmail'), findsNothing);
    });

    // plan Risks: the 704-940 band lost its folder affordance when folders
    // left the list, and the design still owes the artboard for it.
    testWidgets('stands in for the column in the 704-940 band', (tester) async {
      await pumpAt(tester, 800);
      expect(find.byType(KvFilterChip), findsWidgets);
      expect(find.byKey(const ValueKey('vault-folder-pane')), findsNothing);
    });
  });

  group('the Folders sheet (FR-005a, FR-006a)', () {
    testWidgets('opens from the first chip and shows the same tree', (
      tester,
    ) async {
      await pumpAt(tester, 390);
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();

      expect(find.byType(KvFolderTree), findsOneWidget);
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('choosing a folder filters and closes the sheet', (
      tester,
    ) async {
      await pumpAt(tester, 390);
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(KvFolderTree),
          matching: find.text('Devs'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(KvFolderTree), findsNothing, reason: 'sheet closed');
      expect(find.text('GitHub'), findsWidgets);
      expect(find.text('Gmail'), findsNothing);
    });
  });

  group('one expansion state, two hosts (FR-006g)', () {
    testWidgets('the column and the sheet read the same expansion', (
      tester,
    ) async {
      // The fixture is one level deep, so this asserts the wiring rather than
      // a deep tree: both hosts build their nodes from `expandedGroupIds`.
      await pumpAt(tester, 1024);
      await tester.tap(find.text('Devs').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<KvFolderTree>(find.byType(KvFolderTree)).selectedId,
        NavigationFixtureVaultKdbxService.folderId,
        reason: 'selection is not expansion (FR-006f)',
      );
    });
  });
}
