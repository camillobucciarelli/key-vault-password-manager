/// spec 014 FR-5 recovery contract: report unreadable metadata, and discard
/// it when the user explicitly asks. Discarding is never implicit — a write
/// refused by [MetadataStorageUnreadableFailure] stays refused until the user
/// decides.
abstract class MetadataRecoveryRepository {
  /// True when metadata ciphertext exists that no key can open.
  Future<bool> hasUnreadableMetadata();

  /// Moves unreadable metadata aside so writes can resume under a fresh key.
  /// Returns how many files were moved.
  Future<int> discardUnreadableMetadata();
}

/// Default for callers that never hit the FR-5 state (tests, and flows with
/// no metadata of their own). Reports nothing unreadable and discards
/// nothing.
class NoopMetadataRecoveryRepository implements MetadataRecoveryRepository {
  const NoopMetadataRecoveryRepository();

  @override
  Future<bool> hasUnreadableMetadata() async => false;

  @override
  Future<int> discardUnreadableMetadata() async => 0;
}
