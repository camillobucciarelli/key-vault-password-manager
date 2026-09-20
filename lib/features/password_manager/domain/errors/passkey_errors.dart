/// spec 023 — the passkey named by a delete (or a sign-in) is not in the
/// entry any more.
///
/// The UI holds a `VaultPasskey` read at some earlier moment; by the time the
/// write runs the file may have been synced, merged or edited elsewhere.
/// Matching on `(relyingPartyId, credentialId)` rather than on the field
/// suffix means a reordered group is still found, and this error means the
/// credential itself is gone — not that the lookup drifted.
final class PasskeyNotFound implements Exception {
  const PasskeyNotFound({required this.entryId, required this.relyingPartyId});

  final String entryId;
  final String relyingPartyId;

  @override
  String toString() =>
      'PasskeyNotFound(entryId: $entryId, relyingPartyId: $relyingPartyId)';
}
