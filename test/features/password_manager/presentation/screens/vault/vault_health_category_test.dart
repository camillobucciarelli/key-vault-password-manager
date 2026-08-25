// spec-005 T4/FR-4: all five health categories open a filtered destination
// (previously only "Duplicates" was tappable). Covers the four non-duplicate
// categories: tapping a category row opens a flat list containing exactly
// the entries in that category's `entryIds`, and tapping a row in that list
// opens the entry detail surface.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_group.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';

import 'vault_shell_test_utils.dart';

class _HealthFixtureVaultKdbxService implements VaultKdbxService {
  static const rootId = 'root';

  static const weak = VaultEntry(
    id: 'weak-1',
    groupId: rootId,
    title: 'Old router admin',
    username: 'admin',
    password: 'admin',
    url: '192.168.1.1',
    notes: '',
  );
  static const reused1 = VaultEntry(
    id: 'reused-1',
    groupId: rootId,
    title: 'GitHub',
    username: 'dev',
    password: 'Tr0ub4dor&Zx9!Qp',
    url: 'github.com',
    notes: '',
  );
  static const reused2 = VaultEntry(
    id: 'reused-2',
    groupId: rootId,
    title: 'GitLab',
    username: 'dev',
    password: 'Tr0ub4dor&Zx9!Qp',
    url: 'gitlab.com',
    notes: '',
  );
  static final old = VaultEntry(
    id: 'old-1',
    groupId: rootId,
    title: 'Spotify',
    username: 'listener',
    password: 'Zn5!qLp8Rk3@Tx6a',
    url: 'spotify.com',
    notes: '',
    lastPasswordChangedAt: DateTime(2020, 1, 1),
  );
  static const unmatchable = VaultEntry(
    id: 'unmatchable-1',
    groupId: rootId,
    title: 'Loose note',
    username: '',
    password: 'Hl1!Nb6\$Wq4@Zt9c',
    url: '',
    notes: '',
  );
  // In none of the four categories under test — proves filtering excludes it.
  static const control = VaultEntry(
    id: 'control-1',
    groupId: rootId,
    title: 'Amazon',
    username: 'shopper',
    password: 'Qx7#mPz9Lk2\$Vw8!',
    url: 'amazon.com',
    notes: '',
  );

  List<VaultEntry> get entries => [
    weak,
    reused1,
    reused2,
    old,
    unmatchable,
    control,
  ];

  @override
  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async {
    return VaultSnapshot(
      rootGroupId: rootId,
      currentGroupId: currentGroupId ?? rootId,
      groups: const [VaultGroup(id: rootId, name: 'root', parentId: null)],
      entries: entries,
      allEntries: entries,
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

  Future<void> pumpToHealth(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await pumpableVaultShell(
        vaultKdbxService: _HealthFixtureVaultKdbxService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
  }

  final cases = <({String rowLabel, String title, String otherTitle})>[
    (
      rowLabel: 'Weak passwords',
      title: 'Old router admin',
      otherTitle: 'GitHub',
    ),
    (rowLabel: 'Reused passwords', title: 'GitHub', otherTitle: 'Spotify'),
    (
      rowLabel: 'Old passwords',
      title: 'Spotify',
      otherTitle: 'Loose note',
    ),
    (
      rowLabel: 'Missing URL or username',
      title: 'Loose note',
      otherTitle: 'Old router admin',
    ),
  ];

  for (final testCase in cases) {
    testWidgets(
      '${testCase.rowLabel}: opens a list with exactly its category entries',
      (tester) async {
        await pumpToHealth(tester);

        await tester.tap(find.text(testCase.rowLabel));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(testCase.title), findsOneWidget);
        expect(find.text(testCase.otherTitle), findsNothing);
        expect(find.text('Amazon'), findsNothing);
      },
    );
  }

  testWidgets(
    'tapping a row in the filtered list opens the entry detail surface',
    (tester) async {
      await pumpToHealth(tester);

      await tester.tap(find.text('Weak passwords'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Old router admin'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Username'), findsOneWidget);
    },
  );

  testWidgets('an empty category renders a one-line message, still tappable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Only the "control" entry — none of the four categories under test
    // have any member, so this is a reliable zero-count fixture.
    await tester.pumpWidget(
      await pumpableVaultShell(
        vaultKdbxService: _ControlOnlyVaultKdbxService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Weak passwords'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No records in this category'), findsOneWidget);
  });
}

class _ControlOnlyVaultKdbxService extends _HealthFixtureVaultKdbxService {
  @override
  List<VaultEntry> get entries => [_HealthFixtureVaultKdbxService.control];
}
