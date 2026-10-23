import 'dart:async';

import 'package:flutter/foundation.dart';

import 'desktop_browser_autofill_reveal_bridge_service.dart';

/// spec 023 FR-015 — the queue between the reveal bridge, which needs a yes
/// or a no, and the app window, which is where the user gives one.
///
/// The bridge runs on a loopback HTTP server with no UI of its own, so it
/// cannot ask anybody anything. It calls [request]; this holds the prompt in
/// [pendingListenable] until a widget in the vault shell answers it.
///
/// Strictly in-memory and app-owned. It holds no key and no assertion — only
/// the four strings the confirmation shows — and everything outstanding is
/// declined when the vault locks or the app tears the bridge down, because a
/// question nobody is there to answer is a no.
class DesktopPasskeyApprovalService {
  DesktopPasskeyApprovalService({Duration? promptBudget})
    : promptBudget = promptBudget ?? defaultPromptBudget;

  /// Shorter than the native host's own 90s budget for `/passkey-assert` and
  /// `/passkey-create`, on purpose.
  ///
  /// A prompt with no deadline outlives the request it answers: the host has
  /// already given up, the page has already fallen back to the browser's
  /// authenticator, and the dialog is still on screen. Approving it then would
  /// write a credential the site was never told about — the one outcome FR-020
  /// exists to prevent — or sign a challenge nobody is waiting for. The
  /// one-at-a-time rule made it worse: until the stale prompt was answered,
  /// every later sign-in was declined without asking.
  ///
  /// Expiring first means the answer always reaches a live request, and a
  /// timed-out prompt reads as a decline, which is what an unanswered question
  /// is.
  static const defaultPromptBudget = Duration(seconds: 80);

  final Duration promptBudget;

  final ValueNotifier<PasskeyAssertionPrompt?> _pending =
      ValueNotifier<PasskeyAssertionPrompt?>(null);
  final ValueNotifier<PasskeyCreationPrompt?> _pendingCreation =
      ValueNotifier<PasskeyCreationPrompt?>(null);
  Completer<bool>? _completer;
  Completer<PasskeyCreationDecision?>? _creationCompleter;
  final ValueNotifier<int> _written = ValueNotifier<int>(0);

  /// True from the moment a prompt's budget expires until the widget that was
  /// showing it reports back.
  ///
  /// The expiry frees the *request*, not the slot. A dialog the user is looking
  /// at outlives the request it belongs to — the app cannot reach into the
  /// widget tree from here — and the answer it eventually produces must not
  /// become the answer to a different site's request. So while a stale prompt
  /// is outstanding this service keeps refusing new ones, exactly as it did
  /// before the deadline existed, and swallows the late answer that clears it.
  ///
  /// Two guards, deliberately: the widget also closes the dialog when its
  /// prompt stops being the pending one, which is what makes this state
  /// short-lived. This one is what makes the outcome safe if it is not.
  bool _staleAssertion = false;
  bool _staleCreation = false;

  ValueListenable<PasskeyAssertionPrompt?> get pendingListenable => _pending;

  /// spec 023 US3 — the open "create a passkey here?" question, if any.
  ValueListenable<PasskeyCreationPrompt?> get pendingCreationListenable =>
      _pendingCreation;

  /// Bumped once per passkey written to the vault from a browser.
  ///
  /// The write happens outside the app window, so nothing in the UI would
  /// otherwise know the vault changed: the record would show no passkey and
  /// the bridge's own caches would still describe the vault as it was before.
  /// The vault shell listens here and reloads, which republishes both.
  ValueListenable<int> get writtenListenable => _written;

  void notePasskeyWritten() => _written.value++;

  /// Ask the user about one signature. Resolves false if nothing answers.
  ///
  /// One at a time: a second request arriving while a prompt is open is
  /// declined rather than queued. Two sign-in confirmations stacked on each
  /// other is exactly the situation in which someone approves the wrong one.
  Future<bool> request(PasskeyAssertionPrompt prompt) {
    if (_completer != null || _staleAssertion || _staleCreation) {
      return Future.value(false);
    }
    final completer = Completer<bool>();
    _completer = completer;
    _pending.value = prompt;
    return completer.future.timeout(
      promptBudget,
      onTimeout: () {
        // Only if this prompt is still the open one: a later request must not
        // be cancelled by an earlier request's deadline.
        if (identical(_completer, completer)) _expire();
        return false;
      },
    );
  }

  /// The deadline passed. Take the prompt off the screen, free the request, and
  /// hold the slot until whatever was showing it answers.
  void _expire() {
    _completer = null;
    _pending.value = null;
    _staleAssertion = true;
  }

  void _expireCreation() {
    _creationCompleter = null;
    _pendingCreation.value = null;
    _staleCreation = true;
  }

  /// spec 023 US3 — ask the user where a new passkey should go.
  ///
  /// Same one-at-a-time rule as [request], and for the same reason: two
  /// stacked confirmations is how someone approves the wrong one.
  Future<PasskeyCreationDecision?> requestCreation(
    PasskeyCreationPrompt prompt,
  ) {
    if (_creationCompleter != null ||
        _completer != null ||
        _staleCreation ||
        _staleAssertion) {
      return Future.value(null);
    }
    final completer = Completer<PasskeyCreationDecision?>();
    _creationCompleter = completer;
    _pendingCreation.value = prompt;
    return completer.future.timeout(
      promptBudget,
      onTimeout: () {
        if (identical(_creationCompleter, completer)) _expireCreation();
        return null;
      },
    );
  }

  /// Answer the open creation prompt. `null` is a decline.
  ///
  /// An answer that arrives after the prompt expired is discarded, not applied
  /// to whatever is open now: it was given about a site and a record the user
  /// was looking at then, and the request it belonged to has already been told
  /// no.
  void resolveCreation(PasskeyCreationDecision? decision) {
    if (_staleCreation) {
      _staleCreation = false;
      return;
    }
    final completer = _creationCompleter;
    _creationCompleter = null;
    _pendingCreation.value = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(decision);
    }
  }

  /// Answer the open prompt, if there is still one. Same rule as
  /// [resolveCreation] for an answer that arrives too late.
  void resolve({required bool approved}) {
    if (_staleAssertion) {
      _staleAssertion = false;
      return;
    }
    final completer = _completer;
    _completer = null;
    _pending.value = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(approved);
    }
  }

  /// Decline whatever is outstanding — a lock, a database switch, a bridge
  /// teardown. Safe to call when nothing is pending.
  void declineAll() {
    // Twice over for the stale case: the first call clears the stale flag, the
    // second declines whatever is genuinely open. A teardown must leave nothing
    // outstanding in either slot.
    resolve(approved: false);
    resolve(approved: false);
    resolveCreation(null);
    resolveCreation(null);
  }

  void dispose() {
    declineAll();
    _pending.dispose();
    _pendingCreation.dispose();
    _written.dispose();
  }
}
