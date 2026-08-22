// spec-008 T301/T304/T305/T306/T308/T309 — the production KDBX <-> merge-model
// adapter.
//
// **What this file is.** The data-layer bridge that reads two `.kdbx` sides,
// produces the evidence a per-field and per-record diff is computed from, and
// — since slice 2 — applies the resolved decisions and serializes the merge
// candidate. It is the promotion of the Gate 0 spike helpers (`_validateSide`,
// `_crossSideKindMismatch`, `_lineageMatches` in `vault_kdbx_service_test.dart`)
// from test-only code into production code, with the typed refusals the frozen
// domain contract defines.
//
// **What this file is NOT, and why.**
//
//   * It **never touches the filesystem**. The caller hands over bytes and gets
//     bytes back. There is therefore no `withDatabaseLock` and no
//     `SafeVaultFileWriter` call here, and Gate 1's writer-routing guard has
//     nothing to route — building a candidate in memory is not a write, which
//     is a stronger statement than "it takes the mutex". The merge commit that
//     does write the candidate to disk (T403) is a separate, later task and
//     routes through both.
//   * It does **not** call `KdbxFile.merge`. That method is marked unfinished
//     upstream and is forbidden by the spec; a source scan in
//     `vault_kdbx_service_test.dart` enforces it over this file too. The record
//     import below is written against `cloneInto`/`forceSetUuid` instead, which
//     is what the Gate 0 T003 spike proved.
//
// **Secret boundary (T303).** `Credentials`, `KdbxFile`, decrypted string
// values and attachment bytes are legitimate in `data/` and illegitimate
// anywhere else. Nothing in this file is reachable from `domain/` or
// `presentation/` — enforced by `sync_merge_domain_architecture_test.dart`. The
// diff model below deliberately carries an attachment's **digest and length**,
// never its bytes: the diff only needs to classify, and a model that carried
// plaintext would be one refactor away from a log line.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kdbx/kdbx.dart';
// Gate 0 recorded that the primitives a full-fidelity adapter needs sit outside
// `package:kdbx/kdbx.dart`'s export surface. `cloneInto` copies an entry —
// strings, binaries, custom data, times and history — across files, and
// `forceSetUuid` is what keeps the imported object's identity, which is the
// whole point of a UUID-matched merge.
// ignore: implementation_imports
import 'package:kdbx/src/kdbx_entry.dart' show KdbxEntryInternal;
// ignore: implementation_imports
import 'package:kdbx/src/kdbx_object.dart' show KdbxObjectInternal;

import '../../domain/models/sync_merge_models.dart';
import '../../domain/repositories/sync_merge_repository.dart';
import 'kdbx_semantic_manifest.dart';

/// What kind of object a live UUID denotes. FR-2 requires a UUID that appears
/// on both sides to denote the same kind on both.
enum KdbxMergeObjectKind { group, entry }

/// Which namespace a field key lives in. A string key and an attachment name
/// are compared separately even when they spell the same thing: KDBX stores
/// them in two different collections and FR-4's rules apply inside each.
enum KdbxMergeFieldKind { string, attachment }

/// The key KDBX itself matches on: **case-insensitive, case-preserving**.
///
/// `KdbxKey` (kdbx 2.5.0, `kdbx_entry.dart`) defines `==` and `hashCode` over
/// `key.toLowerCase()`, and both `_strings` and `_binaries` are keyed by it. So
/// `Custom_Totp` and `custom_totp` are **one field** to KDBX, and a diff that
/// keys on the verbatim spelling sees two.
///
/// That is not a cosmetic mismatch. It fails twice:
///
///   1. a real value conflict is reported as two automatic one-sided unions, so
///      FR-4's review never shows it to the user;
///   2. the union is not applicable — writing both members into one entry
///      collapses them onto a single key, one value is lost in silence, and
///      which one survives depends on iteration order. Two devices then
///      converge on different bytes, which is exactly the commutativity FR-3
///      exists to guarantee.
///
/// The case that misled the first implementation is `Title` vs `title`: it
/// behaves correctly, because `setString` on an existing entry resolves through
/// `KdbxKey.==` onto the key already stored and KDBX keeps the original
/// spelling. The defect needs the two sides to create the key **independently**
/// — which is the merge scenario and nothing else, and is reachable from any
/// user-typed custom field name or any importer, this repository's own import
/// paths included.
String canonicalFieldKey(String key) => key.toLowerCase();

/// FR-4's presence model, made explicit.
///
/// **Presence is independent of value.** A present empty string and a present
/// zero-byte attachment are [KdbxFieldPresent], never [KdbxFieldMissing] — that
/// distinction is the whole point of the type existing instead of a nullable
/// `String`, which is exactly the representation that collapses the two.
sealed class KdbxFieldPresence {
  const KdbxFieldPresence();

  bool get isPresent;
}

/// The field exists on this side. [semanticValue] is the comparison key, not
/// the plaintext payload:
///
///   * for a string it is the text **verbatim**;
///   * for an attachment it is the SHA-256 digest, so equal-name /
///     different-bytes is detected without the bytes entering this model.
///
/// Protection status is **not** folded into [semanticValue]; it is compared
/// alongside it, in [sameAs], out of [isProtected]. Anyone refactoring `sameAs`
/// must keep both halves: dropping the [isProtected] comparison would make a
/// plain-to-protected change compare `identical` and be silently discarded.
///
/// **No normalisation is applied to a string value, deliberately.** No `trim`,
/// no Unicode normalisation, no case folding. Two values differing only in NFC
/// vs NFD, or only in trailing whitespace, are a [KdbxFieldClassification
/// .fieldConflict] and go to the user. That is the conservative direction: a
/// silent normalisation rewrites a value the user stored — and in a password
/// field a trimmed trailing space is a credential that no longer works. Guarded
/// by tests, so a future "helpful" `trim()` fails instead of shipping.
final class KdbxFieldPresent extends KdbxFieldPresence {
  const KdbxFieldPresent({
    required this.semanticValue,
    required this.isProtected,
    required this.length,
  });

  /// Builds the present state of a KDBX string.
  ///
  /// **Absence of the *key* is the only thing that means missing.** A key
  /// holding an empty value is present.
  ///
  /// The null [StringValue] branch is defensive and, on kdbx 2.5.0, unreachable
  /// through the reader and `setString`: `_strings` is typed
  /// `Map<KdbxKey, StringValue?>`, but the XML reader always constructs a
  /// `PlainValue` (`kdbx_entry.dart:187-197`) and `setString(key, null)`
  /// **removes** the key rather than storing a null (`kdbx_entry.dart:341-352`;
  /// `removeString` is an alias for exactly that). It is not unreachable in
  /// general: `renameKey` with an absent `oldKey` writes `_strings[newKey] =
  /// null` with no guard (`kdbx_entry.dart:355-359`). The adapter never calls
  /// `renameKey`, so that path cannot originate here — but the branch is kept,
  /// and is the reason it is not an assertion.
  /// So the three states the type suggests — absent, null, empty — are two in
  /// any vault, and one fewer again after a save: `<Value/>` reads back as an
  /// empty `PlainValue`. It is mapped to present-empty rather than to missing,
  /// because a key that exists is present; the alternative would make presence
  /// depend on a value, which is the one thing FR-4 forbids.
  factory KdbxFieldPresent.string(StringValue? value) {
    final text = value?.getText() ?? '';
    return KdbxFieldPresent(
      semanticValue: text,
      isProtected: value is ProtectedValue,
      length: text.length,
    );
  }

