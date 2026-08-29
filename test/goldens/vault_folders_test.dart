// spec-019 T034/T043/T050 — the goldens of navigation model 1a.
//
// The vault_shell goldens render an EMPTY vault; these render the navigation
// fixture, so they show what the spec is actually about: a folder column with
// counts, a records list that holds only records, the phone's chip row, and
// the one folder-management surface in both of its containers.
//
// Omitted axes (VR-002), stated per case rather than left implicit: the state
// variants (folder selected, sort open, row menu open) are light-theme only —
// their subject is layout and content, and the palette is covered by the
// light/dark pair of the two root layouts.
//
// Same deterministic harness as vault_shell_test.dart: fixed size and DPR,
// explicit font loading, no runtime font fetching.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/password_manager/presentation/screens/vault/vault_navigation_fixture.dart';
import '../features/password_manager/presentation/screens/vault/vault_shell_test_utils.dart';

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

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      await pumpableVaultShell(
        themeMode: themeMode,
        vaultKdbxService: NavigationFixtureVaultKdbxService(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(name));
  }

  const wide = Size(1024, 768);
  const phone = Size(390, 844);

  // ── The desktop vault: three columns (US1) ──────────────────────────────
  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    final suffix = themeMode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('vault_1a_wide_1024x768_$suffix.png', (tester) async {
      await pump(tester, size: wide, themeMode: themeMode);
      await shoot(tester, 'vault_1a_wide_1024x768_$suffix.png');
    });
  }

  testWidgets('vault_1a_wide_folder_selected_1024x768_light.png', (
    tester,
  ) async {
    await pump(tester, size: wide);
    await tester.tap(find.text('Devs').first);
    await tester.pumpAndSettle();
    await shoot(tester, 'vault_1a_wide_folder_selected_1024x768_light.png');
  });

  testWidgets('vault_1a_sort_menu_1024x768_light.png', (tester) async {
    await pump(tester, size: wide);
    await tester.tap(find.byTooltip('Sort records'));
    await tester.pumpAndSettle();
    await shoot(tester, 'vault_1a_sort_menu_1024x768_light.png');
  });

  // ── The phone vault: a list, not a file browser (US2) ───────────────────
  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    final suffix = themeMode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('vault_1a_phone_390x844_$suffix.png', (tester) async {
      await pump(tester, size: phone, themeMode: themeMode);
      await shoot(tester, 'vault_1a_phone_390x844_$suffix.png');
    });
  }

  testWidgets('vault_1a_phone_folders_sheet_390x844_light.png', (tester) async {
    await pump(tester, size: phone);
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    await shoot(tester, 'vault_1a_phone_folders_sheet_390x844_light.png');
  });

  testWidgets('vault_1a_phone_sort_sheet_390x844_light.png', (tester) async {
    await pump(tester, size: phone);
    await tester.tap(find.byTooltip('Sort records'));
    await tester.pumpAndSettle();
    await shoot(tester, 'vault_1a_phone_sort_sheet_390x844_light.png');
  });

  // ── Manage folders: one surface, two containers (US3) ───────────────────
  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    final suffix = themeMode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('manage_folders_dialog_1024x768_$suffix.png', (tester) async {
      await pump(tester, size: wide, themeMode: themeMode);
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await shoot(tester, 'manage_folders_dialog_1024x768_$suffix.png');
    });
  }

  testWidgets('manage_folders_screen_390x844_light.png', (tester) async {
    await pump(tester, size: phone);
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await shoot(tester, 'manage_folders_screen_390x844_light.png');
  });

  testWidgets('manage_folders_row_menu_390x844_light.png', (tester) async {
    await pump(tester, size: phone);
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Folder actions').last);
    await tester.pumpAndSettle();
    await shoot(tester, 'manage_folders_row_menu_390x844_light.png');
  });

  // Constitution IV: the inventory is exact. A golden that appears without a
  // line here, or a line here without a file, is a gap in the record of what
  // this spec is allowed to have changed visually (SC-005).
  test('spec-019 adds exactly these goldens', () {
    const expected = <String>{
      'vault_1a_wide_1024x768_light.png',
      'vault_1a_wide_1024x768_dark.png',
      'vault_1a_wide_folder_selected_1024x768_light.png',
      'vault_1a_sort_menu_1024x768_light.png',
      'vault_1a_phone_390x844_light.png',
      'vault_1a_phone_390x844_dark.png',
      'vault_1a_phone_folders_sheet_390x844_light.png',
      'vault_1a_phone_sort_sheet_390x844_light.png',
      'manage_folders_dialog_1024x768_light.png',
      'manage_folders_dialog_1024x768_dark.png',
      'manage_folders_screen_390x844_light.png',
      'manage_folders_row_menu_390x844_light.png',
    };

    final onDisk = Directory('test/goldens')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where(
          (name) =>
              name.startsWith('vault_1a_') ||
              name.startsWith('manage_folders_'),
        )
        .toSet();

    expect(onDisk, expected);
  });
}
