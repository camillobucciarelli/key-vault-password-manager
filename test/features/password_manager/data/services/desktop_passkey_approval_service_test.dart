// spec 023 FR-015 — the queue between the loopback bridge and the app window.
//
// The property under test is the deadline. The bridge's caller (the native
// host) gives up after 90 seconds, at which point the page has already
// fallen back to the browser's own authenticator. A prompt that outlives that
// moment can still be approved, and an approval then either signs a challenge
// nobody is waiting for or — worse, and what FR-020 forbids — writes a
// credential the relying party was never told about. The one-at-a-time rule
// compounded it: an unanswered prompt declined every later request without
// asking anyone.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_passkey_approval_service.dart';

void main() {
  const assertionPrompt = PasskeyAssertionPrompt(
    relyingPartyId: 'webauthn.io',
    origin: 'https://webauthn.io',
    entryTitle: 'Webauthn',
    username: 'ada',
  );
  const creationPrompt = PasskeyCreationPrompt(
    relyingPartyId: 'webauthn.io',
    origin: 'https://webauthn.io',
    username: 'ada',
    candidateEntries: [],
  );

  DesktopPasskeyApprovalService build() => DesktopPasskeyApprovalService(
    // Short enough to await for real: the number is not the property, the
    // expiry is.
    promptBudget: const Duration(milliseconds: 20),
  );

  test('the default budget expires before the host gives up', () {
    // The host's own budget for /passkey-assert and /passkey-create. A prompt
    // that outlived it could be approved after the page moved on.
    expect(
      DesktopPasskeyApprovalService.defaultPromptBudget,
      lessThan(const Duration(seconds: 90)),
    );
  });

  test('an unanswered sign-in prompt expires as a decline', () async {
    final service = build();
    addTearDown(service.dispose);

    expect(await service.request(assertionPrompt), isFalse);
    // And it is off the screen: nothing is left for the user to approve into
    // a request that has already ended.
    expect(service.pendingListenable.value, isNull);
  });

  test('an unanswered creation prompt expires as a decline', () async {
    final service = build();
    addTearDown(service.dispose);

    expect(await service.requestCreation(creationPrompt), isNull);
    expect(service.pendingCreationListenable.value, isNull);
  });

  test('an expired prompt does not wedge the next request', () async {
    final service = build();
    addTearDown(service.dispose);

    await service.request(assertionPrompt);
    // The one-at-a-time rule must now let a fresh sign-in through, and this
    // one gets answered.
    final second = service.request(assertionPrompt);
    expect(service.pendingListenable.value, isNotNull);
    service.resolve(approved: true);
    expect(await second, isTrue);
  });

  test('an answer inside the budget is the answer', () async {
    final service = DesktopPasskeyApprovalService(
      promptBudget: const Duration(seconds: 30),
    );
    addTearDown(service.dispose);

    final pending = service.request(assertionPrompt);
    service.resolve(approved: true);

    expect(await pending, isTrue);
  });

  test("an earlier prompt's deadline never cancels a later one", () async {
    final service = build();
    addTearDown(service.dispose);

    await service.request(assertionPrompt);
    final second = service.request(assertionPrompt);
    service.resolve(approved: true);
    // Well past the first prompt's budget: if its onTimeout still owned the
    // slot it would clear this prompt out from under the user.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(await second, isTrue);
  });

  test('a written passkey is announced exactly once per write', () {
    final service = build();
    addTearDown(service.dispose);
    var notifications = 0;
    service.writtenListenable.addListener(() => notifications++);

    service.notePasskeyWritten();
    service.notePasskeyWritten();

    expect(notifications, 2);
  });
}