  /// Builds the present state of a KDBX attachment. Zero bytes is present.
  factory KdbxFieldPresent.attachment(KdbxBinary binary) {
    final bytes = binary.value;
    return KdbxFieldPresent(
      semanticValue: sha256.convert(bytes).toString(),
      isProtected: binary.isProtected,
      length: bytes.length,
    );
  }

  final String semanticValue;
  final bool isProtected;
  final int length;

  @override
  bool get isPresent => true;

  /// Semantic equality for FR-4's "present, equal" row. Protection status is
  /// part of the compared semantics, so a value that only changed from plain
  /// to protected is a genuine conflict rather than a silent overwrite.
  bool sameAs(KdbxFieldPresent other) =>
      semanticValue == other.semanticValue && isProtected == other.isProtected;

  /// Deliberately redacted. This object holds a decrypted value.
  @override
  String toString() => 'KdbxFieldPresent(<redacted>)';
}

/// The field does not exist on this side. **This is not deletion evidence**
/// (FR-4): KDBX has no field-level or attachment-level tombstone, so a missing
/// field is an automatic union member, never a delete.
final class KdbxFieldMissing extends KdbxFieldPresence {
  const KdbxFieldMissing();

  @override
  bool get isPresent => false;

  @override
  String toString() => 'KdbxFieldMissing()';
}

/// FR-4's classification of one field across the two sides.
///
/// `fieldDeletionConflict` has **no member here on purpose.** It requires
/// "explicit field deletion evidence proven by the adapter", and the Gate 0
/// spike proved the installed library exposes deletion evidence only at object
/// level (`DeletedObjects`), never per field or per attachment. Emitting the
/// classification anyway would be the adapter *claiming* evidence it does not
/// have, which FR-4 forbids in the same paragraph. Record-level deletion
/// evidence is FR-5 and lands with T308.
enum KdbxFieldClassification {
  /// Present on both sides with the same semantic value.
  identical,

  /// Present on both sides with different semantic values — a real conflict.
  fieldConflict,

  /// Present locally, missing remotely, no deletion evidence: automatic union.
  fieldLocalOnly,

  /// Missing locally, present remotely, no deletion evidence: automatic union.
  fieldRemoteOnly,
}

/// One field's evidence, for one entry, across both sides.
final class KdbxFieldDiff {
  const KdbxFieldDiff({
    required this.entryUuid,
    required this.fieldKind,
    required this.canonicalKey,
    required this.localKey,
    required this.remoteKey,
    required this.local,
    required this.remote,
    required this.classification,
  });

  /// The KDBX entry UUID both sides agree on. Data-private: FR-2 keeps raw
  /// UUIDs out of logs, state and the domain port.
  final String entryUuid;
  final KdbxMergeFieldKind fieldKind;

  /// The key the two sides are **matched** on — [canonicalFieldKey], i.e. what
  /// KDBX itself matches on. Never written back to a vault.
  final String canonicalKey;

  /// The original key spelling on each side, verbatim, `null` where that side
  /// has no such field. FR-1 keeps original key spelling, so the adapter
  /// preserves both rather than canonicalising one away: the canonical form is
  /// a *match key*, not a value.
  final String? localKey;
  final String? remoteKey;

  final KdbxFieldPresence local;
  final KdbxFieldPresence remote;
  final KdbxFieldClassification classification;

  /// Both sides hold this field but spell its key differently — e.g. local
  /// `Custom_Totp`, remote `custom_totp`.
  ///
  /// **The adapter reports this and does not resolve it.** Neither FR-1 nor
  /// FR-4 says which spelling wins, and the three answers available are all
  /// decisions rather than derivations: "keep local" is perspective-dependent
  /// and FR-3 forbids that class outright (two devices would pick opposite
  /// spellings and never converge); "make it a conflict" would send a row to
  /// the user whose *values* agree, which FR-4's "present, equal → identical"
  /// row denies; and applying FR-3's deterministic UTF-8 order is very probably
  /// right but belongs to T401a, which owns that comparator and has not been
  /// written. Producing the evidence and leaving the choice to the apply step
  /// is the conservative option: nothing is lost, nothing is invented, and the
  /// decision is recorded as open. Raised to the PM with this slice.
  ///
  /// Classification is unaffected: it is driven by the values, so the fixture
  /// `Custom_Totp='AAA'` vs `custom_totp='BBB'` is one
  /// [KdbxFieldClassification.fieldConflict], which is what the user must see.
  bool get keySpellingDiverges =>
      localKey != null && remoteKey != null && localKey != remoteKey;

  @override
  String toString() => 'KdbxFieldDiff(<redacted>)';
}

/// What one side knows about one object, re-derived from that side's tree and
/// `DeletedObjects` list.
///
/// **Why this has to be re-derived rather than read off the presence sets.**
/// Deleting an entry in this app moves it to the recycle bin. A recycle-binned
/// object is still a *live object in the KDBX tree*: it appears in
/// `getAllGroupsAndEntries`, it is shared with the other side, and its fields
/// keep diffing as though nothing happened. Meanwhile the recycle-bin group
/// itself shows up as an ordinary one-sided group on whichever side created it.
/// Neither fact is deletion evidence, and neither is visible in a UUID set — so
/// bin membership is computed here by walking down from `KdbxFile.recycleBin`,
/// and permanent deletion is read from the `DeletedObjects` tombstone list.
enum KdbxRecordEvidence {
  /// Live in the tree, outside the recycle bin.
  live,

  /// Live in the tree, inside the recycle bin subtree (a move-to-bin).
  recycled,

  /// Absent from the tree with a matching `DeletedObjects` tombstone.
  tombstoned,

  /// Absent from the tree with no tombstone. FR-4: **not** deletion evidence.
  absent,
}

/// One side's evidence about one object.
final class KdbxRecordSide {
  const KdbxRecordSide({
    required this.evidence,
    this.modifiedAtUtc,
    this.deletedAtUtc,
  });

  const KdbxRecordSide.absent()
    : evidence = KdbxRecordEvidence.absent,
      modifiedAtUtc = null,
      deletedAtUtc = null;

  final KdbxRecordEvidence evidence;

  /// KDBX `LastModificationTime` where the object is live on this side.
  final DateTime? modifiedAtUtc;

  /// Tombstone `DeletionTime` where this side holds one.
  final DateTime? deletedAtUtc;

  bool get isLiveSomewhere =>
      evidence == KdbxRecordEvidence.live ||
      evidence == KdbxRecordEvidence.recycled;

  // A constant literal, even though `evidence` is a safe enum: the rule the
  // gate enforces is "no interpolation at all", because an interpolation that
  // is safe today is one field away from carrying a decrypted value, and the
  // reviewer who adds that field will not re-read this method.
  @override
  String toString() => 'KdbxRecordSide(<redacted>)';
}

/// FR-5's record-level classification of one object across the two sides.
enum KdbxRecordClassification {
  /// Live and un-binned on both sides: the ordinary shared record, and the
  /// only classification whose fields are diffed.
  sharedLive,

  /// Live on the local side, no evidence at all on the remote: automatic union.
  recordLocalOnly,

  /// Live on the remote side, no evidence at all on the local: automatic union.
  recordRemoteOnly,

  /// Live one side, deleted (binned or tombstoned) on the other. FR-5 requires
  /// an explicit keep/delete; the default is keep.
  recordDeletionConflict,

