// spec 023 US1b (T102) — a secret custom field in the entry detail gets the
// password's own treatment: masked by default, revealed through the same
// biometric gate and countdown, copied through the clipboard guard. The raw
// value never enters the widget tree while masked.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/widgets/kv_field_row.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_group.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';

import 'entry_editor_generator_test_utils.dart';

const _seed = 'abandon ability able about above absent';
const _masked = '••••••••••••';

VaultSnapshot _snapshot({List<VaultCustomField> extraFields = const []}) {
  final wallet = VaultEntry(
    id: 'e-wallet',
    groupId: kRootGroupId,
    title: 'Wallet',
    username: 'me',
    password: 'Wallet-Pass-4d!ab',
    url: '',
    notes: '',
    customFields: [
      const VaultCustomField(key: 'Seed', value: _seed, isProtected: true),
      const VaultCustomField(key: 'Network', value: 'mainnet'),
      ...extraFields,
    ],
  );
  return VaultSnapshot(
    rootGroupId: kRootGroupId,
    currentGroupId: kRootGroupId,
    groups: const [VaultGroup(id: kRootGroupId, name: 'Vault', parentId: null)],
    entries: [wallet],
    allEntries: [wallet],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetEntryTestDi);

  Future<EntryTestHarness> pumpDetail(
    WidgetTester tester, {
    bool biometricGate = false,
    bool biometricResult = true,
    List<VaultCustomField> extraFields = const [],
  }) async {
    final harness =
        EntryTestHarness(snapshot: _snapshot(extraFields: extraFields))
          ..biometricAvailable = biometricGate
          ..biometricEnabledForDatabase = biometricGate
          ..biometricAuthenticateResult = biometricResult;
    await tester.pumpWidget(await pumpableEntryScreen(harness: harness));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallet').first);
    await tester.pumpAndSettle();
    return harness;
  }

  Finder seedRow() =>
      find.ancestor(of: find.text('Seed'), matching: find.byType(KvFieldRow));

  testWidgets('masked by default; the plain field stays readable', (
    tester,
  ) async {
    await pumpDetail(tester);

    // Password and Seed: two masked rows, one Show value (the password's
    // eye says Show password).
    expect(find.text(_masked), findsNWidgets(2));
    expect(find.text(_seed), findsNothing);
    expect(find.byTooltip('Show value'), findsOneWidget);
    expect(find.text('mainnet'), findsOneWidget);
  });

  testWidgets('reveal shows the value on the countdown row, one at a time', (
    tester,
  ) async {
    await pumpDetail(tester);

    await tester.tap(find.byTooltip('Show value'));
    await tester.pumpAndSettle();
    expect(find.text(_seed), findsOneWidget);
    expect(find.byTooltip('Hide value'), findsOneWidget);
    // The password did not come along.
    expect(find.text(_masked), findsOneWidget);

    await tester.tap(find.byTooltip('Hide value'));
    await tester.pumpAndSettle();
    expect(find.text(_seed), findsNothing);
  });

  testWidgets('two secret fields sharing a name reveal one at a time', (
    tester,
  ) async {
    // A vault written elsewhere may repeat a key; the editor never does.
    // One gate uncovers one row, so the reveal is tracked by position.
    await pumpDetail(
      tester,
      extraFields: const [
        VaultCustomField(key: 'Seed', value: 'other-seed', isProtected: true),
      ],
    );
    expect(find.byTooltip('Show value'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Show value').last);
    await tester.pumpAndSettle();
    expect(find.text('other-seed'), findsOneWidget);
    expect(find.text(_seed), findsNothing);
    expect(find.byTooltip('Hide value'), findsOneWidget);
  });

  testWidgets('a biometric-protected database gates the reveal', (
    tester,
  ) async {
    await pumpDetail(tester, biometricGate: true, biometricResult: false);

    await tester.tap(find.byTooltip('Show value'));
    await tester.pumpAndSettle();

    // The OS prompt failed, so the fallback sheet is up and nothing leaked.
    expect(find.text('Confirm it’s you'), findsOneWidget);
    expect(find.text(_seed), findsNothing);
  });

  testWidgets('a passing biometric check reveals', (tester) async {
    await pumpDetail(tester, biometricGate: true);

    await tester.tap(find.byTooltip('Show value'));
    await tester.pumpAndSettle();
    expect(find.text(_seed), findsOneWidget);
  });

  testWidgets('copy goes through the clipboard guard', (tester) async {
    String? clipboard;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpDetail(tester);
    await tester.tap(
      find.descendant(of: seedRow(), matching: find.byTooltip('Copy')),
    );
    await tester.pump();

    expect(clipboard, _seed);
    expect(find.text('Copied Seed.'), findsOneWidget);
    // Copying is not revealing.
    expect(find.text(_seed), findsNothing);
    // Let the guard's 30 s clear timer run out inside the test.
    await tester.pump(const Duration(seconds: 31));
  });
}
