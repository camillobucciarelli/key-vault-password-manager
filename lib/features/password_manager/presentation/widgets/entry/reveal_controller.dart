import 'package:flutter/foundation.dart';

/// Drives the 12 s reveal auto-hide (spec-004 FR-2 "Proposal — 12 s reveal
/// auto-hide"). A plain [ChangeNotifier], not a BLoC — this is UI-local
/// countdown state, not a domain workflow.
///
/// Deliberately owns **no timer of its own**: spec-004's "TOTP + reveal"
/// non-negotiable requires a single shared 1 s ticker in the entry-detail
/// screen driving both the TOTP countdown and this reveal countdown, not
/// two independent timers. The owning screen calls [tick] once per second
/// from the same `Timer.periodic` it already uses to refresh the TOTP code;
/// this controller just counts elapsed ticks against the 12 s budget.
///
/// That external ticker is a plain app timer, not an `AnimationController`,
/// so the 12 s expiry keeps counting down even when
/// `MediaQuery.disableAnimations` is on — it is a security control, not
/// decoration. Callers rendering the countdown *bar* may still shorten the
/// bar's own visual transition under reduced motion (see
/// `RevealedPasswordRow`); that never affects when [tick] actually expires
/// the reveal.
class RevealController extends ChangeNotifier {
  static const revealSeconds = 12;

  bool _isRevealed = false;
  int _elapsedSeconds = 0;

  bool get isRevealed => _isRevealed;

  /// 1.0 right after [reveal], stepping down to 0.0 at expiry — one step
  /// per [tick] (i.e. one step per second).
  double get remainingFraction {
    if (!_isRevealed) {
      return 0;
    }
    final remaining = revealSeconds - _elapsedSeconds;
    if (remaining <= 0) {
      return 0;
    }
    return (remaining / revealSeconds).clamp(0.0, 1.0);
  }

  void reveal() {
    _isRevealed = true;
    _elapsedSeconds = 0;
    notifyListeners();
  }

  /// Manual hide before expiry. The next [tick] from the shared ticker is
  /// then simply a no-op for this controller — there is no separate timer
  /// to cancel.
  void hide() {
    if (!_isRevealed) {
      return;
    }
    _isRevealed = false;
    notifyListeners();
  }

  /// Called once per second by the entry-detail screen's shared ticker.
  /// No-op when not currently revealed.
  void tick() {
    if (!_isRevealed) {
      return;
    }
    _elapsedSeconds++;
    if (_elapsedSeconds >= revealSeconds) {
      hide();
      return;
    }
    notifyListeners();
  }
}