  /// Deleted on both sides. Stays deleted; the tombstone/bin evidence of both
  /// sides is preserved.
  recordDeleted,
}

/// One object's record-level evidence across both sides.
final class KdbxRecordDiff {
  const KdbxRecordDiff({
    required this.objectUuid,
    required this.objectKind,
    required this.local,
    required this.remote,
    required this.classification,
  });

  final String objectUuid;
  final KdbxMergeObjectKind objectKind;
  final KdbxRecordSide local;
  final KdbxRecordSide remote;
  final KdbxRecordClassification classification;

  @override
  String toString() => 'KdbxRecordDiff(<redacted>)';
}

/// The read-only evidence a diff is computed from: how every object classifies
/// at record level (FR-5), and how every field of every shared live entry
/// classifies at field level (FR-4).
final class KdbxPresenceDiff {
  KdbxPresenceDiff({
    required List<KdbxRecordDiff> recordDiffs,
    required List<KdbxFieldDiff> fieldDiffs,
  }) : recordDiffs = List.unmodifiable(recordDiffs),
       fieldDiffs = List.unmodifiable(fieldDiffs);

  /// Every object live on at least one side, sorted by UUID so two devices
  /// produce the same evidence in the same order.
  ///
  /// An object tombstoned on both sides and live on neither is deliberately
  /// **not** here: it carries no decision and has no fields. Its tombstones are
  /// still unioned when the candidate is built (FR-5 "preserve newest supported
  /// deletion data").
  final List<KdbxRecordDiff> recordDiffs;

  /// Only fields of entries [KdbxRecordClassification.sharedLive] on both
  /// sides. A one-sided entry's fields are not a field-level decision — the
  /// whole record is an automatic union member — and neither are the fields of
  /// a record whose *existence* is being decided.
  final List<KdbxFieldDiff> fieldDiffs;

  Set<String> _uuidsWhere(
    KdbxRecordClassification classification,
    KdbxMergeObjectKind kind,
  ) => {
    for (final record in recordDiffs)
      if (record.classification == classification && record.objectKind == kind)
        record.objectUuid,
  };

  Set<String> get localOnlyEntryUuids => _uuidsWhere(
    KdbxRecordClassification.recordLocalOnly,
    KdbxMergeObjectKind.entry,
  );

  Set<String> get remoteOnlyEntryUuids => _uuidsWhere(
    KdbxRecordClassification.recordRemoteOnly,
    KdbxMergeObjectKind.entry,
  );

  Set<String> get localOnlyGroupUuids => _uuidsWhere(
    KdbxRecordClassification.recordLocalOnly,
    KdbxMergeObjectKind.group,
  );

  Set<String> get remoteOnlyGroupUuids => _uuidsWhere(
    KdbxRecordClassification.recordRemoteOnly,
    KdbxMergeObjectKind.group,
  );

  /// FR-5 record-level decisions the user must answer.
  List<KdbxRecordDiff> get deletionConflicts => [
    for (final record in recordDiffs)
      if (record.classification ==
          KdbxRecordClassification.recordDeletionConflict)
        record,
  ];

  /// FR-4 one-sided field count for the redacted review summary.
  int get oneSidedFieldCount => fieldDiffs
      .where(
        (d) =>
            d.classification == KdbxFieldClassification.fieldLocalOnly ||
            d.classification == KdbxFieldClassification.fieldRemoteOnly,
      )
      .length;

  @override
  String toString() => 'KdbxPresenceDiff(<redacted>)';
}

/// Addresses one field of one entry, the way the diff matches it.
typedef KdbxFieldRef = ({
  String entryUuid,
  KdbxMergeFieldKind fieldKind,
  String canonicalKey,
});

KdbxFieldRef kdbxFieldRefOf(KdbxFieldDiff diff) => (
  entryUuid: diff.entryUuid,
  fieldKind: diff.fieldKind,
  canonicalKey: diff.canonicalKey,
);

/// The resolved answers the candidate is built from — data-private, and the
/// only thing the domain's redacted decisions are translated into.
final class KdbxMergeResolution {
  KdbxMergeResolution({
    Map<KdbxFieldRef, MergeChoice> fieldChoices = const {},
    Map<String, MergeChoice> recordChoices = const {},
  }) : _fieldChoices = Map.unmodifiable(fieldChoices),
       _recordChoices = Map.unmodifiable(recordChoices);

  final Map<KdbxFieldRef, MergeChoice> _fieldChoices;
  final Map<String, MergeChoice> _recordChoices;

  /// A conflict with no recorded answer is a programming error, not a merge
  /// outcome: every conflict carries a computed default from the moment the
  /// review is created, so an absent entry means the resolution was not built
  /// from the session's own decisions.
  MergeChoice fieldChoiceFor(KdbxFieldDiff diff) {
    final choice = _fieldChoices[kdbxFieldRefOf(diff)];
    if (choice == null) {
      throw StateError('no recorded choice for a field conflict');
    }
    return choice;
  }

  /// FR-5's default is **keep**, so an unanswered deletion conflict preserves.
  /// An unattended session can never delete.
  MergeChoice recordChoiceFor(String objectUuid) =>
      _recordChoices[objectUuid] ?? MergeChoice.keep;

  @override
  String toString() => 'KdbxMergeResolution(<redacted>)';
}

/// FR-3's Notes separator. **Not** a plain Markdown thematic break: it carries
/// `U+241E SYMBOL FOR RECORD SEPARATOR` between two rules, so ordinary user
/// text — including a `---` the user typed themselves — splits into exactly one
/// segment and can be neither interleaved nor deduplicated against itself.
const mergeNotesSeparator = '\n\n---\u241E---\n\n';

/// FR-3's `bothNotes`: an **ordered, deduplicated union of segments**, not a
/// concatenation.
///
/// A concatenation with a merely fixed operand order is deterministic and still
/// not associative, so three devices merging in different orders hold different
/// Notes, the FR-7 semantic short-circuit stops firing and the next round
/// duplicates text the user wrote. The set union sorted by one fixed comparator
/// is associative, commutative and idempotent.
String notesSegmentUnion(String local, String remote) {
  final segments = {
    ...local.split(mergeNotesSeparator),
    ...remote.split(mergeNotesSeparator),
  }.where((segment) => segment.isNotEmpty).toList()..sort(compareUtf8Bytes);
  return segments.join(mergeNotesSeparator);
}

/// FR-3's value order: unsigned lexicographic over **UTF-8** bytes, shortest is
/// smaller on a common prefix.
///
/// The encoding is UTF-8 and no other. A Dart `String`'s `codeUnits` are
/// UTF-16, which sorts an astral character's surrogate pair *below* the BMP
/// range `U+E000..FFFF` while its UTF-8 bytes and its code point sort *above*:
/// two devices disagreeing on the encoding elect opposite winners, and the
/// tie-break's whole purpose is that they do not.
///
/// T401a owns the full tie-break (timestamps first, then this). This function
/// is the value half, needed here because [notesSegmentUnion] must sort by the
/// *same* comparator — a segment order that drifted from the tie-break order
/// would make two devices agree on every field and disagree on the notes.
int compareUtf8Bytes(String a, String b) {
  final left = utf8.encode(a);
  final right = utf8.encode(b);
  final shared = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < shared; i++) {
    if (left[i] != right[i]) return left[i] - right[i];
  }
  return left.length - right.length;
}

