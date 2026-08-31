// spec-018 T009: `VaultLayoutClass` is the single width authority (FR-002a),
// so its boundaries are asserted directly rather than inferred from a widget.
//
// The derived thresholds must equal the arithmetic the spec states. If a
// column width is ever retuned, these tests fail with the new number — which
// is the point: a threshold may only move because a column moved.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/responsive/breakpoints.dart';

void main() {
  group('derived thresholds match the spec arithmetic', () {
    test('detailPane is 704 = 72 + 330 + 300 + 2', () {
      expect(VaultLayoutWidths.detailPane, 704);
    });

    // 2026-08-31: raised from the 941 column-minima sum by user direction.
    test('folderPane is 1024', () {
      expect(VaultLayoutWidths.folderPane, 1024);
    });

    test('generatorColumn is 995 = 72 + 330 + 300 + 290 + 3', () {
      expect(VaultLayoutWidths.generatorColumn, 995);
    });

    test('foldersAndGenerator is 1232 = 72 + 236 + 330 + 290 + 300 + 4', () {
      expect(VaultLayoutWidths.foldersAndGenerator, 1232);
    });

    test('folders and the generator cannot coexist at the 1024 baseline', () {
      expect(VaultLayoutWidths.foldersAndGenerator, greaterThan(1024));
    });

    test('the corrected columns are single values, not the drifted ones', () {
      expect(VaultColumns.rail, 72, reason: 'not 76 — corrected drift');
      expect(VaultColumns.list, 330, reason: 'not 352 — corrected drift');
      expect(VaultColumns.folders, 236);
      expect(VaultColumns.detailMin, 300);
      expect(VaultColumns.generator, 290);
    });
  });

  group('VaultLayoutClass.fromWidth boundary table (contract C1)', () {
    const cases = <(double, VaultLayoutClass)>[
      (0, VaultLayoutClass.narrowTabBar),
      (390, VaultLayoutClass.narrowTabBar),
      (599, VaultLayoutClass.narrowTabBar),
      (600, VaultLayoutClass.narrowRail),
      (703, VaultLayoutClass.narrowRail),
      (704, VaultLayoutClass.wide),
      (940, VaultLayoutClass.wide),
      (941, VaultLayoutClass.wide),
      (1023, VaultLayoutClass.wide),
      (1024, VaultLayoutClass.wideWithFolders),
      (4000, VaultLayoutClass.wideWithFolders),
    ];

    for (final (width, expected) in cases) {
      test('$width -> ${expected.name}', () {
        expect(VaultLayoutClass.fromWidth(width), expected);
      });
    }

    // G1.1 total
    test('every width maps to exactly one class', () {
      for (var width = 0.0; width <= 1600; width += 0.5) {
        expect(() => VaultLayoutClass.fromWidth(width), returnsNormally);
      }
    });

    // G1.2 monotonic
    test('the classification never goes backwards as width grows', () {
      var previous = VaultLayoutClass.fromWidth(0).index;
      for (var width = 0.0; width <= 1600; width += 0.5) {
        final current = VaultLayoutClass.fromWidth(width).index;
        expect(
          current,
          greaterThanOrEqualTo(previous),
          reason: 'classification regressed at ${width}px',
        );
        previous = current;
      }
    });

    // G1.3 boundaries are the FIRST width of their class
    test('600, 704 and 1024 are the first width of their class', () {
      expect(VaultLayoutClass.fromWidth(599.5), VaultLayoutClass.narrowTabBar);
      expect(VaultLayoutClass.fromWidth(600), VaultLayoutClass.narrowRail);
      expect(VaultLayoutClass.fromWidth(703.5), VaultLayoutClass.narrowRail);
      expect(VaultLayoutClass.fromWidth(704), VaultLayoutClass.wide);
      expect(VaultLayoutClass.fromWidth(1023.5), VaultLayoutClass.wide);
      expect(
        VaultLayoutClass.fromWidth(1024),
        VaultLayoutClass.wideWithFolders,
      );
    });
  });

  group('predicates', () {
    test('only the wide classes have a detail pane', () {
      expect(VaultLayoutClass.narrowTabBar.hasDetailPane, isFalse);
      expect(VaultLayoutClass.narrowRail.hasDetailPane, isFalse);
      expect(VaultLayoutClass.wide.hasDetailPane, isTrue);
      expect(VaultLayoutClass.wideWithFolders.hasDetailPane, isTrue);
    });

    test('only wideWithFolders has the folder pane', () {
      expect(VaultLayoutClass.wide.hasFolderPane, isFalse);
      expect(VaultLayoutClass.wideWithFolders.hasFolderPane, isTrue);
    });

    test('only narrowTabBar has the tab bar', () {
      expect(VaultLayoutClass.narrowTabBar.hasTabBar, isTrue);
      expect(VaultLayoutClass.narrowRail.hasTabBar, isFalse);
    });

    // The rail replaces the tab bar at 600, but that is chrome only: both
    // narrow classes push the detail. This is what preserves US5.
    test('both narrow classes agree that the detail pushes', () {
      expect(VaultLayoutClass.narrowTabBar.hasDetailPane, isFalse);
      expect(VaultLayoutClass.narrowRail.hasDetailPane, isFalse);
    });
  });
}
