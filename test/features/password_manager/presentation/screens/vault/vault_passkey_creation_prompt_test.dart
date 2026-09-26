// spec 023 T707 — the in-app confirmation for `navigator.credentials.create`,
// driven through the real approval service and the vault shell.
//
// The flow's contract is that nothing is written until the user says yes, and
// that the yes is specific: which record, and whether an existing passkey may
// be replaced. So each case asserts the decision the service hands back to the
// bridge, not just what appeared on screen — a dialog that looks right but
// resolves the wrong entry would pass a screenshot test.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_passkey_approval_service.dart';

import 'vault_shell_test_utils.dart';

PasskeyCreationPrompt _prompt({
  required List<PasskeyCreationCandidate> candidates,
}) => PasskeyCreationPrompt(
  relyingPartyId: 'webauthn.io',
  origin: 'https://webauthn.io',
  username: 'ada@example.com',
  candidateEntries: candidates,
);

PasskeyCreationCandidate _candidate({
  String entryId = 'e-1',
  String title = 'Webauthn',
  String username = 'ada@example.com',
  bool holdsPasskeyForThisSite = false,
}) => PasskeyCreationCandidate(
  entryId: entryId,
  title: title,
  username: username,
  holdsPasskeyForThisSite: holdsPasskeyForThisSite,
);

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

  /// Pumps the shell with a live approval service and returns it, so a test can
  /// pose the question the bridge would have posed.
  Future<DesktopPasskeyApprovalService> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final approvals = DesktopPasskeyApprovalService();
    addTearDown(approvals.dispose);
    await tester.pumpWidget(
      await pumpableVaultShell(passkeyApprovalService: approvals),
    );
    await tester.pumpAndSettle();
    return approvals;
  }

  testWidgets('one matching record → one confirmation naming it', (
    tester,
  ) async {
    final approvals = await pumpShell(tester);

    final decision = approvals.requestCreation(
      _prompt(candidates: [_candidate()]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create a passkey for webauthn.io?'), findsOneWidget);
    expect(
      find.textContaining('It will be saved on “Webauthn” (ada@example.com)'),
      findsOneWidget,
    );
    // FR-009's security model, stated where the credential is created too.
    expect(
      find.textContaining('not by hardware key isolation'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create passkey'));
    await tester.pumpAndSettle();

    final resolved = await decision;
    expect(resolved, isNotNull);
    expect(resolved!.entryId, 'e-1');
    expect(resolved.replaceExisting, isFalse);
  });

  testWidgets('declining the confirmation writes nothing', (tester) async {
    final approvals = await pumpShell(tester);

    final decision = approvals.requestCreation(
      _prompt(candidates: [_candidate()]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await decision, isNull);
  });

  testWidgets('no matching record → an explanation, not a silent refusal', (
    tester,
  ) async {
    final approvals = await pumpShell(tester);

    final decision = approvals.requestCreation(_prompt(candidates: const []));
    await tester.pumpAndSettle();

    expect(find.text('No record for webauthn.io'), findsOneWidget);
    expect(
      find.textContaining('this vault has no record for that site yet'),
      findsOneWidget,
    );
    // Nothing to confirm: the only action acknowledges it.
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(await decision, isNull);
  });

  testWidgets('several matching records → a chooser saying which hold one', (
    tester,
  ) async {
    final approvals = await pumpShell(tester);

    final decision = approvals.requestCreation(
      _prompt(
        candidates: [
          _candidate(entryId: 'e-1', title: 'Webauthn work'),
          _candidate(
            entryId: 'e-2',
            title: 'Webauthn personal',
            holdsPasskeyForThisSite: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create a passkey for webauthn.io?'), findsOneWidget);
    expect(find.text('Webauthn work'), findsOneWidget);
    expect(find.text('Webauthn personal'), findsOneWidget);
    // The row that leads to a replacement says so before it is chosen.
    expect(find.textContaining('already has a passkey for this site'), findsOneWidget);

    await tester.tap(find.text('Webauthn work'));
    await tester.pumpAndSettle();

    final resolved = await decision;
    expect(resolved!.entryId, 'e-1');
    expect(resolved.replaceExisting, isFalse);
  });

  testWidgets('a record that already holds one asks again before replacing', (
    tester,
  ) async {
    final approvals = await pumpShell(tester);

    final decision = approvals.requestCreation(
      _prompt(candidates: [_candidate(holdsPasskeyForThisSite: true)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create passkey'));
    await tester.pumpAndSettle();

    // FR-019: a second, explicit confirmation, naming the backup.
    expect(find.text('Replace the passkey on “Webauthn”?'), findsOneWidget);
    expect(find.textContaining('cannot be recovered'), findsOneWidget);
    expect(
      find.textContaining('A dated copy of the vault is saved'),
      findsOneWidget,
    );

    await tester.tap(find.text('Replace passkey'));
    await tester.pumpAndSettle();

    final resolved = await decision;
    expect(resolved!.entryId, 'e-1');
    expect(resolved.replaceExisting, isTrue);
  });

  testWidgets('declining the replacement declines the whole request', (
    tester,
  ) async {
    final approvals = await pumpShell(tester);

    final decision = approvals.requestCreation(
      _prompt(candidates: [_candidate(holdsPasskeyForThisSite: true)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create passkey'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await decision, isNull);
  });
}