/// One validated side: the open file plus its live-object UUID index.
///
/// Only constructible through [KdbxMergeAdapter.validatePair], so an index that
/// failed FR-2 validation cannot exist.
///
/// **The guarantee is about the index, not about the file.** [file] is a live
/// mutable `KdbxFile`, and [KdbxMergeAdapter.diffPresence] re-walks it rather
/// than reading [liveObjectKinds] back, so a caller that mutates the file
/// between the two calls gets a diff over unvalidated state. Nothing does that
/// today — the adapter is read-only and the sides are opened from bytes
/// immediately before validation — but "validated by construction" would be
/// overclaiming, so it is stated as what it is: validated at the moment
/// `validatePair` returned.
final class KdbxMergeSide {
  const KdbxMergeSide._(this.file, this.liveObjectKinds);

  final KdbxFile file;

  /// Every live group and entry UUID on this side, mapped to its object kind,
  /// as observed during validation: globally unique and non-nil at that point.
  final Map<String, KdbxMergeObjectKind> liveObjectKinds;

  @override
  String toString() => 'KdbxMergeSide(<redacted>)';
}

/// Two sides that have passed every FR-2 gate: per-side UUID integrity, root
/// UUID lineage and cross-side object-kind agreement.
final class KdbxMergePair {
  const KdbxMergePair._(this.local, this.remote);

  final KdbxMergeSide local;
  final KdbxMergeSide remote;

  @override
  String toString() => 'KdbxMergePair(<redacted>)';
}

/// Reads two KDBX sides and produces the evidence for a per-field diff.
///
/// Stateless and read-only. Every refusal is a [SyncMergeFailure] carrying a
/// [MergeFailureCode] and nothing else: no UUID, no object label, no path, no
/// value. FR-2 requires exactly that, because the alternative is a log line
/// that names the entry the user was trying to protect.
class KdbxMergeAdapter {
  const KdbxMergeAdapter();

  /// Opens one side from bytes.
  ///
  /// The caller resolves credentials and reads the bytes; the adapter touches
  /// no filesystem, so it can never be the writer that bypasses the mutex.
  ///
  /// **Failure mapping.** A header the library refuses — an out-of-range major
  /// version, an unknown cipher — becomes
  /// [MergeFailureCode.unsupportedKdbxConstruct]. Gate 0 recorded that the
  /// refusal is not one exception type: 5.x and above throw
  /// `KdbxUnsupportedException`, below 3.x the header parser fails earlier with
  /// a `RangeError`. Both are mapped, and so is any other parse failure, so an
  /// unreadable side can never be mistaken for an empty one.
  ///
  /// A wrong-credentials failure is deliberately **not** mapped and propagates
  /// unchanged: it is the calling repository's concern (T302), it is not a
  /// property of the KDBX construct, and swallowing it here would report a
  /// revoked credential as a corrupt database.
  Future<KdbxFile> openSide({
    required Uint8List bytes,
    required Credentials credentials,
  }) async {
    try {
      return await KdbxFormat().read(bytes, credentials);
    } on KdbxInvalidKeyException {
      rethrow;
    } on Object {
      throw const SyncMergeFailure(MergeFailureCode.unsupportedKdbxConstruct);
    }
  }

  /// Runs every FR-2 gate over the pair and returns the validated sides.
  ///
  /// **Nothing has happened yet when this throws.** The adapter holds no
  /// session, has opened no file handle for writing and has contacted no remote
  /// — and the repository (T302) cannot mint a session id before this method
  /// returns, because the validated [KdbxMergePair] is its only input. "Reject
  /// before session, backup, local write or upload" is therefore a property of
  /// the call graph, not of a check someone remembered to run first.
  ///
  /// Order, and why it is this order:
  ///
  /// 1. **per side** — nil UUID, duplicate entry UUID, duplicate group UUID,
  ///    group/entry collision. Uniqueness is global across groups and entries,
  ///    not per collection and not per parent;
  /// 2. **lineage** — root group UUIDs must match. A shared remote file id is
  ///    not lineage evidence (proven in Gate 0: two independently created
  ///    databases never share a root UUID);
  /// 3. **cross-side kind** — a UUID live on both sides must denote the same
  ///    kind. Only visible with both indexes in hand, which is why it is last.
  ///
  /// **What the order between 1 and 2 actually buys, stated honestly.** It is
  /// not safety: swapping them refuses the same set of pairs, because a nil
  /// root that slipped past the lineage comparison is caught by the per-side
  /// check immediately after, with the same code. An earlier revision of this
  /// comment claimed two nil roots would "pass the gate"; that was false, and a
  /// mutation swapping the blocks survived the whole suite, which is how it was
  /// caught. What the order decides is the **reported code** when a pair
  /// violates both at once: a structurally invalid side is
  /// [MergeFailureCode.unsupportedKdbxData], never
  /// [MergeFailureCode.wrongLineage]. That distinction is worth pinning —
  /// `wrongLineage` tells the user "these are different databases", which is
  /// the wrong remedy for a corrupt one — so it is pinned by a test rather than
  /// left to statement order.
  KdbxMergePair validatePair({
    required KdbxFile local,
    required KdbxFile remote,
  }) {
    final localSide = _validateSide(local);
    final remoteSide = _validateSide(remote);

    if (local.body.rootGroup.uuid != remote.body.rootGroup.uuid) {
      throw const SyncMergeFailure(MergeFailureCode.wrongLineage);
    }

    for (final entry in localSide.liveObjectKinds.entries) {
      final remoteKind = remoteSide.liveObjectKinds[entry.key];
      if (remoteKind != null && remoteKind != entry.value) {
        throw const SyncMergeFailure(MergeFailureCode.unsupportedKdbxData);
      }
    }

    return KdbxMergePair._(localSide, remoteSide);
  }

  /// FR-4/FR-5's presence diff over a validated pair.
  ///
  /// Records are matched by KDBX UUID, never by title or path (FR-3). Record
  /// evidence is re-derived per side from the tree (bin membership) and the
  /// `DeletedObjects` list (tombstones) — see [KdbxRecordEvidence] for why the
  /// UUID sets alone cannot say it. Fields are classified only for records live
  /// and un-binned on both sides; a `missing` side with no deletion evidence is
  /// an automatic union member and never a delete.
  KdbxPresenceDiff diffPresence(KdbxMergePair pair) {
    final local = _sideEvidence(pair.local);
    final remote = _sideEvidence(pair.remote);

    final recordDiffs = <KdbxRecordDiff>[];
    final fieldDiffs = <KdbxFieldDiff>[];

    // Sorted so two devices emit the same evidence in the same order; FR-3's
    // convergence argument depends on it.
    final uuids = {...local.objects.keys, ...remote.objects.keys}.toList()
      ..sort();

    for (final uuid in uuids) {
      final localObject = local.objects[uuid];
      final remoteObject = remote.objects[uuid];
      final localSide = local.sideFor(uuid);
      final remoteSide = remote.sideFor(uuid);
      final classification = _classifyRecord(localSide, remoteSide);

      recordDiffs.add(
        KdbxRecordDiff(
          objectUuid: uuid,
          objectKind: (localObject ?? remoteObject!) is KdbxGroup
              ? KdbxMergeObjectKind.group
              : KdbxMergeObjectKind.entry,
          local: localSide,
          remote: remoteSide,
          classification: classification,
        ),
      );

      if (classification != KdbxRecordClassification.sharedLive) continue;
      if (localObject is! KdbxEntry || remoteObject is! KdbxEntry) continue;
      fieldDiffs.addAll(_diffEntry(uuid, localObject, remoteObject));
    }

    return KdbxPresenceDiff(recordDiffs: recordDiffs, fieldDiffs: fieldDiffs);
  }

