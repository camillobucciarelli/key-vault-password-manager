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

  test('an answer inside the budget is the answer', () async {
    final service = DesktopPasskeyApprovalService(
      promptBudget: const Duration(seconds: 30),
    );
    addTearDown(service.dispose);

    final pending = service.request(assertionPrompt);
    service.resolve(approved: true);

    expect(await pending, isTrue);
  });

  test("an answered prompt's deadline never expires a later one", () async {
    final service = DesktopPasskeyApprovalService(
      promptBudget: const Duration(milliseconds: 40),
    );
    addTearDown(service.dispose);

    // First prompt is answered well inside its budget, so its timer is still
    // pending when the second prompt opens.
    final first = service.request(assertionPrompt);
    service.resolve(approved: true);
    expect(await first, isTrue);

    final second = service.request(assertionPrompt);
    // Past the first prompt's deadline but not the second's: if the first
    // timer still owned the slot it would take this prompt off the screen and
    // decline it under the user.
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(service.pendingListenable.value, isNotNull);
    service.resolve(approved: true);

    expect(await second, isTrue);
  });

  // The regression the deadline itself introduced. Expiring frees the request,
  // but the dialog the user is looking at outlives it — nothing in this service
  // can reach into the widget tree — so the answer it eventually produces must
  // not become the answer to a different site's request.
  group('a prompt that expired while its dialog was still up', () {
    test('does not let a later request be accepted into its slot', () async {
      final service = build();
      addTearDown(service.dispose);

      // First prompt expires. Its dialog is, as far as this service knows,
      // still on screen: nothing has answered.
      expect(await service.request(assertionPrompt), isFalse);

      // A second sign-in for another site must not be accepted, or the stale
      // dialog's "Sign in" would answer it.
      const other = PasskeyAssertionPrompt(
        relyingPartyId: 'evil.example',
        origin: 'https://evil.example',
        entryTitle: 'Other',
        username: 'bob',
      );
      expect(await service.request(other), isFalse);
      expect(
        service.pendingListenable.value,
        isNull,
        reason: 'and the second prompt was never put on screen either',
      );
    });

    test('its late approval signs nothing', () async {
      final service = build();
      addTearDown(service.dispose);
      await service.request(assertionPrompt);

      // The user presses "Sign in" on the stale dialog. It resolves nothing,
      // and it releases the slot.
      service.resolve(approved: true);

      final next = service.request(assertionPrompt);
      expect(service.pendingListenable.value, isNotNull);
      service.resolve(approved: true);
      expect(await next, isTrue);
    });

    test('blocks a creation request too, and vice versa', () async {
      final service = build();
      addTearDown(service.dispose);

      await service.request(assertionPrompt);
      expect(await service.requestCreation(creationPrompt), isNull);

      service.resolve(approved: false);

      await service.requestCreation(creationPrompt);
      expect(await service.request(assertionPrompt), isFalse);
    });

    test("a stale creation's late decision creates nothing", () async {
      final service = build();
      addTearDown(service.dispose);
      await service.requestCreation(creationPrompt);

      service.resolveCreation(
        const PasskeyCreationDecision(entryId: 'e1', replaceExisting: true),
      );

      final next = service.requestCreation(creationPrompt);
      expect(service.pendingCreationListenable.value, isNotNull);
      service.resolveCreation(null);
      expect(await next, isNull);
    });

    test('a teardown leaves neither slot outstanding', () async {
      final service = build();
      addTearDown(service.dispose);
      await service.request(assertionPrompt);
      await service.requestCreation(creationPrompt);

      service.declineAll();

      // Both slots are free again: a lock must not leave the app unable to
      // ask anything for the rest of the session.
      final next = service.request(assertionPrompt);
      expect(service.pendingListenable.value, isNotNull);
      service.resolve(approved: true);
      expect(await next, isTrue);
    });
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
