// spec-004 T6/T23/AC5: RevealController 12s auto-hide, driven by an
// external 1s `tick()` (shared with the TOTP ticker per the "TOTP +
// reveal" non-negotiable — see reveal_controller.dart doc comment).
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/widgets/entry/reveal_controller.dart';

void main() {
  test('reveal() sets isRevealed and starts at full fraction', () {
    final controller = RevealController();

    expect(controller.isRevealed, isFalse);
    controller.reveal();
    expect(controller.isRevealed, isTrue);
    expect(controller.remainingFraction, 1.0);
  });

  test('auto-hides at the 12th tick; the bar reaches 0 at the same moment', () {
    final controller = RevealController();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    controller.reveal();
    for (var i = 0; i < 11; i++) {
      controller.tick();
    }
    expect(controller.isRevealed, isTrue, reason: 'not yet expired at 11s');
    expect(controller.remainingFraction, closeTo(1 / 12, 1e-9));

    controller.tick(); // 12th tick
    expect(controller.isRevealed, isFalse, reason: 'expired at 12s');
    expect(controller.remainingFraction, 0);
    expect(notifyCount, greaterThan(0));
  });

  test('a manual hide before 12s cancels the countdown outright', () {
    final controller = RevealController();

    controller.reveal();
    controller.tick();
    controller.tick();
    controller.tick();
    controller.hide();
    expect(controller.isRevealed, isFalse);

    var notifiedAfterHide = false;
    controller.addListener(() => notifiedAfterHide = true);
    // If the countdown were merely ignored (not cancelled) it would still
    // "expire" and notify around the 12th tick.
    for (var i = 0; i < 10; i++) {
      controller.tick();
    }
    expect(
      notifiedAfterHide,
      isFalse,
      reason: 'manual hide must stop the countdown, not just ignore it',
    );
  });

  test('reveal() while already revealed restarts the 12s window', () {
    final controller = RevealController();

    controller.reveal();
    for (var i = 0; i < 10; i++) {
      controller.tick();
    }
    controller.reveal(); // restart
    for (var i = 0; i < 5; i++) {
      controller.tick();
    }
    expect(
      controller.isRevealed,
      isTrue,
      reason: 'still within the new 12s window (5 ticks < 12)',
    );

    for (var i = 0; i < 7; i++) {
      controller.tick();
    }
    expect(controller.isRevealed, isFalse);
  });

  test('tick() while not revealed is a harmless no-op', () {
    final controller = RevealController();
    controller.tick();
    controller.tick();
    expect(controller.isRevealed, isFalse);
  });

  test('timer keeps counting toward expiry independent of reduced motion — '
      'RevealController has no dependency on MediaQuery/AppMotion at all', () {
    // The controller itself never reads MediaQuery.disableAnimations;
    // only the *visual* bar widget (RevealedPasswordRow) may shorten its
    // own transition under reduced motion. This test documents that the
    // controller's tick()/12-tick expiry logic is unconditional.
    final controller = RevealController();
    controller.reveal();
    for (var i = 0; i < 12; i++) {
      controller.tick();
    }
    expect(controller.isRevealed, isFalse);
  });
}