  /// Applies [resolution] to the **local** side of [pair] and returns it as the
  /// merge candidate.
  ///
  /// **Why the local file is the base.** FR-1 forbids rebuilding a database
  /// from a lossy projection, and the cheapest way to keep every construct the
  /// library supports — header, KDF, metadata, settings, custom icons, history,
  /// tombstones, recycle-bin settings — is to never destroy the object that
  /// already holds them. So the candidate *is* the opened local file, mutated
  /// in place. Two consequences, stated rather than discovered later:
  ///
  ///   * the pair is consumed by this call. `pair.local.file` is no longer the
  ///     local side afterwards, and the caller must not diff it again;
  ///   * nothing is written anywhere. The candidate lives in memory until
  ///     [serializeCandidate] turns it into bytes and T403 writes those bytes
  ///     under the mutex through `SafeVaultFileWriter`.
  ///
  /// What is applied, in this order and for these reasons:
  ///
  ///   1. **remote-only groups**, in pre-order so a parent exists before its
  ///      child needs it;
  ///   2. **remote-only entries**, which need their parent group to exist;
  ///   3. **fields of shared live entries** — automatic unions for the
  ///      one-sided rows, the resolved choice for the conflicts;
  ///   4. **record deletion decisions**, which move objects in and out of the
  ///      tree and must therefore run after the imports that may have created
  ///      them;
  ///   5. **tombstone union**, last, so it can see the final tree and skip any
  ///      UUID a Keep decision has just brought back to life.
  KdbxFile applyMerge({
    required KdbxMergePair pair,
    required KdbxPresenceDiff diff,
    required KdbxMergeResolution resolution,
  }) {
    final local = pair.local.file;
    final remote = pair.remote.file;

    // Captured BEFORE anything is mutated: the merge must never write a wall
    // clock into the candidate. See [_stampDeterministicTimes].
    final times = _captureTimes(local, remote);
    final keepStamps = <String, DateTime>{};

    for (final record in diff.recordDiffs) {
      if (record.classification != KdbxRecordClassification.recordRemoteOnly) {
        continue;
      }
      if (record.objectKind != KdbxMergeObjectKind.group) continue;
      _importGroup(local: local, remote: remote, groupUuid: record.objectUuid);
    }
    for (final record in diff.recordDiffs) {
      if (record.classification != KdbxRecordClassification.recordRemoteOnly) {
        continue;
      }
      if (record.objectKind != KdbxMergeObjectKind.entry) continue;
      _importEntry(local: local, remote: remote, entryUuid: record.objectUuid);
    }

    for (final field in diff.fieldDiffs) {
      _applyField(
        local: local,
        remote: remote,
        field: field,
        resolution: resolution,
      );
    }

    for (final record in diff.deletionConflicts) {
      _applyRecordDecision(
        local: local,
        remote: remote,
        record: record,
        choice: resolution.recordChoiceFor(record.objectUuid),
        keepStamps: keepStamps,
      );
    }

    _unionTombstones(local: local, remote: remote);
    _stampDeterministicTimes(local, times, keepStamps);
    return local;
  }

  /// Both sides' object times, per UUID, before the merge touches anything.
  Map<String, _ObjectTimes> _captureTimes(KdbxFile local, KdbxFile remote) {
    final captured = <String, _ObjectTimes>{};
    for (final file in [local, remote]) {
      for (final object in file.body.rootGroup.getAllGroupsAndEntries()) {
        final existing = captured[object.uuid.uuid] ?? const _ObjectTimes();
        captured[object.uuid.uuid] = existing.joinedWith(
          modifiedAt: object.times.lastModificationTime.get(),
          locationChangedAt: object.times.locationChanged.get(),
        );
      }
    }
    return captured;
  }

  /// FR-3, applied to timestamps: **every time the merge writes is a function
  /// of the two inputs, never of the local clock.**
  ///
  /// This is not tidiness. `parent.addEntry` / `addGroup` and `setString` all
  /// route through `Changeable.modify`, which stamps the object with
  /// `DateTime.now()`. So importing a one-sided record re-dated the group that
  /// received it, and taking a remote field value re-dated the entry — and two
  /// devices never merge in the same second, so their candidates differed on
  /// exactly those objects, forever. Measured as a ~27% flake in the
  /// commutativity test and reproduced deterministically by separating the two
  /// devices by three seconds.
  ///
  /// It is the same defect class FR-3 identifies for values, in the dimension
  /// nobody looks at: a merge whose output depends on *when* it ran is not
  /// commutative, so the FR-7 semantic short-circuit never fires and each
  /// device rewrites the other's result on every round.
  ///
  /// The rule is FR-3's own join: the merged object's time is the **newer of
  /// the two sides' known times**, which is exactly "the winning side's
  /// timestamp travels with the winning value" at the granularity KDBX
  /// actually stores (there is no per-field time). A one-sided object keeps
  /// the single known time, which is its source's.
  ///
  /// Two deliberate exceptions, both already deterministic:
  ///   * [keepStamps] — FR-5 Keep re-dates the record at the tombstone's clock
  ///     (T009b G2), and that must win over the join or the tombstone starts
  ///     matching again on the next peer;
  ///   * a **fresh** deletion emitted by an explicit Delete keeps the wall
  ///     clock. A Delete is a user decision taken at a real moment and is
  ///     per-device by G4, and unlike a modification time a tombstone clock is
  ///     join-convergent (FR-5 "preserve newest supported deletion data" is a
  ///     max), so two devices converge on the next round instead of rewriting
  ///     each other forever.
  void _stampDeterministicTimes(
    KdbxFile candidate,
    Map<String, _ObjectTimes> times,
    Map<String, DateTime> keepStamps,
  ) {
    for (final object in candidate.body.rootGroup.getAllGroupsAndEntries()) {
      final captured = times[object.uuid.uuid];
      if (captured == null) continue;
      final modifiedAt = keepStamps[object.uuid.uuid] ?? captured.modifiedAt;
      if (modifiedAt != null) {
        object.times.lastModificationTime.set(modifiedAt);
      }
      if (captured.locationChangedAt != null) {
        object.times.locationChanged.set(captured.locationChangedAt);
      }
    }
  }

  /// FR-1's serialization parity gate: serialize the candidate, reopen it with
  /// the **original credentials**, and refuse unless the reopened file carries
  /// the same canonical semantic manifest.
  ///
  /// The comparison is semantic and never on bytes: salts, IVs and the master
  /// seed are redrawn on every save, so two serializations of one file are
  /// never byte-equal and a byte check would refuse every candidate. A
  /// mismatch is [MergeFailureCode.serializationParityFailed] — the candidate
  /// is discarded and no target is touched.
  Future<Uint8List> serializeCandidate({
    required KdbxFile candidate,
    required Credentials credentials,
  }) async {
    final expected = kdbxSemanticManifest(candidate);
    final bytes = Uint8List.fromList(await candidate.save());

    final KdbxFile reopened;
    try {
      reopened = await KdbxFormat().read(bytes, credentials);
    } on Object {
      throw const SyncMergeFailure(MergeFailureCode.serializationParityFailed);
    }
    if (kdbxManifestDigest(kdbxSemanticManifest(reopened)) !=
        kdbxManifestDigest(expected)) {
      throw const SyncMergeFailure(MergeFailureCode.serializationParityFailed);
    }
    return bytes;
  }

