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
  final ValueNotifier<PasskeyAssertionPrompt?> _pending =
      ValueNotifier<PasskeyAssertionPrompt?>(null);
  final ValueNotifier<PasskeyCreationPrompt?> _pendingCreation =
      ValueNotifier<PasskeyCreationPrompt?>(null);
  Completer<bool>? _completer;
  Completer<PasskeyCreationDecision?>? _creationCompleter;

  ValueListenable<PasskeyAssertionPrompt?> get pendingListenable => _pending;

  /// spec 023 US3 — the open "create a passkey here?" question, if any.
  ValueListenable<PasskeyCreationPrompt?> get pendingCreationListenable =>
      _pendingCreation;

  /// Ask the user about one signature. Resolves false if nothing answers.
  ///
  /// One at a time: a second request arriving while a prompt is open is
  /// declined rather than queued. Two sign-in confirmations stacked on each
  /// other is exactly the situation in which someone approves the wrong one.
  Future<bool> request(PasskeyAssertionPrompt prompt) {
    if (_completer != null) return Future.value(false);
    final completer = Completer<bool>();
    _completer = completer;
    _pending.value = prompt;
    return completer.future;
  }

  /// spec 023 US3 — ask the user where a new passkey should go.
  ///
  /// Same one-at-a-time rule as [request], and for the same reason: two
  /// stacked confirmations is how someone approves the wrong one.
  Future<PasskeyCreationDecision?> requestCreation(
    PasskeyCreationPrompt prompt,
  ) {
    if (_creationCompleter != null || _completer != null) {
      return Future.value(null);
    }
    final completer = Completer<PasskeyCreationDecision?>();
    _creationCompleter = completer;
    _pendingCreation.value = prompt;
    return completer.future;
  }

  /// Answer the open creation prompt. `null` is a decline.
  void resolveCreation(PasskeyCreationDecision? decision) {
    final completer = _creationCompleter;
    _creationCompleter = null;
    _pendingCreation.value = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(decision);
    }
  }

  /// Answer the open prompt, if there is still one.
  void resolve({required bool approved}) {
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
    resolve(approved: false);
    resolveCreation(null);
  }

  void dispose() {
    declineAll();
    _pending.dispose();
    _pendingCreation.dispose();
  }
}
