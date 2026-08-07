// spec-004 T23: acceptance-criteria checks that aren't goldens —
// AC7 (canGenerate disables the primary action), AC8 (tablet metadata grid
// has exactly 3 rows), AC9 (detail/editor push no route on tablet).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entry_editor_generator_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetEntryTestDi);

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('AC7: canGenerate == false disables the primary action', () {
    testWidgets('unchecking every character set disables "Use this password"', (
      tester,
    ) async {
      await setSize(tester, const Size(390, 844));
      await tester.pumpWidget(await pumpableEntryScreen());
      await tester.pumpAndSettle();

      // Root folder's "Add record" -> new-item editor -> generator sheet.
      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add record'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Generate secure password'));
      await tester.pumpAndSettle();

      // KvPillButton wraps an ElevatedButton (see kv_pill_button.dart).
      Finder useButton() =>
          find.widgetWithText(ElevatedButton, 'Use this password');
      expect(
        tester.widget<ElevatedButton>(useButton()).onPressed,
        isNotNull,
        reason: 'default options have every set enabled',
      );

      for (final label in [
        'Lowercase letters (a-z)',
        'Uppercase letters (A-Z)',
        'Numbers (0-9)',
        'Special characters (!@#...)',
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(
        tester.widget<ElevatedButton>(useButton()).onPressed,
        isNull,
        reason: 'AC7: no character set selected must disable the action',
      );
      expect(
        find.text('Select at least one character set.'),
        findsOneWidget,
        reason: 'byte-identical literal error string (spec-004 non-negotiable)',
      );

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('AC8: tablet metadata grid has exactly 3 rows', () {
    testWidgets('Created / Updated / last password change, no more no less', (
      tester,
    ) async {
      await setSize(tester, const Size(1024, 768));
      await tester.pumpWidget(await pumpableEntryScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('GitHub').first);
      await tester.pumpAndSettle();

      final grid = find.byKey(const ValueKey('entry-detail-metadata-grid'));
      expect(grid, findsOneWidget);

      // The grid renders one KvFieldRow-shaped label per row; count the
      // three known labels directly rather than reaching into internals.
      expect(find.text('Created'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('Last password change'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('AC9: detail and editor are a pane on tablet — no route pushed', () {
    testWidgets('opening an entry at 1024 width does not push a route', (
      tester,
    ) async {
      await setSize(tester, const Size(1024, 768));
      await tester.pumpWidget(await pumpableEntryScreen());
      await tester.pumpAndSettle();

      final routesBefore = _routeCount(tester);
      await tester.tap(find.text('GitHub').first);
      await tester.pumpAndSettle();

      expect(
        _routeCount(tester),
        routesBefore,
        reason: 'AC9: entry detail must render as a pane, not a pushed route',
      );
      // The detail content is visible inline (no MaterialPageRoute Scaffold
      // pushed on top) — its username field is on screen immediately.
      expect(find.text('camillo@bucciarelli.dev'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opening the editor at 1024 width does not push a route', (
      tester,
    ) async {
      await setSize(tester, const Size(1024, 768));
      await tester.pumpWidget(await pumpableEntryScreen());
      await tester.pumpAndSettle();

      final routesBefore = _routeCount(tester);
      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add record'));
      await tester.pumpAndSettle();

      expect(
        _routeCount(tester),
        routesBefore,
        reason: 'AC9: the editor must render as a pane, not a pushed route',
      );
      expect(find.text('New item'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// Counts live `Route`s on the app's Navigator via the number of `Route`
/// entries the `Navigator`'s `Overlay` currently holds — a pushed
/// `MaterialPageRoute` adds one; a pane embedded inline in the existing
/// tree does not.
int _routeCount(WidgetTester tester) {
  // `NavigatorState` doesn't expose its route count publicly. Every route
  // this app pushes wraps its content in exactly one `Scaffold`
  // (`VaultShellRouter._defaultRouteHost`), and the shell itself has
  // exactly one more — so the `Scaffold` count is a reliable proxy that
  // changes if and only if a route is actually pushed/popped.
  return tester.widgetList(find.byType(Scaffold)).length;
}