  // ------------------------------------------------------------------ private

  void _importGroup({
    required KdbxFile local,
    required KdbxFile remote,
    required String groupUuid,
  }) {
    final source = _groupByUuid(remote, groupUuid);
    if (source == null) return;
    final parentUuid = source.parent?.uuid.uuid;
    // A remote-only ROOT group is impossible: lineage was verified, so the two
    // roots share a UUID and the root is never one-sided.
    final parent = parentUuid == null
        ? local.body.rootGroup
        : _groupByUuid(local, parentUuid) ?? local.body.rootGroup;

    final imported = KdbxGroup.create(
      ctx: local.ctx,
      parent: parent,
      name: source.name.get(),
    );
    parent.addGroup(imported);
    // Graft the source's own XML rather than copying a hand-written list of
    // fields: `KdbxNode.node` holds every construct the library models AND the
    // ones it does not, so a field nobody remembered is carried anyway. The
    // container elements are excluded because `toXml` regenerates them from
    // the live child lists, and `Times` because it is a separate `KdbxNode`
    // with its own element.
    _graftChildren(
      from: source,
      to: imported,
      skip: const {'Group', 'Entry', 'Times'},
    );
    _graftChildren(from: source.times, to: imported.times);
    imported.forceSetUuid(source.uuid);
    _copyCustomIcon(local: local, remote: remote, object: imported);
  }

  void _importEntry({
    required KdbxFile local,
    required KdbxFile remote,
    required String entryUuid,
  }) {
    final source = _entryByUuid(remote, entryUuid);
    if (source == null) return;
    final parentUuid = source.parent?.uuid.uuid;
    final parent = parentUuid == null
        ? local.body.rootGroup
        : _groupByUuid(local, parentUuid) ?? local.body.rootGroup;

    // `cloneInto` is the Gate 0 T003 primitive: it carries strings, binaries
    // (re-registered in the target file's binary pool), custom data, times,
    // colors, tags, override URL, icons and history.
    final imported = source.cloneInto(parent);
    // ...but not the constructs the library does not model. Gate 0 found
    // exactly one on an entry: `AutoType`. Grafting it keeps the auto-type
    // sequence and window associations of an imported record.
    _graftChildren(from: source, to: imported, only: const {'AutoType'});
    _copyCustomIcon(local: local, remote: remote, object: imported);
  }

  void _copyCustomIcon({
    required KdbxFile local,
    required KdbxFile remote,
    required KdbxObject object,
  }) {
    final iconUuid = object.customIconUuid.get();
    if (iconUuid == null) return;
    if (local.body.meta.customIcons.containsKey(iconUuid)) return;
    final icon = remote.body.meta.customIcons[iconUuid];
    if (icon != null) local.body.meta.addCustomIcon(icon);
  }

  void _applyField({
    required KdbxFile local,
    required KdbxFile remote,
    required KdbxFieldDiff field,
    required KdbxMergeResolution resolution,
  }) {
    final localEntry = _entryByUuid(local, field.entryUuid);
    final remoteEntry = _entryByUuid(remote, field.entryUuid);
    if (localEntry == null || remoteEntry == null) return;

    switch (field.classification) {
      case KdbxFieldClassification.identical:
      case KdbxFieldClassification.fieldLocalOnly:
        // Already in the candidate; FR-4 preserves it with no decision.
        return;
      case KdbxFieldClassification.fieldRemoteOnly:
        _takeRemote(localEntry, remoteEntry, field);
        return;
      case KdbxFieldClassification.fieldConflict:
        final choice = resolution.fieldChoiceFor(field);
        switch (choice) {
          case MergeChoice.local:
            return;
          case MergeChoice.remote:
            _takeRemote(localEntry, remoteEntry, field);
            return;
          case MergeChoice.bothNotes:
            localEntry.setString(
              KdbxKey(field.localKey ?? field.remoteKey!),
              PlainValue(
                notesSegmentUnion(
                  localEntry.getString(KdbxKey(field.localKey!))?.getText() ??
                      '',
                  remoteEntry.getString(KdbxKey(field.remoteKey!))?.getText() ??
                      '',
                ),
              ),
            );
            return;
          case MergeChoice.keep:
          case MergeChoice.delete:
            // Unrepresentable: `RedactedMergeDecision` refuses keep/delete on a
            // value conflict, so reaching here means the resolution was built
            // outside the domain invariants.
            throw StateError('keep/delete is not a value-conflict choice');
        }
    }
  }

  /// Copies the remote side of one field onto the candidate.
  ///
  /// The **local** key spelling wins where both sides have one, because KDBX
  /// matches keys case-insensitively and keeps the spelling already stored:
  /// writing the remote spelling would resolve onto the same key anyway. Where
  /// only the remote side has the field, its spelling is preserved verbatim
  /// (FR-1).
  void _takeRemote(
    KdbxEntry localEntry,
    KdbxEntry remoteEntry,
    KdbxFieldDiff field,
  ) {
    final targetKey = KdbxKey(field.localKey ?? field.remoteKey!);
    final sourceKey = KdbxKey(field.remoteKey!);

    switch (field.fieldKind) {
      case KdbxMergeFieldKind.string:
        localEntry.setString(targetKey, remoteEntry.getString(sourceKey));
      case KdbxMergeFieldKind.attachment:
        final binary = remoteEntry.getBinary(sourceKey);
        if (binary == null) return;
        if (localEntry.getBinary(targetKey) != null) {
          // `createBinary` uniquifies a colliding name, which would silently
          // produce `doc1.pdf` beside `doc.pdf` instead of replacing it.
          localEntry.removeBinary(targetKey);
        }
        localEntry.createBinary(
          isProtected: binary.isProtected,
          name: targetKey.key,
          bytes: binary.value,
        );
    }
  }

  /// FR-5 Keep/Delete on one record.
  void _applyRecordDecision({
    required KdbxFile local,
    required KdbxFile remote,
    required KdbxRecordDiff record,
    required MergeChoice choice,
    required Map<String, DateTime> keepStamps,
  }) {
    switch (choice) {
      case MergeChoice.keep:
        _applyKeep(
          local: local,
          remote: remote,
          record: record,
          keepStamps: keepStamps,
        );
      case MergeChoice.delete:
        _applyDelete(local: local, record: record);
      case MergeChoice.local:
      case MergeChoice.remote:
      case MergeChoice.bothNotes:
        throw StateError('a deletion conflict is answered keep/delete only');
    }
  }

