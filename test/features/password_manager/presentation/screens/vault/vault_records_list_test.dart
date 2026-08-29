// spec-019 T033/T040/T042 — the records list is a list of records.
//
// Omitted axes (VR-002): behavioural, light theme only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/widgets/kv_folder_tree.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_state.dart';

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

  /// The list pane's own subtree at wide widths; the whole screen on a phone.
  Finder listPane() => find.byKey(const ValueKey('vault-list-pane'));

  group('FR-007 / C-03-03 — no folder is a row of the list', () {
    for (final width in <double>[390, 800, 1024]) {
      testWidgets('at $width the list contains no folder tree', (tester) async {
        await pumpAt(tester, width);
        final inList = find.descendant(
          of: width >= 704 ? listPane() : find.byType(MaterialApp),
          matching: find.byType(KvFolderTree),
        );
        expect(
          inList,
          findsNothing,
          reason: 'the folder tree belongs to the folder surfaces, not here',
        );
      });
    }
  });

  group('FR-006i — the count line', () {
    testWidgets('says how many records are shown', (tester) async {
      await pumpAt(tester, 1024);
      await tester.tap(find.text('Devs').first);
      await tester.pumpAndSettle();
      expect(find.text('1 items'), findsOneWidget);
    });

    testWidgets('declares when the count includes subfolders', (tester) async {
      await pumpAt(tester, 1024);
      // `All items` is selected by default and the root has a subfolder.
      expect(find.text('3 items · incl. subfolders'), findsOneWidget);
    });
  });

  testWidgets('FR-008 — the search placeholder carries the count', (
    tester,
  ) async {
    await pumpAt(tester, 1024);
    expect(find.text('Search 3 items'), findsOneWidget);
  });

  testWidgets('FR-006j — a record on loan from a subfolder says so', (
    tester,
  ) async {
    await pumpAt(tester, 1024);
    expect(find.text('dev · in Devs'), findsOneWidget);
  });

  group('FR-009 — the sort control', () {
    testWidgets('offers exactly three orders and marks the active one', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      await tester.tap(find.byTooltip('Sort records'));
      await tester.pumpAndSettle();

      expect(find.text('Title A→Z'), findsOneWidget);
      expect(find.text('Title Z→A'), findsOneWidget);
      // The active order also labels the closed control, hence two.
      expect(find.text('Username A→Z'), findsNWidgets(2));

      final checked = tester
          .widgetList<CheckedPopupMenuItem<VaultEntrySort>>(
            find.byType(CheckedPopupMenuItem<VaultEntrySort>),
          )
          .where((item) => item.checked);
      expect(checked, hasLength(1));
      expect(checked.single.value, VaultEntrySort.usernameAsc);
    });

    testWidgets('the choice survives a folder change and a search', (
      tester,
    ) async {
      await pumpAt(tester, 1024);
      await tester.tap(find.byTooltip('Sort records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title Z→A'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Devs').first);
      await tester.pumpAndSettle();
      expect(find.text('Title Z→A'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Git');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Title Z→A'), findsOneWidget);
    });
  });

  group('FR-009a / FR-014a / FR-014b — the phone Sort sheet', () {
    testWidgets('opens from the header and offers the same three orders', (
      tester,
    ) async {
      await pumpAt(tester, 390);
      await tester.tap(find.byTooltip('Sort records'));
      await tester.pumpAndSettle();

      expect(find.text('Sort'), findsOneWidget);
      expect(find.byType(RadioListTile<VaultEntrySort>), findsNWidgets(3));
      final selected = tester
          .widgetList<RadioListTile<VaultEntrySort>>(
            find.byType(RadioListTile<VaultEntrySort>),
          )
          .where((tile) => tile.value == VaultEntrySort.usernameAsc);
      expect(selected, hasLength(1));
    });

    testWidgets('choosing applies immediately and dismisses', (tester) async {
      await pumpAt(tester, 390);
      await tester.tap(find.byTooltip('Sort records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title A→Z'));
      await tester.pumpAndSettle();

      expect(find.byType(RadioListTile<VaultEntrySort>), findsNothing);
      // Title ascending: Banca Sella, Gmail (GitHub is inside Devs but the
      // default folder is All items, so all three are listed).
      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where(
            (data) => const {
              'Banca Sella',
              'GitHub',
              'Gmail',
            }.contains(data),
          )
          .toList();
      expect(titles, ['Banca Sella', 'GitHub', 'Gmail']);
    });

    testWidgets('carries no filter of any kind (FR-014b)', (tester) async {
      await pumpAt(tester, 390);
      await tester.tap(find.byTooltip('Sort records'));
      await tester.pumpAndSettle();

      // Scoped to the sheet: the chip row is still on screen behind it, and
      // its `Folders` chip is the folder filter, which is exactly where
      // FR-014b says the folder filter belongs.
      final sheet = find.ancestor(
        of: find.byType(RadioListTile<VaultEntrySort>).first,
        matching: find.byType(Column),
      );
      for (final forbidden in const [
        'Folders',
        'Health',
        'Filter',
        'Advanced',
      ]) {
        expect(
          find.descendant(of: sheet, matching: find.text(forbidden)),
          findsNothing,
          reason: '$forbidden is not a sort order (FR-014b)',
        );
      }
    });
  });

  group('FR-010 / C-03-04 — one-tap copy from the row', () {
    testWidgets('copies without opening the record (SC-003)', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpAt(tester, 390);
      await tester.tap(find.byTooltip('Copy password').first);
      await tester.pumpAndSettle();

      expect(copied, [NavigationFixtureVaultKdbxService.bank.password]);
      // The confirmation is the detail's own string, byte for byte.
      expect(find.text('Copied password.'), findsOneWidget);
      // …and the record was never opened.
      expect(find.text('Copy username'), findsNothing);

      // Drain the guard's 30 s clear timer so the binding does not report it
      // as pending. Its presence is the point: the row's copy goes through
      // `ClipboardGuard`, so the same auto-clear covers it as the detail's.
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
    });

    testWidgets('the row still announces its health in words', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAt(tester, 390);

      expect(
        find.bySemanticsLabel(RegExp('Password healthy')),
        findsWidgets,
        reason: 'colour alone is not a signal (Constitution V)',
      );

      handle.dispose();
    });
  });

  group('FR-012 — the record actions survive at every width', () {
    for (final width in <double>[650, 1024]) {
      testWidgets('a list row still offers all four at $width', (tester) async {
        await pumpAt(tester, width);
        await tester.tap(find.byTooltip('Record actions').first);
        await tester.pumpAndSettle();

        for (final action in const [
          'Edit',
          'Move',
          'Attachments',
          'Delete',
        ]) {
          expect(find.text(action), findsWidgets, reason: action);
        }
      });
    }
  });
}
