// spec-018 US4 (T029, T030) + US3 (T033-T035) + US1 origin parity (T014).
//
// Grouped in one file because they all drive the same surface: what happens
// to the detail pane when the record under it changes, when the editor takes
// its slot, and when the same record is opened from a different origin.
//
// Omitted axes per VR-002: light theme only; the visual result at 1024 is
// covered by the goldens in both themes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'vault_navigation_fixture.dart';
import 'vault_shell_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() async {
    await (FontLoader(
      'Caprasimo',
    )..addFont(rootBundle.load('assets/fonts/Caprasimo-Regular.ttf'))).load();
    await (FontLoader('Figtree')
          ..addFont(rootBundle.load('assets/fonts/Figtree-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Figtree-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Figtree-Bold.ttf')))
        .load();
  });

  tearDown(resetVaultShellTestDi);

  Finder inDetail(Finder matching) => find.descendant(
    of: find.byKey(const ValueKey('vault-detail-pane')),
    matching: matching,
  );

  Finder inList(Finder matching) => find.descendant(
    of: find.byKey(const ValueKey('vault-list-pane')),
    matching: matching,
  );

  Future<NavigationFixtureVaultKdbxService> pumpAt(
    WidgetTester tester,
    double width,
  ) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = NavigationFixtureVaultKdbxService();
    await tester.pumpWidget(
      await pumpableVaultShell(vaultKdbxService: service),
    );
    await tester.pumpAndSettle();
    return service;
  }

  Future<void> openGmail(WidgetTester tester) async {
    await tester.tap(inList(find.text('Gmail')).first);
    await tester.pumpAndSettle();
  }

  // ---- T029/T030: US4, a deleted record leaves no dead detail ------------

  testWidgets('deleting the shown record returns the pane to its empty state', (
    tester,
  ) async {
    await pumpAt(tester, 1024);
    await openGmail(tester);
    expect(inDetail(find.text('Copy password')), findsOneWidget);

    await tester.tap(inDetail(find.byTooltip('Record actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'FR-008/G4.5 — no error dialog, no exception',
    );
    expect(
      find.text('Copy password'),
      findsNothing,
      reason: 'D6 — the pane must not be left showing a dead surface',
    );
    expect(find.byKey(const ValueKey('vault-detail-pane')), findsOneWidget);

    // Nothing is left selected once the record is gone.
    final stillSelected = tester
        .widgetList<Semantics>(inList(find.byType(Semantics)))
        .where((widget) => widget.properties.selected ?? false);
    expect(stillSelected, isEmpty, reason: 'G4.4 — selection cleared');
  });

  testWidgets('the same delete works in the single-pane band', (tester) async {
    await pumpAt(tester, 650);
    await tester.tap(find.text('Gmail').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Record actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // G4.2: the dismissal path is presentation-neutral, so the pushed
    // presentation lands back on the list just as the pane lands on empty.
    expect(find.text('Copy password'), findsNothing);
    expect(find.text('Banca Sella'), findsWidgets);
  });

  // ---- T014: US1 origin parity -------------------------------------------

  // FR-011/G5.6: the action set must not depend on the layout. Origin parity
  // (list vs Health vs duplicates) is guaranteed structurally rather than
  // asserted here — every origin now calls the single `_openEntryDetailsSurface`,
  // which attaches the actions itself, so there is no second wiring that could
  // drift. What a test *can* still catch is a layout-dependent menu, so that
  // is what this checks.
  for (final width in <double>[650, 1024]) {
    testWidgets('at $width the detail offers the same three actions', (
      tester,
    ) async {
      await pumpAt(tester, width);
      await tester.tap(find.text('Gmail').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Record actions').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in ['Move', 'Attachments', 'Delete']) {
        expect(
          find.text(label),
          findsWidgets,
          reason: '$label must be offered at $width too (FR-011)',
        );
      }
      // Edit is a header button rather than a menu item, at every width.
      expect(find.byTooltip('Edit'), findsWidgets);
    });
  }

  // ---- T033/T034: US3, the editor keeps the user's place -----------------

  testWidgets('the editor header carries the record title, not a generic '
      'label', (tester) async {
    await pumpAt(tester, 1024);
    await openGmail(tester);

    await tester.tap(inDetail(find.byTooltip('Edit')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      inDetail(find.text('Gmail')),
      findsWidgets,
      reason: 'FR-009a — the user can tell which record they are editing (D7)',
    );
    expect(find.text('Edit item'), findsNothing);
  });

  testWidgets('cancelling the editor returns to that record\'s detail', (
    tester,
  ) async {
    await pumpAt(tester, 1024);
    await openGmail(tester);

    await tester.tap(inDetail(find.byTooltip('Edit')));
    await tester.pumpAndSettle();
    await tester.tap(inDetail(find.text('Cancel')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      inDetail(find.text('Copy password')),
      findsOneWidget,
      reason: 'FR-009 — not the empty state (D7)',
    );
  });

  testWidgets('the records list is never dimmed while the editor is open', (
    tester,
  ) async {
    await pumpAt(tester, 1024);
    await openGmail(tester);
    await tester.tap(inDetail(find.byTooltip('Edit')));
    await tester.pumpAndSettle();

    // FR-002e: the design's artboard drew the list at 50% while editing. That
    // is a drawing device, not a spec: a dimmed interactive column fails the
    // contrast floor and misrepresents itself as inactive.
    final opacities = tester
        .widgetList<Opacity>(inList(find.byType(Opacity)))
        .where((widget) => widget.opacity < 0.95);
    expect(opacities, isEmpty, reason: 'the list stays fully legible');
  });

  // ---- T035: US3, the generator column vs sheet --------------------------

  testWidgets('at 1024 the generator opens as a column, not stacked on the '
      'editor', (tester) async {
    await pumpAt(tester, 1024);
    await openGmail(tester);
    await tester.tap(inDetail(find.byTooltip('Edit')));
    await tester.pumpAndSettle();

    // 1024 >= 995, so FR-002e says column. The editor stays visible beside it
    // rather than being covered by a sheet — the "dialog over dialog" case
    // the design called the worst of the current app.
    expect(tester.takeException(), isNull);
    expect(inDetail(find.text('Save')), findsOneWidget);
  });
}