  void _applyKeep({
    required KdbxFile local,
    required KdbxFile remote,
    required KdbxRecordDiff record,
    required Map<String, DateTime> keepStamps,
  }) {
    final uuid = record.objectUuid;
    var object = _objectByUuid(local, uuid);

    if (object == null) {
      // Tombstoned locally, live remotely: import it back.
      if (record.objectKind == KdbxMergeObjectKind.group) {
        _importGroup(local: local, remote: remote, groupUuid: uuid);
      } else {
        _importEntry(local: local, remote: remote, entryUuid: uuid);
      }
      object = _objectByUuid(local, uuid);
    } else if (record.local.evidence == KdbxRecordEvidence.recycled) {
      // Binned locally, live remotely: put it back where the live side has it.
      final remoteParentUuid = _objectByUuid(remote, uuid)?.parent?.uuid.uuid;
      final target = remoteParentUuid == null
          ? local.body.rootGroup
          : _groupByUuid(local, remoteParentUuid) ?? local.body.rootGroup;
      KdbxDao(local).move(object, target);
    }
    if (object == null) return;

    // FR-5: Keep "removes/neutralizes matching tombstone". T009b gap G2: simply
    // dropping the tombstone locally lets a peer that still holds it
    // re-introduce the conflict on the next sync, forever. So the live object
    // is also re-stamped at the tombstone's own clock, which under G1/G3 makes
    // the tombstone non-matching on *every* device, deterministically — while
    // the tombstone evidence stays retained wherever it exists, so the join
    // remains monotone.
    final deletedAt = record.local.deletedAtUtc ?? record.remote.deletedAtUtc;
    if (deletedAt != null) {
      keepStamps[uuid] = deletedAt;
    }
    _removeTombstone(local, uuid);
  }

  void _applyDelete({required KdbxFile local, required KdbxRecordDiff record}) {
    final object = _objectByUuid(local, record.objectUuid);
    if (object != null && object.parent != null) {
      // `deletePermanently` removes the object and emits the tombstone in one
      // step, for the object and — on a group — for everything under it.
      KdbxDao(local).deletePermanently(object);
      return;
    }
    if (!tombstonesOf(local).containsKey(record.objectUuid)) {
      _addTombstone(
        local,
        record.objectUuid,
        record.remote.deletedAtUtc ?? record.local.deletedAtUtc,
      );
    }
  }

  /// Emits a tombstone carrying [deletedAt].
  ///
  /// `KdbxReadWriteContext.addDeletedObject` declares a `now` parameter and
  /// then **drops it** (kdbx 2.5.0, `kdbx_format.dart:119`: it calls
  /// `KdbxDeletedObject.create(this, uuid)` without forwarding it), so every
  /// tombstone it emits is stamped with the current clock. That silently
  /// rewrites the deletion time of a tombstone copied from the other side,
  /// which is the one piece of data FR-5's "preserve newest supported deletion
  /// data" is about, and which T009b's G1 uses to decide whether a tombstone
  /// still matches. The clock is therefore re-applied on the object the call
  /// just appended.
  void _addTombstone(KdbxFile file, String uuid, DateTime? deletedAt) {
    file.ctx.addDeletedObject(KdbxUuid(uuid));
    if (deletedAt == null) return;
    // ignore: invalid_use_of_visible_for_testing_member
    final emitted = file.body.deletedObjects.lastWhere(
      (o) => o.uuid.uuid == uuid,
    );
    emitted.deletionTime.set(deletedAt);
  }

  /// FR-5 "preserve newest supported deletion data": every tombstone the remote
  /// holds and the candidate does not is carried over — unless the UUID is live
  /// in the candidate, which is what a Keep decision or a one-sided union just
  /// established.
  void _unionTombstones({required KdbxFile local, required KdbxFile remote}) {
    final existing = tombstonesOf(local);
    final live = {
      for (final object in local.body.rootGroup.getAllGroupsAndEntries())
        object.uuid.uuid,
    };
    tombstonesOf(remote).forEach((uuid, deletedAt) {
      if (existing.containsKey(uuid) || live.contains(uuid)) return;
      _addTombstone(local, uuid, deletedAt);
    });
  }

  void _removeTombstone(KdbxFile file, String uuid) {
    // ignore: invalid_use_of_visible_for_testing_member
    file.body.deletedObjects.removeWhere((o) => o.uuid.uuid == uuid);
  }

  /// Copies element children of [from]'s XML into [to]'s, replacing same-named
  /// ones.
  ///
  /// Takes the `KdbxNode`s rather than the `XmlElement`s so that `xml` does not
  /// become a direct dependency of this package: it is kdbx's own transitive
  /// dependency, and `KdbxNode.node` is a public, exported member, so the
  /// elements are reachable through inference without naming the type.
  void _graftChildren({
    required KdbxNode from,
    required KdbxNode to,
    Set<String> skip = const {},
    Set<String>? only,
  }) {
    for (final child in from.node.childElements.toList()) {
      final name = child.name.local;
      if (skip.contains(name)) continue;
      if (only != null && !only.contains(name)) continue;
      for (final existing in to.node.childElements.toList()) {
        if (existing.name.local == name) to.node.children.remove(existing);
      }
      to.node.children.add(child.copy());
    }
  }

  KdbxObject? _objectByUuid(KdbxFile file, String uuid) {
    for (final object in file.body.rootGroup.getAllGroupsAndEntries()) {
      if (object.uuid.uuid == uuid) return object;
    }
    return null;
  }

  KdbxGroup? _groupByUuid(KdbxFile file, String uuid) {
    final object = _objectByUuid(file, uuid);
    return object is KdbxGroup ? object : null;
  }

  KdbxEntry? _entryByUuid(KdbxFile file, String uuid) {
    final object = _objectByUuid(file, uuid);
    return object is KdbxEntry ? object : null;
  }

  /// FR-5's record table, with T009b's temporal reading of "matching".
  ///
  /// The one row that is not a direct transcription of the spec table is
  /// `live` against `tombstoned`: T009b's gaps G1/G3 resolved "matching" as
  /// **strictly newer than the live side's modification time**, so an edit at
  /// or after the deletion clock is proof of life and supersedes the tombstone,
  /// and an equal clock breaks toward preservation. An *unknown* modification
  /// time carries no such proof, so a tombstone always matches it — FR-3's
  /// "unknown never outranks evidence", applied to deletion. That model is the
  /// gate this implementation has to be coherent with, not an invention here.
  KdbxRecordClassification _classifyRecord(
    KdbxRecordSide local,
    KdbxRecordSide remote,
  ) {
    if (local.evidence == KdbxRecordEvidence.live &&
        remote.evidence == KdbxRecordEvidence.live) {
      return KdbxRecordClassification.sharedLive;
    }
    if (!local.isLiveSomewhere && !remote.isLiveSomewhere) {
      return KdbxRecordClassification.recordDeleted;
    }
    if (local.isLiveSomewhere && remote.isLiveSomewhere) {
      // At least one side has it binned (the other is live or binned too):
      // bin-vs-live is FR-5's explicit move-to-bin conflict, bin-vs-bin is
      // deleted on both.
      return local.evidence == remote.evidence
          ? KdbxRecordClassification.recordDeleted
          : KdbxRecordClassification.recordDeletionConflict;
    }

    final liveSide = local.isLiveSomewhere ? local : remote;
    final otherSide = local.isLiveSomewhere ? remote : local;
    final liveOnLocal = local.isLiveSomewhere;

    if (otherSide.evidence == KdbxRecordEvidence.tombstoned &&
        _tombstoneMatches(liveSide, otherSide)) {
      return KdbxRecordClassification.recordDeletionConflict;
    }
    // Either plain absence (FR-4: never deletion evidence) or a tombstone the
    // live side's later edit superseded. Both preserve the record.
    return liveOnLocal
        ? KdbxRecordClassification.recordLocalOnly
        : KdbxRecordClassification.recordRemoteOnly;
  }

  bool _tombstoneMatches(KdbxRecordSide live, KdbxRecordSide tomb) {
    final deletedAt = tomb.deletedAtUtc;
    if (deletedAt == null) return true;
    final modifiedAt = live.modifiedAtUtc;
    if (modifiedAt == null) return true;
    return deletedAt.isAfter(modifiedAt);
  }

