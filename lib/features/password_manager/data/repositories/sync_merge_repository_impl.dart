// spec-008 T302/T302a/T303 — the data-owned implementation of the frozen merge
// port.
//
// **The whole point of this file is that it is the only thing that knows.** The
// domain port speaks in opaque ids, redacted decisions and safe codes; every
// fact those stand for — the canonical path, the master password, the key-file
// bytes, the two `KdbxFile`s, the object UUIDs, the field keys, the decrypted
// values and the attachment bytes — lives here, in `_MergeSession`, and is
// dropped when the session is cancelled, invalidated or completed.
//
// **What this slice does NOT do, deliberately.**
//
//   * It performs **no filesystem write and no upload**. `commit` refuses. The
//     FR-7 write-verify-converge cycle, the collision-safe backup, the atomic
//     replace and the pending-upload recovery record are T401-T410, and the
//     per-platform atomicity artifacts Gate 1 T111 owes are still `not-run`, so
//     there is nothing to enable yet either. A merge that wrote before those
//     landed would be the one failure mode the whole spec exists to prevent.
//   * Because it never writes, it takes **no `DatabasePathMutex`**. That is not
//     an omission: Gate 1's routing guard pins the exact set of files that may
//     reference the mutex, and adding this one to that set while it acquires
//     nothing would be a false claim. `startReview` is explicitly lock-free
//     under FR-8 ("Review holds no mutex; edits may make review stale"), and
//     T403 — the commit that does write — is where the lock belongs, at the
//     outermost level, because the mutex is not reentrant.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';

import '../../domain/entities/database_record.dart';
import '../../domain/models/merge_field_display.dart';
import '../../domain/models/sync_merge_models.dart';
import '../../domain/repositories/database_registry_repository.dart';
import '../../domain/repositories/database_security_repository.dart';
import '../../domain/repositories/database_sync_repository.dart';
import '../../domain/repositories/sync_merge_repository.dart';
import '../datasources/local_data_source.dart';
import '../datasources/secure_data_source.dart';
import '../services/kdbx_merge_adapter.dart';

/// spec-008 **T302a** — opaque id minting.
///
/// **This is where T202's "not derivable into sensitive values" actually
/// lives.** The frozen contract says so in as many words, because the id
/// *type* cannot deliver it: `ms-` + 32 lowercase hex is exactly the shape of
/// `'ms-' + md5(anything)`, so the shape check accepts a token that decodes
/// straight back to the thing it is supposed to hide. The type is a typo guard.
/// The guarantee is a property of this function and of nothing else.
///
/// Three commitments, each verified in
/// `test/.../data/repositories/sync_merge_repository_impl_test.dart`:
///
///   1. the source is [Random.secure] — a CSPRNG — and no other `Random`
///      instance exists in this library;
///   2. every token carries [_tokenEntropyBytes] × 8 = 128 bits;
///   3. no input reaches the token. Not the canonical path, not the registry
///      id, not an object UUID, not a field key, not an attachment name, not a
///      checksum, not a credential. The function takes **no argument** other
///      than its prefix, which is the strongest form that statement can take:
///      there is nothing to derive from.
const _tokenEntropyBytes = 16;

/// The one CSPRNG. Not injectable on purpose: a seam here would let a test —
/// or a future caller — substitute a predictable generator, and the whole
/// obligation of T302a is that the production path cannot be anything but
/// [Random.secure].
final Random _secureRandom = Random.secure();

