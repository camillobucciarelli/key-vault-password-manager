// spec-008 T301/T304/T305/T306 — the production KDBX <-> merge-model adapter.
//
// **What this file is.** The data-layer bridge that reads two `.kdbx` sides and
// produces the evidence a per-field diff is computed from. It is the promotion
// of the Gate 0 spike helpers (`_validateSide`, `_crossSideKindMismatch`,
// `_lineageMatches` in `vault_kdbx_service_test.dart`) from test-only code into
// production code, with the typed refusals the frozen domain contract defines.
//
// **What this file is NOT, and why.**
//
//   * It **never writes**. No filesystem access at all: the caller hands over
//     bytes. There is therefore no `withDatabaseLock` and no
//     `SafeVaultFileWriter` call here, and Gate 1's writer-routing guard has
//     nothing to route — the adapter is read-only by construction, which is a
//     stronger statement than "it takes the mutex". The merge commit that does
//     write (T403) is a separate, later task and routes through both.
//   * It does **not** serialize, apply decisions or import one-sided objects.
//     Those are the mutating halves of T301 and land with the tests that can
//     actually exercise them (T308 shortcut/deletion, T309 candidate reopen).
//     Shipping untested vault-mutating code is the one thing worse than
//     shipping it late.
//   * It does **not** call `KdbxFile.merge`. That method is marked unfinished
//     upstream and is forbidden by the spec; a source scan in
//     `vault_kdbx_service_test.dart` enforces it over this file too.
//
// **Secret boundary (T303 is Phase 3 slice 2, but nothing here may pre-empt
// it).** `Credentials`, `KdbxFile`, decrypted string values and attachment
// bytes are legitimate in `data/` and illegitimate anywhere else. Nothing in
// this file is reachable from `domain/` or `presentation/` — enforced by
// `sync_merge_domain_architecture_test.dart`. The diff model below deliberately
// carries an attachment's **digest and length**, never its bytes: the diff only
// needs to classify, and a model that carried plaintext would be one refactor
// away from a log line.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kdbx/kdbx.dart';

import '../../domain/models/sync_merge_models.dart';
import '../../domain/repositories/sync_merge_repository.dart';

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
  /// The null [StringValue] branch is defensive and, on kdbx 2.5.0, otherwise
  /// unreachable: `_strings` is typed `Map<KdbxKey, StringValue?>`, but the XML
  /// reader always constructs a `PlainValue` (`kdbx_entry.dart:187-197`) and
  /// `setString(key, null)` **removes** the key rather than storing a null
  /// (`kdbx_entry.dart:341-352`; `removeString` is an alias for exactly that).
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

/// The read-only evidence a diff is computed from: which records are one-sided,
/// and how every field of every shared entry classifies.
///
/// Record-level *deletion* evidence (recycle bin, `DeletedObjects`) is not
/// interpreted here — FR-5 and T308. Recycle-binned objects are live objects
/// in the KDBX tree and therefore appear in these sets like any other.
final class KdbxPresenceDiff {
  KdbxPresenceDiff({
    required Set<String> localOnlyEntryUuids,
    required Set<String> remoteOnlyEntryUuids,
    required Set<String> localOnlyGroupUuids,
    required Set<String> remoteOnlyGroupUuids,
    required List<KdbxFieldDiff> fieldDiffs,
  }) : localOnlyEntryUuids = Set.unmodifiable(localOnlyEntryUuids),
       remoteOnlyEntryUuids = Set.unmodifiable(remoteOnlyEntryUuids),
       localOnlyGroupUuids = Set.unmodifiable(localOnlyGroupUuids),
       remoteOnlyGroupUuids = Set.unmodifiable(remoteOnlyGroupUuids),
       fieldDiffs = List.unmodifiable(fieldDiffs);

  final Set<String> localOnlyEntryUuids;
  final Set<String> remoteOnlyEntryUuids;
  final Set<String> localOnlyGroupUuids;
  final Set<String> remoteOnlyGroupUuids;

  /// Only fields of entries present on **both** sides. A one-sided entry's
  /// fields are not a field-level decision: the whole record is an automatic
  /// union member.
  final List<KdbxFieldDiff> fieldDiffs;

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

  /// FR-4's presence diff over a validated pair.
  ///
  /// Records are matched by KDBX UUID, never by title or path (FR-3). Fields of
  /// an entry present on both sides are classified one by one; a `missing` side
  /// with no deletion evidence is an automatic union member and never a delete.
  KdbxPresenceDiff diffPresence(KdbxMergePair pair) {
    final localEntries = _entriesByUuid(pair.local.file);
    final remoteEntries = _entriesByUuid(pair.remote.file);
    final localGroups = _groupUuids(pair.local.file);
    final remoteGroups = _groupUuids(pair.remote.file);

    final fieldDiffs = <KdbxFieldDiff>[];
    for (final uuid in localEntries.keys) {
      final remoteEntry = remoteEntries[uuid];
      if (remoteEntry == null) continue;
      fieldDiffs.addAll(_diffEntry(uuid, localEntries[uuid]!, remoteEntry));
    }

    return KdbxPresenceDiff(
      localOnlyEntryUuids: localEntries.keys.toSet().difference(
        remoteEntries.keys.toSet(),
      ),
      remoteOnlyEntryUuids: remoteEntries.keys.toSet().difference(
        localEntries.keys.toSet(),
      ),
      localOnlyGroupUuids: localGroups.difference(remoteGroups),
      remoteOnlyGroupUuids: remoteGroups.difference(localGroups),
      fieldDiffs: fieldDiffs,
    );
  }

  // ------------------------------------------------------------------ private

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

  Map<String, KdbxEntry> _entriesByUuid(KdbxFile file) => {
    for (final entry in file.body.rootGroup.getAllEntries())
      entry.uuid.uuid: entry,
  };

  Set<String> _groupUuids(KdbxFile file) => {
    for (final group in file.body.rootGroup.getAllGroups()) group.uuid.uuid,
  };
}