  _SideEvidence _sideEvidence(KdbxMergeSide side) {
    final file = side.file;
    final binned = _recycleBinMemberUuids(file);
    final objects = <String, KdbxObject>{
      for (final object in file.body.rootGroup.getAllGroupsAndEntries())
        object.uuid.uuid: object,
    };
    return _SideEvidence(
      objects: objects,
      binnedUuids: binned,
      tombstones: tombstonesOf(file),
    );
  }

  /// Every object inside the recycle-bin subtree, the bin group itself
  /// excluded.
  ///
  /// The bin group is a container, not a deleted record: it is preserved like
  /// any other group, and only what the user put *into* it counts as a
  /// move-to-bin.
  Set<String> _recycleBinMemberUuids(KdbxFile file) {
    final bin = file.recycleBin;
    if (bin == null) return const <String>{};
    return {
      for (final object in bin.getAllGroupsAndEntries())
        if (object.uuid != bin.uuid) object.uuid.uuid,
    };
  }

  KdbxMergeSide _validateSide(KdbxFile file) {
    final kinds = <String, KdbxMergeObjectKind>{};

    for (final object in file.body.rootGroup.getAllGroupsAndEntries()) {
      final uuid = object.uuid;
      if (uuid.isNil) {
        throw const SyncMergeFailure(MergeFailureCode.unsupportedKdbxData);
      }
      final kind = object is KdbxGroup
          ? KdbxMergeObjectKind.group
          : KdbxMergeObjectKind.entry;
      // One map for both collections, so a duplicate group UUID, a duplicate
      // entry UUID and a group/entry collision are the same single check.
      // FR-2 requires global uniqueness; three separate per-collection checks
      // is how the collision case gets forgotten.
      if (kinds.containsKey(uuid.uuid)) {
        throw const SyncMergeFailure(MergeFailureCode.unsupportedKdbxData);
      }
      kinds[uuid.uuid] = kind;
    }

    return KdbxMergeSide._(file, Map.unmodifiable(kinds));
  }

  Iterable<KdbxFieldDiff> _diffEntry(
    String entryUuid,
    KdbxEntry local,
    KdbxEntry remote,
  ) sync* {
    // Keyed by the CANONICAL key, because that is what KDBX matches on. The
    // verbatim spelling travels as payload so FR-1's "original key spelling"
    // is preserved for both sides.
    yield* _classifyAll(
      entryUuid,
      KdbxMergeFieldKind.string,
      {
        for (final e in local.stringEntries)
          canonicalFieldKey(e.key.key): (
            spelling: e.key.key,
            present: KdbxFieldPresent.string(e.value),
          ),
      },
      {
        for (final e in remote.stringEntries)
          canonicalFieldKey(e.key.key): (
            spelling: e.key.key,
            present: KdbxFieldPresent.string(e.value),
          ),
      },
    );
    yield* _classifyAll(
      entryUuid,
      KdbxMergeFieldKind.attachment,
      {
        for (final e in local.binaryEntries)
          canonicalFieldKey(e.key.key): (
            spelling: e.key.key,
            present: KdbxFieldPresent.attachment(e.value),
          ),
      },
      {
        for (final e in remote.binaryEntries)
          canonicalFieldKey(e.key.key): (
            spelling: e.key.key,
            present: KdbxFieldPresent.attachment(e.value),
          ),
      },
    );
  }

  Iterable<KdbxFieldDiff> _classifyAll(
    String entryUuid,
    KdbxMergeFieldKind fieldKind,
    Map<String, ({String spelling, KdbxFieldPresent present})> local,
    Map<String, ({String spelling, KdbxFieldPresent present})> remote,
  ) sync* {
    // Sorted by canonical key so the diff is deterministic AND identical on
    // both devices; FR-3's convergence argument needs two devices to produce
    // the same evidence in the same order, and sorting by a per-side verbatim
    // spelling would not be the same order on both.
    final keys = {...local.keys, ...remote.keys}.toList()..sort();
    for (final key in keys) {
      final l = local[key]?.present;
      final r = remote[key]?.present;

      // "missing on both" cannot occur — the key set is the union — which is
      // FR-4's "emit no field" row expressed as an absence from the output.
      final KdbxFieldClassification classification;
      if (l != null && r != null) {
        classification = l.sameAs(r)
            ? KdbxFieldClassification.identical
            : KdbxFieldClassification.fieldConflict;
      } else if (l != null) {
        classification = KdbxFieldClassification.fieldLocalOnly;
      } else {
        classification = KdbxFieldClassification.fieldRemoteOnly;
      }

      yield KdbxFieldDiff(
        entryUuid: entryUuid,
        fieldKind: fieldKind,
        canonicalKey: key,
        localKey: local[key]?.spelling,
        remoteKey: remote[key]?.spelling,
        local: l ?? const KdbxFieldMissing(),
        remote: r ?? const KdbxFieldMissing(),
        classification: classification,
      );
    }
  }
}

/// The join of one object's times across the two sides.
final class _ObjectTimes {
  const _ObjectTimes({this.modifiedAt, this.locationChangedAt});

  final DateTime? modifiedAt;
  final DateTime? locationChangedAt;

  /// FR-3's order over known times: a known time beats an unknown one, and the
  /// newer known time wins. Commutative, so the two sides can be visited in
  /// either order — which is the whole point.
  _ObjectTimes joinedWith({
    DateTime? modifiedAt,
    DateTime? locationChangedAt,
  }) => _ObjectTimes(
    modifiedAt: _newer(this.modifiedAt, modifiedAt),
    locationChangedAt: _newer(this.locationChangedAt, locationChangedAt),
  );

  static DateTime? _newer(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

/// One side's raw evidence, indexed by UUID.
final class _SideEvidence {
  const _SideEvidence({
    required this.objects,
    required this.binnedUuids,
    required this.tombstones,
  });

  final Map<String, KdbxObject> objects;
  final Set<String> binnedUuids;
  final Map<String, DateTime?> tombstones;

  KdbxRecordSide sideFor(String uuid) {
    final object = objects[uuid];
    if (object != null) {
      return KdbxRecordSide(
        evidence: binnedUuids.contains(uuid)
            ? KdbxRecordEvidence.recycled
            : KdbxRecordEvidence.live,
        modifiedAtUtc: object.times.lastModificationTime.get(),
        // A tombstone can coexist with a live object of the same UUID after a
        // delete-then-restore on this side; carrying it keeps the join
        // monotone (T009b) instead of silently dropping evidence.
        deletedAtUtc: tombstones[uuid],
      );
    }
    if (tombstones.containsKey(uuid)) {
      return KdbxRecordSide(
        evidence: KdbxRecordEvidence.tombstoned,
        deletedAtUtc: tombstones[uuid],
      );
    }
    return const KdbxRecordSide.absent();
  }
}

/// The `DeletedObjects` tombstone list of [file], keyed by UUID.
///
/// `KdbxBody.deletedObjects` is the only accessor the library offers and it is
/// annotated `@visibleForTesting` — recorded in the Gate 0 report as one of the
/// primitives that sits outside the supported surface. It is exported and
/// stable; the annotation is what forces the ignore, not the API.
Map<String, DateTime?> tombstonesOf(KdbxFile file) => {
  // ignore: invalid_use_of_visible_for_testing_member
  for (final deleted in file.body.deletedObjects)
    deleted.uuid.uuid: deleted.deletionTime.get(),
};
