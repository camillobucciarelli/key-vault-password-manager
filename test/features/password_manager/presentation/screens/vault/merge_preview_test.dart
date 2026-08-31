// spec-005 T20/AC5: merge preview sheet shows exactly the five
// `MergePreview` flags — no more, no fewer.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_group.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';

import 'vault_shell_test_utils.dart';

class _DuplicatesVaultKdbxService implements VaultKdbxService {
  @override
  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async {
    const rootId = 'root';
    final primary = VaultEntry(
      id: 'primary',
      groupId: rootId,
      title: 'Netflix',
      username: 'user@example.com',
      password: 'primary-pw',
      url: 'netflix.com',
      notes: '', // empty -> willCopyNotes should be true
      updatedAt: DateTime(2026, 1, 2),
    );
    final secondary = VaultEntry(
      id: 'secondary',
      groupId: rootId,
      title: 'Netflix family',
      username: 'user@example.com',
      password: 'secondary-pw',
      url: 'netflix.com',
      notes: 'Family plan notes',
      customFields: const [VaultCustomField(key: 'Plan', value: 'Family')],
      updatedAt: DateTime(2024, 1, 4),
    );

    return VaultSnapshot(
      rootGroupId: rootId,
      currentGroupId: currentGroupId ?? rootId,
      groups: const [VaultGroup(id: rootId, name: 'root', parentId: null)],
      entries: [primary, secondary],
      allEntries: [primary, secondary],
    );
  }

  @override
  Future<List<VaultEntry>> loadRecycleBinEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
          ..addFont(rootBundle.load('assets/fonts/Figtree-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Figtree-Bold.ttf')))
        .load();
  });

  tearDown(resetVaultShellTestDi);

  testWidgets('merge preview sheet renders exactly 5 MergePreview flag rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await pumpableVaultShell(vaultKdbxService: _DuplicatesVaultKdbxService()),
    );
    await tester.pumpAndSettle();

    // Vault -> Health -> Duplicates category -> group card -> Merge.
    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge and move duplicate'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final flagRowKeys = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('merge-flag-row-');
    });
    expect(
      flagRowKeys,
      findsNWidgets(5),
      reason: 'exactly the five MergePreview flags — no more, no fewer',
    );

    // Sanity: the five concepts are exactly
    // notes/attachments/customFields/urls/otp.
    expect(find.byKey(const ValueKey('merge-flag-row-notes')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('merge-flag-row-attachments')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('merge-flag-row-customFields')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('merge-flag-row-urls')), findsOneWidget);
    expect(find.byKey(const ValueKey('merge-flag-row-otp')), findsOneWidget);
  });
}
