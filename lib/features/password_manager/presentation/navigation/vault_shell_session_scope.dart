import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The vault shell's session, as seen from a surface the shell's own subtree
/// does not contain.
///
/// A separate object rather than the shell's `State`: a route on the shared
/// Navigator is a *sibling* of the shell's content and can outlive it, so what
/// it retains is this — a flag and two hooks — and not the whole shell with
/// the vault it holds. The shell calls [dispose], which drops the hooks.
final class VaultShellSession {
  VaultShellSession({
    required VoidCallback onUserActivity,
    required Future<void> Function(String databasePath) lockAndReauthenticate,
  }) : _onUserActivity = onUserActivity,
       _lockAndReauthenticate = lockAndReauthenticate;

  final ValueNotifier<bool> _locked = ValueNotifier<bool>(false);
  VoidCallback? _onUserActivity;
  Future<void> Function(String databasePath)? _lockAndReauthenticate;

  /// True while the shell's lock overlay is up. The overlay is a widget in
  /// the shell's body, so it cannot cover a route: a surface above it watches
  /// this and dismisses itself.
  ValueListenable<bool> get locked => _locked;
  bool get isLocked => _locked.value;
  set isLocked(bool value) => _locked.value = value;

  /// Feeds the shell's inactivity timer from outside the shell's pointer
  /// `Listener`, which a route is not below.
  void reportActivity() => _onUserActivity?.call();

  /// Locks the vault and hands the user to the unlock screen, replacing the
  /// *shell's* route whatever is stacked above it — the caller's own route is
  /// not necessarily the one to replace.
  ///
  /// After [dispose] there is no shell to lock: a no-op, by design.
  Future<void> lockAndReauthenticate(String databasePath) async {
    final lock = _lockAndReauthenticate;
    if (lock == null) return;
    await lock(databasePath);
  }

  void dispose() {
    _onUserActivity = null;
    _lockAndReauthenticate = null;
    _locked.dispose();
  }
}

/// Publishes [VaultShellSession] down the tree.
///
/// Mounted by the vault shell and re-provided by every host that puts a
/// surface outside the shell's subtree — the same re-hosting
/// `VaultShellRouterScope` needs, and for the same reason.
final class VaultShellSessionScope extends InheritedWidget {
  const VaultShellSessionScope({
    super.key,
    required this.session,
    required super.child,
  });

  final VaultShellSession session;

  static VaultShellSession of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<VaultShellSessionScope>();
    assert(scope != null, 'No VaultShellSessionScope found in context.');
    return scope!.session;
  }

  /// For a host re-providing the scope: reads without taking a dependency,
  /// and answers `null` where there is no shell at all (widget tests that
  /// pump a router on its own).
  static VaultShellSession? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<VaultShellSessionScope>()?.session;

  @override
  bool updateShouldNotify(VaultShellSessionScope oldWidget) =>
      session != oldWidget.session;
}
