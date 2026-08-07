import 'dart:async';

import 'package:flutter/services.dart';

/// Copies a value to the clipboard and clears it again 30 s later — but
/// only if the clipboard still holds exactly what this guard wrote. Never
/// clears blindly: if the user (or another app) overwrote the clipboard in
/// the meantime, [ClipboardData] on fire is compared before touching
/// anything. Spec-004 FR-3 "Proposal — 30 s clipboard clear".
///
/// One guard instance is meant to live for the lifetime of a screen (e.g. an
/// entry detail screen); each [copy] call cancels the previous pending
/// timer and schedules a new one. Call [dispose] when the owning widget is
/// disposed so a backgrounded app never leaks a timer.
class ClipboardGuard {
  Timer? _timer;
  String? _lastWritten;

  static const clearDelay = Duration(seconds: 30);

  /// Writes [value] to the clipboard and schedules the 30 s conditional
  /// clear. Cancels any previously scheduled clear from an earlier [copy].
  Future<void> copy(String value) async {
    _timer?.cancel();
    await Clipboard.setData(ClipboardData(text: value));
    _lastWritten = value;
    _timer = Timer(clearDelay, _clearIfUnchanged);
  }

  Future<void> _clearIfUnchanged() async {
    final written = _lastWritten;
    if (written == null) {
      return;
    }
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == written) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  /// Cancels the pending clear without touching the clipboard. Call from
  /// the owning widget's `dispose()`.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