String _mintToken(String prefix) {
  final buffer = StringBuffer(prefix)..write('-');
  for (var i = 0; i < _tokenEntropyBytes; i++) {
    buffer.write(_secureRandom.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

MergeSessionId _mintSessionId() => MergeSessionId(_mintToken('ms'));

MergeDecisionId _mintDecisionId() => MergeDecisionId(_mintToken('md'));

class SyncMergeRepositoryImpl implements SyncMergeRepository {
  SyncMergeRepositoryImpl({
    required DatabaseRegistryRepository registryRepository,
    required DatabaseSecurityRepository securityRepository,
    required DatabaseSyncRepository syncRepository,
    required SecureDataSource secureDataSource,
    required LocalDataSource localDataSource,
    KdbxMergeAdapter adapter = const KdbxMergeAdapter(),
  }) : _registry = registryRepository,
       _security = securityRepository,
       _sync = syncRepository,
       _secure = secureDataSource,
       _local = localDataSource,
       _adapter = adapter;

  final DatabaseRegistryRepository _registry;
  final DatabaseSecurityRepository _security;
  final DatabaseSyncRepository _sync;
  final SecureDataSource _secure;
  final LocalDataSource _local;
  final KdbxMergeAdapter _adapter;

  /// The private session store. Keyed by the minted token, so a caller can only
  /// reach a session by presenting an id this repository handed out.
  final Map<String, _MergeSession> _sessions = <String, _MergeSession>{};

  @override
  Future<MergeReviewSummary> startReview(MergeDatabaseId databaseId) async {
    final record = await _registry.getById(databaseId.value);
    if (record == null) {
      // D16: the id names nothing in the registry, so the state that made a
      // review possible is gone. Distinct from `sessionInvalidated`, which
      // means "the session you are holding is no longer valid".
      throw const SyncMergeFailure(MergeFailureCode.mergePreconditionFailed);
    }

    final credentials = await _resolveCredentials(record);
    final localBytes = await _readLocalBytes(record);
    final remoteBytes = await _downloadRemoteBytes(record);

    // FR-2: everything below happens BEFORE a session id exists, so a refusal
    // cannot leave a session, a backup, a local write or an upload behind.
    final localFile = await _open(localBytes, credentials);
    final remoteFile = await _open(remoteBytes, credentials);
    final pair = _adapter.validatePair(local: localFile, remote: remoteFile);
    final diff = _adapter.diffPresence(pair);

    final session = _MergeSession(
      sessionId: _mintSessionId(),
      databaseId: databaseId,
      canonicalPath: record.canonicalPath,
      credentials: credentials,
      pair: pair,
      diff: diff,
    );
    _buildDecisions(session);
    _sessions[session.sessionId.token] = session;
    return session.summary();
  }

  @override
  Future<MergeReviewSummary> updateDecision({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
    required MergeChoice choice,
  }) async {
    final session = _requireSession(sessionId);
    final entry = session.decisions[decisionId.token];
    if (entry == null) {
      throw const SyncMergeFailure(MergeFailureCode.sessionInvalidated);
    }
    // `withChoice` re-runs every FR-4/FR-5/FR-6 invariant, so a missing side or
    // a delete without evidence throws before it can reach the candidate.
    entry.redacted = entry.redacted.withChoice(choice);
    return session.summary();
  }

  @override
  Future<MergeCommitOutcome> commit(MergeSessionId sessionId) async {
    // Phase 4 (T401-T403) owns the write. Refusing is not a placeholder: the
    // per-platform atomicity artifacts (Gate 1 T111) are `not-run`, and FR-9
    // makes the feature disabled until the platform has its own passing
    // artifact. Nothing is written and the session is left intact, so the user
    // loses no review work.
    _requireSession(sessionId);
    return const MergeRejected(
      MergeFailureCode.platformDisabled,
      localCommitCompleted: false,
    );
  }

  /// spec-008 T301 (apply half) / T309 — the merge candidate, in memory.
  ///
  /// Applies the session's decisions to the local side, serializes it, reopens
  /// the result with the **original credentials** and validates the canonical
  /// semantic manifest before returning the bytes. Nothing is written: the
  /// caller that eventually does write them is T403, under the path mutex and
  /// through `SafeVaultFileWriter`.
  ///
  /// **The session is consumed here, before anything is applied**, and a second
  /// call returns [MergeFailureCode.sessionInvalidated].
  ///
  /// That is a constraint, not a convention, and the difference is not
  /// academic. [KdbxMergeAdapter.applyMerge] mutates the local side in place,
  /// so a second application re-imports every remote-only record into a tree
  /// that already contains it. In debug the library's own assertion fires and
  /// a raw `AssertionError` crosses the port, breaking the typed-refusal
  /// contract. **In release assertions are disabled**, `addEntry` proceeds, and
  /// the candidate carries two objects with the same UUID — precisely the FR-2
  /// violation `validatePair` exists to refuse, introduced by the merge itself.
  /// A comment saying "call this once" prevents neither.
  ///
  /// The session is removed first rather than last so that a failure anywhere
  /// below cannot leave a half-applied session reachable: the local `KdbxFile`
  /// has already been mutated by then, so it is no longer the local side of
  /// anything and must not be diffed, displayed or re-applied.
  Future<Uint8List> buildCandidateBytes(MergeSessionId sessionId) async {
    final session = _requireSession(sessionId);
    _sessions.remove(sessionId.token);

    try {
      final candidate = _adapter.applyMerge(
        pair: session.pair,
        diff: session.diff,
        resolution: session.resolution(),
      );
      // The merge is the one operation that can *create* a UUID collision, by
      // importing an object the tree already holds. `validatePair` is FR-2's
      // gate on the inputs; running it against the candidate makes it a gate on
      // the output too, which is the check that is missing in release where the
      // library's assertion is compiled out. Cost is one tree walk over a file
      // already in memory — cheaper than the serialization on the next line.
      _adapter.validatePair(local: candidate, remote: candidate);
      return await _adapter.serializeCandidate(
        candidate: candidate,
        credentials: session.credentials,
      );
    } finally {
      session.dispose();
    }
  }

  @override
  Future<void> cancel(MergeSessionId sessionId) async {
    _sessions.remove(sessionId.token)?.dispose();
  }

  @override
  Future<void> invalidate(MergeDatabaseId databaseId) async {
    final doomed = [
      for (final entry in _sessions.entries)
        if (entry.value.databaseId == databaseId) entry.key,
    ];
    for (final token in doomed) {
      _sessions.remove(token)?.dispose();
    }
  }

  @override
  Future<MergeRecoveryOutcome> recoverPending(
    MergeDatabaseId databaseId,
  ) async {
    // No upload has ever been dispatched by this repository, so no
    // `_PendingMergeUpload` record can exist. T404-T409 persist and triage it.
    return const MergeRecoveryOutcome(MergeRecoveryDisposition.none);
  }

  @override
  Future<MergeFieldDisplay> loadFieldDisplay({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
  }) async {
    final session = _requireSession(sessionId);
    final entry = session.decisions[decisionId.token];
    if (entry == null) {
      throw const SyncMergeFailure(MergeFailureCode.sessionInvalidated);
    }
    return entry.display(session);
  }

  // =========================================================================
  // Credentials and bytes. Everything below is data-private by construction.
  // =========================================================================

  Future<Credentials> _resolveCredentials(DatabaseRecord record) async {
    final password = await _secure.getMasterPassword(record.databaseId);
    if (password == null || password.isEmpty) {
      throw const SyncMergeFailure(MergeFailureCode.credentialsRevoked);
    }

    final profile = await _security.getProfile(record.databaseId);
    var keyFilePath = profile?.keyFilePath;
    if (keyFilePath == null || keyFilePath.trim().isEmpty) {
      // FR's "cached fallback ... only for matching active database": the
      // cached path is process-wide, so it may only be used when the database
      // being merged IS the active one.
      final activeId = await _registry.getActive();
      if (activeId == record.databaseId) {
        keyFilePath = await _local.getCachedKeyFilePath();
      }
    }

    Uint8List? keyFileBytes;
    if (keyFilePath != null && keyFilePath.trim().isNotEmpty) {
      final keyFile = File(keyFilePath);
      if (!await keyFile.exists()) {
        throw const SyncMergeFailure(MergeFailureCode.credentialsRevoked);
      }
      keyFileBytes = await keyFile.readAsBytes();
    }

    return Credentials.composite(
      ProtectedValue.fromString(password),
      keyFileBytes,
    );
  }

  Future<Uint8List> _readLocalBytes(DatabaseRecord record) async {
    final file = File(record.canonicalPath);
    if (!await file.exists()) {
      // Deliberately NOT `mergePreconditionFailed` (D16): `staleLocal` is the
      // least-wrong code that exists here, because its user-facing remedy —
      // "the local side is not what the registry recorded, resynchronize
      // instead of writing" — is correct for an absent file too.
      throw const SyncMergeFailure(MergeFailureCode.staleLocal);
    }
    return file.readAsBytes();
  }

  Future<Uint8List> _downloadRemoteBytes(DatabaseRecord record) async {
    final mapping = await _sync.getMapping(record.canonicalPath);
    if (mapping == null) {
      // D16: no remote to merge against. A merge review is only reachable from
      // a linked database, so reaching here means the mapping vanished under
      // the caller — a precondition, not a stale session.
      throw const SyncMergeFailure(MergeFailureCode.mergePreconditionFailed);
    }
    try {
      return await _sync.downloadRemoteFile(mapping.driveFileId);
    } on SyncMergeFailure {
      rethrow;
    } on Object {
      // The raw transport error never crosses the port: it can carry a file
      // id, a URL and an account label.
      throw const SyncMergeFailure(MergeFailureCode.uploadOutcomeAmbiguous);
    }
  }

  Future<KdbxFile> _open(Uint8List bytes, Credentials credentials) async {
    try {
      return await _adapter.openSide(bytes: bytes, credentials: credentials);
    } on KdbxInvalidKeyException {
      // The adapter deliberately lets this through unmapped: whether a
      // credential still opens the file is the repository's concern, not a
      // property of the KDBX construct.
      throw const SyncMergeFailure(MergeFailureCode.credentialsRevoked);
    }
  }

  _MergeSession _requireSession(MergeSessionId sessionId) {
    final session = _sessions[sessionId.token];
    // The disposed check is redundant with the removal at every call site, and
    // deliberately kept: it makes "disposed" the authority rather than "still
    // in the map", so a future edit that forgets one removal cannot serve a
    // session whose KdbxFile has already been consumed.
    if (session == null || session.isDisposed) {
      throw const SyncMergeFailure(MergeFailureCode.sessionInvalidated);
    }
    return session;
  }

  // =========================================================================
  // Redaction: private evidence -> domain decisions.
  // =========================================================================

  void _buildDecisions(_MergeSession session) {
    var ordinal = 0;

    for (final field in session.diff.fieldDiffs) {
      if (field.classification != KdbxFieldClassification.fieldConflict) {
        continue;
      }
      final local = field.local as KdbxFieldPresent;
      final remote = field.remote as KdbxFieldPresent;
      final relation = session.timestampRelationFor(field.entryUuid);
      final decisionId = _mintDecisionId();
      session.decisions[decisionId.token] = _DecisionRecord.forField(
        fieldDiff: field,
        redacted: RedactedMergeDecision(
          decisionId: decisionId,
          ordinal: ordinal++,
          kind: MergeDecisionKind.fieldConflict,
          category: _categoryOf(field),
          presence: MergePresence.presentBoth,
          choice: _defaultFieldChoice(relation, local, remote),
          isDefault: true,
          timestampRelation: relation,
        ),
      );
    }

    for (final record in session.diff.deletionConflicts) {
      final decisionId = _mintDecisionId();
      session.decisions[decisionId.token] = _DecisionRecord.forRecord(
        recordDiff: record,
        redacted: RedactedMergeDecision(
          decisionId: decisionId,
          ordinal: ordinal++,
          kind: MergeDecisionKind.recordDeletionConflict,
          category: record.objectKind == KdbxMergeObjectKind.group
              ? MergeFieldCategory.groupMetadata
              : MergeFieldCategory.other,
          presence: record.local.evidence == KdbxRecordEvidence.live
              ? MergePresence.localOnly
              : MergePresence.remoteOnly,
          // FR-5: the automatic default is always Keep, so an unattended
          // session can never delete. The constructor enforces it too.
          choice: MergeChoice.keep,
          isDefault: true,
          timestampRelation: _relationOf(
            record.local.modifiedAtUtc,
            record.remote.modifiedAtUtc,
          ),
        ),
      );
    }
  }

  MergeFieldCategory _categoryOf(KdbxFieldDiff field) {
    if (field.fieldKind == KdbxMergeFieldKind.attachment) {
      return MergeFieldCategory.attachment;
    }
    switch (field.canonicalKey) {
      case 'title':
        return MergeFieldCategory.title;
      case 'username':
        return MergeFieldCategory.username;
      case 'password':
        return MergeFieldCategory.password;
      case 'url':
        return MergeFieldCategory.url;
      case 'notes':
        return MergeFieldCategory.notes;
      case 'otp':
      case 'totp':
      case 'otpauth':
        return MergeFieldCategory.otp;
      default:
        return MergeFieldCategory.customField;
    }
  }

  /// FR-3's default, computed from the data alone.
  ///
  /// Known modification time beats unknown; then newer wins; then the greater
  /// UTF-8 byte sequence wins. **Never "prefer local"** — that is
  /// perspective-dependent, so two devices holding the same pair would pick
  /// opposite winners, write over each other and oscillate across sessions,
  /// which no retry budget can stop.
  ///
  /// For an attachment the compared value is the SHA-256 digest rather than the
  /// bytes. It is still a function of the content alone and still identical on
  /// both devices, which is everything the tie-break requires; carrying the
  /// bytes into a comparator would put them one refactor away from a log line.
  ///
  /// T401a owns the full tie-break and promotes the T009 model properties to
  /// adapter-level tests. This is the same order, applied where the frozen
  /// contract forces a visible default to exist from the first review.
  MergeChoice _defaultFieldChoice(
    TimestampRelation relation,
    KdbxFieldPresent local,
    KdbxFieldPresent remote,
  ) {
    switch (relation) {
      case TimestampRelation.localNewer:
      case TimestampRelation.localKnownRemoteUnknown:
        return MergeChoice.local;
      case TimestampRelation.remoteNewer:
      case TimestampRelation.remoteKnownLocalUnknown:
        return MergeChoice.remote;
      case TimestampRelation.tie:
      case TimestampRelation.bothUnknown:
        return compareUtf8Bytes(local.semanticValue, remote.semanticValue) >= 0
            ? MergeChoice.local
            : MergeChoice.remote;
    }
  }
}

TimestampRelation _relationOf(DateTime? local, DateTime? remote) {
  if (local == null && remote == null) return TimestampRelation.bothUnknown;
  if (remote == null) return TimestampRelation.localKnownRemoteUnknown;
  if (local == null) return TimestampRelation.remoteKnownLocalUnknown;
  if (local.isAfter(remote)) return TimestampRelation.localNewer;
  if (remote.isAfter(local)) return TimestampRelation.remoteNewer;
  return TimestampRelation.tie;
}

/// One review session's private state.
///
/// Not `Equatable`, not serializable, `toString` redacted. Everything the port
/// must never expose is reachable from here and from nowhere else.
final class _MergeSession {
  _MergeSession({
    required this.sessionId,
    required this.databaseId,
    required this.canonicalPath,
    required this.credentials,
    required this.pair,
    required this.diff,
  });

  final MergeSessionId sessionId;
  final MergeDatabaseId databaseId;
  final String canonicalPath;
  final Credentials credentials;
  final KdbxMergePair pair;
  final KdbxPresenceDiff diff;

  /// Keyed by the minted decision token.
  final Map<String, _DecisionRecord> decisions = <String, _DecisionRecord>{};

  bool _disposed = false;

  TimestampRelation timestampRelationFor(String entryUuid) {
    final record = diff.recordDiffs.firstWhere(
      (r) => r.objectUuid == entryUuid,
    );
    return _relationOf(record.local.modifiedAtUtc, record.remote.modifiedAtUtc);
  }

  KdbxEntry? entryOn(KdbxFile file, String uuid) {
    for (final entry in file.body.rootGroup.getAllEntries()) {
      if (entry.uuid.uuid == uuid) return entry;
    }
    return null;
  }

  KdbxObject? objectOn(KdbxFile file, String uuid) {
    for (final object in file.body.rootGroup.getAllGroupsAndEntries()) {
      if (object.uuid.uuid == uuid) return object;
    }
    return null;
  }

  MergeReviewSummary summary() {
    final ordered = decisions.values.toList()
      ..sort((a, b) => a.redacted.ordinal.compareTo(b.redacted.ordinal));
    return MergeReviewSummary(
      sessionId: sessionId,
      databaseId: databaseId,
      phase: MergeReviewPhase.reviewing,
      decisions: [for (final entry in ordered) entry.redacted],
      localOnlyRecordCount:
          diff.localOnlyEntryUuids.length + diff.localOnlyGroupUuids.length,
      remoteOnlyRecordCount:
          diff.remoteOnlyEntryUuids.length + diff.remoteOnlyGroupUuids.length,
      oneSidedFieldCount: diff.oneSidedFieldCount,
    );
  }

  /// The private evidence the resolved candidate is built from (T403 consumes
  /// it). Kept here so the translation from redacted decisions to KDBX
  /// operations happens exactly once, on this side of the port.
  KdbxMergeResolution resolution() {
    final fieldChoices = <KdbxFieldRef, MergeChoice>{};
    final recordChoices = <String, MergeChoice>{};
    for (final entry in decisions.values) {
      final field = entry.field;
      if (field != null) {
        fieldChoices[kdbxFieldRefOf(field)] = entry.redacted.choice;
        continue;
      }
      recordChoices[entry.record!.objectUuid] = entry.redacted.choice;
    }
    return KdbxMergeResolution(
      fieldChoices: fieldChoices,
      recordChoices: recordChoices,
    );
  }

  bool get isDisposed => _disposed;

  void dispose() {
    decisions.clear();
    _disposed = true;
  }

  @override
  String toString() => '_MergeSession(<redacted>)';
}

/// One decision: the redacted row that crosses the port, plus the private
/// evidence it stands for. The two are never merged into one object — that is
/// the whole boundary.
final class _DecisionRecord {
  _DecisionRecord.forField({
    required KdbxFieldDiff fieldDiff,
    required this.redacted,
  }) : field = fieldDiff,
       record = null;

  _DecisionRecord.forRecord({
    required KdbxRecordDiff recordDiff,
    required this.redacted,
  }) : record = recordDiff,
       field = null;

  final KdbxFieldDiff? field;
  final KdbxRecordDiff? record;

  RedactedMergeDecision redacted;

  /// The single transient plaintext read (T203). This is the ONLY method in
  /// the whole data implementation that produces a value the presentation layer
  /// can read, and its result is non-`Equatable`, non-serializable, redacted in
  /// `toString` and disposable.
  MergeFieldDisplay display(_MergeSession session) {
    final field = this.field;
    if (field != null) return _fieldDisplay(session, field);
    return _recordDisplay(session, record!);
  }

  MergeFieldDisplay _fieldDisplay(_MergeSession session, KdbxFieldDiff field) {
    final localEntry = session.entryOn(
      session.pair.local.file,
      field.entryUuid,
    );
    final remoteEntry = session.entryOn(
      session.pair.remote.file,
      field.entryUuid,
    );
    final protected =
        (field.local is KdbxFieldPresent &&
            (field.local as KdbxFieldPresent).isProtected) ||
        (field.remote is KdbxFieldPresent &&
            (field.remote as KdbxFieldPresent).isProtected);

    return MergeFieldDisplay(
      // FR-4 keeps a custom field / attachment name data-private until exactly
      // this transient response is requested.
      label: field.localKey ?? field.remoteKey ?? field.canonicalKey,
      local: _side(field, field.local, field.localKey, localEntry),
      remote: _side(field, field.remote, field.remoteKey, remoteEntry),
      protected: protected,
    );
  }

  MergeDisplaySide _side(
    KdbxFieldDiff field,
    KdbxFieldPresence presence,
    String? spelling,
    KdbxEntry? entry,
  ) {
    if (presence is! KdbxFieldPresent || spelling == null || entry == null) {
      return MergeDisplaySide.missing();
    }
    final changedAt = entry.times.lastModificationTime.get();
    if (field.fieldKind == KdbxMergeFieldKind.attachment) {
      return MergeDisplaySide.present(
        spelling,
        changedAt: changedAt,
        sizeBytes: presence.length,
        // A short prefix of the digest, never the bytes and never the whole
        // checksum: enough to tell "same name, different content" apart.
        fingerprint: presence.semanticValue.substring(0, 12),
      );
    }
    return MergeDisplaySide.present(
      entry.getString(KdbxKey(spelling))?.getText() ?? '',
      changedAt: changedAt,
    );
  }

  MergeFieldDisplay _recordDisplay(
    _MergeSession session,
    KdbxRecordDiff record,
  ) {
    MergeDisplaySide sideOf(KdbxFile file, KdbxRecordSide side) {
      if (!side.isLiveSomewhere) return MergeDisplaySide.missing();
      final object = session.objectOn(file, record.objectUuid);
      if (object == null) return MergeDisplaySide.missing();
      final label = object is KdbxEntry
          ? object.getString(KdbxKeyCommon.TITLE)?.getText() ?? ''
          : (object as KdbxGroup).name.get() ?? '';
      return MergeDisplaySide.present(label, changedAt: side.modifiedAtUtc);
    }

    return MergeFieldDisplay(
      label: record.objectKind == KdbxMergeObjectKind.group ? 'group' : 'entry',
      local: sideOf(session.pair.local.file, record.local),
      remote: sideOf(session.pair.remote.file, record.remote),
      protected: false,
    );
  }
}
