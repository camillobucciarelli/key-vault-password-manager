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

/// spec 023 US3 FR-019 — the entry already holds a passkey for this relying
/// party and account.
///
/// Thrown rather than overwritten: a passkey has exactly one copy of its
/// private key, so replacing one silently is how a user loses a credential
/// they could still have been signing in with.
final class PasskeyAlreadyExists implements Exception {
  const PasskeyAlreadyExists({
    required this.entryId,
    required this.relyingPartyId,
  });

  final String entryId;
  final String relyingPartyId;

  @override
  String toString() =>
      'PasskeyAlreadyExists(entryId: $entryId, '
      'relyingPartyId: $relyingPartyId)';
}

/// spec 023 T207 / FR-011a — a merge would have put two different passkeys
/// for the same relying party and account on one entry.
///
/// Refused rather than resolved: the two are different credentials, only the
/// relying party knows which one it still trusts, and an entry holding both
/// would offer the user a sign-in that fails half the time. The merge is
/// abandoned whole, so nothing is written.
final class PasskeyMergeConflict implements Exception {
  const PasskeyMergeConflict({
    required this.primaryId,
    required this.secondaryId,
    required this.relyingPartyId,
  });

  final String primaryId;
  final String secondaryId;
  final String relyingPartyId;

  @override
  String toString() =>
      'PasskeyMergeConflict(primaryId: $primaryId, '
      'secondaryId: $secondaryId, relyingPartyId: $relyingPartyId)';
}
