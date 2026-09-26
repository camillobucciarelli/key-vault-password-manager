part of '../vault_screen.dart';

/// spec 023 T502 / FR-015 — the in-app confirmation for a passkey sign-in a
/// desktop browser asked for.
///
/// Invisible until the bridge has a question. It mounts inside the vault
/// shell, so it exists exactly while a vault is open and unlocked: the
/// window where a signature is possible at all.
///
/// The prompt names the site the page is on, the record and the account, and
/// nothing else. A signature is not a secret the user reads, so there is
/// nothing here to reveal or copy.
class _PasskeyApprovalListener extends StatefulWidget {
  const _PasskeyApprovalListener();

  @override
  State<_PasskeyApprovalListener> createState() =>
      _PasskeyApprovalListenerState();
}

class _PasskeyApprovalListenerState extends State<_PasskeyApprovalListener> {
  // Captured in initState, never resolved from the locator in dispose: a
  // teardown must not require the registration to still be there (the golden
  // ordering rule in AGENTS.md).
  //
  // Nullable because the service is desktop-only and the shell is not: a
  // host that never registered it — a widget test, a mobile build — mounts
  // this widget and it simply does nothing. Resolving unconditionally would
  // make every vault-shell test depend on a desktop bridge.
  DesktopPasskeyApprovalService? _approvals;
  bool _isAsking = false;

  @override
  void initState() {
    super.initState();
    if (di.sl.isRegistered<DesktopPasskeyApprovalService>()) {
      final approvals = di.sl<DesktopPasskeyApprovalService>();
      _approvals = approvals;
      approvals.pendingListenable.addListener(_onPendingChanged);
    }
  }

  @override
  void dispose() {
    final approvals = _approvals;
    if (approvals != null) {
      approvals.pendingListenable.removeListener(_onPendingChanged);
      // The shell is going away — a lock, a database switch, a close.
      // Whatever was waiting on this window gets its no rather than a
      // signature nobody is left to approve.
      approvals.declineAll();
    }
    super.dispose();
  }

  void _onPendingChanged() {
    final prompt = _approvals?.pendingListenable.value;
    if (prompt == null || _isAsking || !mounted) return;
    unawaited(_ask(prompt));
  }

  Future<void> _ask(PasskeyAssertionPrompt prompt) async {
    _isAsking = true;
    try {
      final account = prompt.username.trim().isEmpty
          ? 'the account with no username'
          : '“${prompt.username.trim()}”';
      final record = prompt.entryTitle.trim().isEmpty
          ? 'a record in this vault'
          : '“${prompt.entryTitle.trim()}”';
      final approved = await showKvConfirmDialog(
        context,
        title: 'Sign in to ${prompt.relyingPartyId}?',
        body:
            '${prompt.origin} is asking to sign in with the passkey on '
            '$record, for $account.\n\n'
            'Approving signs one challenge from that page. It does not give '
            'the page your passkey, your password or anything else from this '
            'vault.',
        confirmLabel: 'Sign in',
      );
      _approvals?.resolve(approved: approved == true);
    } finally {
      _isAsking = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
