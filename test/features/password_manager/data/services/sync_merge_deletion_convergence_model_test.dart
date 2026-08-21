// T009b — deletion convergence model for spec 008 FR-4/FR-5.
//
// This is a MODEL test, not an integration test. It runs entirely in memory:
// no network, no filesystem, no KDBX, no `lib/` dependency. It exists because
// T009's grow-only union says NOTHING about removal — a grow-only set cannot
// remove an element, so a delete either fails to converge or is resurrected by
// the next peer that still holds the value (feasibility report, §"What T009
// does not cover"). T009b must pass before any deletion, tombstone,
// `fieldDeletionConflict` or attachment behaviour enters the implementation.
//
// STRUCTURE CHOSEN: a **tombstone with a clock** (the LWW-element-set family),
// NOT a 2P-Set. The spec decides this, not taste:
//
//   * FR-5 "Keep emits live record and removes/neutralizes matching tombstone"
//     — Keep is an un-delete. A 2P-Set makes removal permanent (an element once
//     removed can never re-enter), so it cannot express Keep at all.
//   * FR-5 "Tombstoned both sides: remain deleted; preserve newest supported
//     deletion data" — tombstones carry data ordered by recency, so the join of
//     two tombstones is the max of their clocks. A 2P-Set removal carries
//     nothing to order.
//   * FR-4's deletion-evidence rows require distinguishing "missing with a
//     proven deletion marker" from plain absence; the marker IS the tombstone.
//
// The model therefore represents every record/field/attachment key as a pair
// of monotone evidence components:
//
//     RecState(live: Field?, tomb: int?)
//
// and the JOIN is pointwise: the live component joins by FR-3's total order
// (T009's proven `compareFields`, imported from that model), the tombstone
// component joins by max clock, and absence is the identity of both. Each
// component is a join-semilattice, so the product is — and that is proved by
// enumeration below, not assumed. Classification (live / deleted /
// deletionConflict) and the Keep/Delete decisions are a pure VIEW over the
// joined evidence: because the evidence converges regardless of order, the
// view converges too.
//
// FR-4/FR-5 semantics modelled exactly as written:
//   * absence is never deletion evidence — a missing side is a union (FR-4);
//   * empty string / zero-byte attachment counts as present (FR-4);
//   * live + matching tombstone = deletionConflict, default preserve,
//     EXPLICIT Keep/Delete required — never resolved by policy (FR-5);
//   * Delete emits no live object and retains the tombstone (FR-5);
//   * Keep emits the live record and neutralizes the tombstone (FR-5);
//   * both sides tombstoned: remain deleted, newest deletion data (FR-5).
//
// SPEC GAPS FOUND WHILE MODELLING (documented, not invented around; each is
// resolved here with the most conservative — data-preserving — reading, and
// recorded in feasibility-report.md §"T009b"):
//
//   G1  FR-5 defines a "matching" tombstone by identity (same UUID) only. It
//       does not say whether a tombstone OLDER than a later live edit still
//       forces a deletionConflict. Model: a tombstone matches only when it is
//       strictly newer than the live side's known mtime; an edit at or after
//       the deletion clock supersedes the tombstone (proof of life after the
//       delete — the data-preserving direction, and the reading that makes G2
//       possible at all).
//   G2  FR-5 does not say how Keep's "neutralization" survives a merge against
//       a peer that still holds the tombstone; dropping the tombstone locally
//       would let the peer re-introduce it and reopen the conflict forever.
//       Model: Keep re-emits the live field carrying the tombstone's clock as
//       its mtime, so under G1 the tombstone is non-matching on EVERY device,
//       deterministically, while the tombstone evidence itself is retained
//       (the join stays monotone).
//   G3  The equal-clock case (tombstone clock == live mtime) is unspecified.
//       Model: not matching — ties break toward preservation, which is FR-4's
//       own default, and is what G2's neutralization relies on.
//   G4  FR-7's decision ledger is session-scoped, so a Keep/Delete decision
//       does NOT propagate to peers: a peer holding the conflicting state must
//       decide too (its session returns to review). The EVIDENCE converges
//       regardless; only the explicit resolution is per-device. Asserted, not
//       hidden, in the resurrection tests.

import 'package:flutter_test/flutter_test.dart';

import 'sync_merge_convergence_model_test.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// The evidence state of one record/field/attachment key.
///
/// [live] is the live value with its modification time (absent = null); it is
/// exactly T009's [Field], so the live component inherits FR-3's proven total
/// order. [tomb] is the deletion evidence: the clock of the newest known
/// deletion of this key (no evidence = null). Both components only ever grow
/// under the join, which is what makes deletion convergent instead of
/// resurrection-prone: the tombstone is never forgotten by merging.
class RecState {
  const RecState({this.live, this.tomb});

  final Field? live;
  final int? tomb;

  bool get isAbsent => live == null && tomb == null;

  @override
  bool operator ==(Object other) =>
      other is RecState && other.live == live && other.tomb == tomb;

  @override
  int get hashCode => Object.hash(live, tomb);

  @override
  String toString() => 'RecState(live: $live, tomb: $tomb)';
}

/// A deletion-aware document: key → evidence state.
typedef DelDoc = Map<String, RecState>;

/// Join of the live component. Absence is the identity — a missing side
/// contributes nothing and never deletes (FR-4: missing without explicit
/// marker is automatic union). Two present sides join by FR-3's total order,
/// the same `compareFields` T009 proved commutative and associative.
Field? joinLive(Field? a, Field? b) {
  if (a == null) return b;
  if (b == null) return a;
  return compareFields(a, b) >= 0 ? a : b;
}

/// Join of the deletion evidence. No evidence is the identity; two tombstones
/// keep the newest clock (FR-5: "preserve newest supported deletion data").
int? joinTomb(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a >= b ? a : b;
}

/// The pointwise product join — a semilattice because each component is.
RecState joinRec(RecState a, RecState b) =>
    RecState(live: joinLive(a.live, b.live), tomb: joinTomb(a.tomb, b.tomb));

/// Join of two documents: key union, pointwise [joinRec]. A key absent on both
/// sides emits nothing (FR-4: missing/missing → emit no field).
DelDoc joinDelDocs(DelDoc a, DelDoc b) {
  const absent = RecState();
  final out = <String, RecState>{};
  for (final key in {...a.keys, ...b.keys}) {
    final joined = joinRec(a[key] ?? absent, b[key] ?? absent);
    if (!joined.isAbsent) out[key] = joined;
  }
  return out;
}

/// FR-5's "matching" tombstone, made temporal (gaps G1/G3): the tombstone
/// matches — i.e. still dominates the live side — only when it is STRICTLY
/// newer than the live side's known modification time. An edit at or after
/// the deletion clock is proof of life after the delete and supersedes it
/// (the data-preserving reading). An UNKNOWN mtime carries no such proof, so
/// a tombstone always matches it: unknown never outranks evidence (FR-3's own
/// rule, applied to deletion).
bool tombMatches(RecState s) {
  final live = s.live;
  final tomb = s.tomb;
  if (live == null || tomb == null) return false;
  final mtime = live.mtime;
  if (mtime == null) return true;
  return tomb > mtime;
}

/// The visible classification — a pure function of the joined evidence, so it
/// is exactly as order-independent as the join itself.
enum RecClass { absent, live, deleted, deletionConflict }

RecClass classOf(RecState s) {
  final live = s.live;
  if (live == null) {
    return s.tomb == null ? RecClass.absent : RecClass.deleted;
  }
  return tombMatches(s) ? RecClass.deletionConflict : RecClass.live;
}

/// The two explicit decisions FR-5 requires for a `deletionConflict` /
/// `fieldDeletionConflict`. Recorded in the same session-scoped ledger shape
/// as T009's value decisions.
const String keepDecision = 'keep';
const String deleteDecision = 'delete';

/// FR-5 **Keep**: emit the live record, neutralize the matching tombstone.
/// The neutralization (gap G2) re-emits the live field carrying the
/// tombstone's clock as its mtime: under G1 the tombstone stops matching on
/// every device, deterministically, and the tombstone evidence is RETAINED so
/// the join stays monotone. Bumping to the tombstone's clock invents no new
/// time — the user made this decision in full knowledge of evidence at that
/// clock, and any peer edit older than the deletion had already lost to it.
RecState resolveKeep(RecState s) =>
    RecState(live: Field(s.live!.value, s.tomb), tomb: s.tomb);

/// FR-5 **Delete**: emit no live object, retain the valid tombstone. The
/// retained tombstone is what makes the delete convergent: a peer that still
/// holds the live value re-encounters the evidence instead of silently
/// resurrecting the record.
RecState resolveDelete(RecState s) => RecState(tomb: s.tomb);

class DelMergeResult {
  DelMergeResult.merged(this.doc)
    : pending = const <String>{},
      needsReview = false;

  DelMergeResult.review(this.pending)
    : doc = const <String, RecState>{},
      needsReview = true;

  final DelDoc doc;
  final Set<String> pending;
  final bool needsReview;
}

/// Merge two deletion-aware documents: join the evidence, then apply the
/// session ledger to every `deletionConflict`.
///
/// FR-5: a deletion is NEVER resolved by policy. An undecided
/// `deletionConflict` routes to review — on the first round too, unlike
/// T009's value conflicts, because FR-5 says "explicit Keep/Delete required"
/// where FR-3 defines an automatic policy for values.
///
/// Two stale-ledger guards, same class as T009's Case Q (fail safe, not fail
/// silent — both reopen review instead of silently picking a side):
///   * a Delete recorded against a tombstone that a NEWER edit has since
///     superseded would silently delete data the user never saw lose;
///   * a Keep recorded for a value that is no longer live anywhere would
///     silently no-op the user's explicit preservation.
DelMergeResult mergeDeletionDocs(
  DelDoc local,
  DelDoc remote, {
  Map<String, String> ledger = const <String, String>{},
}) {
  final joined = joinDelDocs(local, remote);
  final result = <String, RecState>{};
  final pending = <String>{};

  for (final entry in joined.entries) {
    final key = entry.key;
    var state = entry.value;
    final decided = ledger[key];
    final cls = classOf(state);

    if (cls == RecClass.deletionConflict) {
      if (decided == keepDecision) {
        state = resolveKeep(state);
      } else if (decided == deleteDecision) {
        state = resolveDelete(state);
      } else {
        pending.add(key);
        continue;
      }
    } else if (decided == deleteDecision &&
        cls == RecClass.live &&
        state.tomb != null) {
      // Stale Delete: the tombstone the user confirmed no longer matches — a
      // newer edit superseded it. Deleting now would discard an edit the user
      // has never seen. Reopen review.
      pending.add(key);
      continue;
    } else if (decided == keepDecision && cls == RecClass.deleted) {
      // Stale Keep: the value the user chose to keep is not live anywhere in
      // the joined evidence. Silently staying deleted would drop an explicit
      // preservation decision. Reopen review.
      pending.add(key);
      continue;
    }
    result[key] = state;
  }

  if (pending.isNotEmpty) return DelMergeResult.review(pending);
  return DelMergeResult.merged(result);
}

/// Canonical semantic manifest over the evidence, deletion included: two docs
/// with the same manifest are the same converged state. Tombstones are IN the
/// manifest — a manifest that omitted them would finalize a real divergence in
/// silence (T009's N4 invariant, extended to deletion evidence).
String delManifest(DelDoc doc) {
  final keys = doc.keys.toList()..sort();
  return keys
      .map((k) {
        final s = doc[k]!;
        final live = s.live == null
            ? '-'
            : '${s.live!.value}@${s.live!.mtime ?? 'u'}';
        return '$k=live:$live|tomb:${s.tomb ?? '-'}';
      })
      .join(';');
}

/// Nondeterministic serialization, as in T009: same logical content, fresh
/// bytes every time — what makes the manifest, not the bytes, the arbiter.
int _saltCounter = 0;
String delSerialize(DelDoc doc) => '${delManifest(doc)}#salt${_saltCounter++}';

/// A bare `get`/`put` remote for deletion-aware documents — the same measured
/// shape as T009's [Remote], duplicated here so T009's mutation anchors stay
/// untouched.
class DelRemote {
  DelRemote(DelDoc initial)
    : content = Map<String, RecState>.from(initial),
      bytes = delSerialize(initial);

  DelDoc content;
  String bytes;
  int writeCount = 0;

  void put(String newBytes, DelDoc newContent) {
    bytes = newBytes;
    content = Map<String, RecState>.from(newContent);
    writeCount++;
  }
}

/// The FR-7 write-verify-converge cycle over deletion-aware documents. Same
/// cycle as T009's [CommitSession] — read/merge/revalidate/write/verify,
/// re-anchor on divergence, semantic short-circuit, retry budget 3. The cycle
/// itself is T009's proven ground; what T009b adds is the payload.
class DelCommitSession {
  DelCommitSession({
    required this.local,
    required this.remote,
    this.ledger = const <String, String>{},
    this.budget = 3,
    this.onBeforeWrite,
    this.onAfterWrite,
  });

  final DelDoc local;
  final DelRemote remote;
  final Map<String, String> ledger;
  final int budget;
  final void Function()? onBeforeWrite;
  final void Function()? onAfterWrite;

  int roundsUsed = 0;

  Outcome run() {
    var expectedBase = remote.bytes;

    final first = mergeDeletionDocs(local, remote.content, ledger: ledger);
    if (first.needsReview) return Outcome.needsReview;
    var merged = first.doc;

    while (true) {
      if (remote.bytes != expectedBase) return Outcome.staleRemote;

      onBeforeWrite?.call();

      final myBytes = delSerialize(merged);
      remote.put(myBytes, merged);

      onAfterWrite?.call();

      final observed = remote.bytes;
      if (observed == myBytes) return Outcome.finalized;

      expectedBase = observed;
      final observedContent = Map<String, RecState>.from(remote.content);
      if (delManifest(observedContent) == delManifest(merged)) {
        return Outcome.finalized;
      }

      if (roundsUsed >= budget) return Outcome.unresolved;
      roundsUsed++;

      final again = mergeDeletionDocs(merged, observedContent, ledger: ledger);
      if (again.needsReview) return Outcome.needsReview;
      merged = again.doc;
    }
  }
}

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

void main() {
  DelDoc doc(Map<String, RecState> m) => Map<String, RecState>.from(m);
  RecState live(String v, int? mtime, {int? tomb}) =>
      RecState(live: Field(v, mtime), tomb: tomb);
  RecState tombOnly(int clock) => RecState(tomb: clock);

  List<List<T>> permutations<T>(List<T> items) {
    if (items.length <= 1) return [items];
    final out = <List<T>>[];
    for (var i = 0; i < items.length; i++) {
      final rest = [...items]..removeAt(i);
      for (final tail in permutations(rest)) {
        out.add([items[i], ...tail]);
      }
    }
    return out;
  }

  /// Every full parenthesization — all Catalan(n-1) binary-tree shapes, as in
  /// T009 after finding L1: the claim and the enumeration must be the same
  /// statement.
  List<T> allJoins<T>(List<T> items, T Function(T, T) join) {
    if (items.length == 1) return [items.first];
    final out = <T>[];
    for (var split = 1; split < items.length; split++) {
      for (final left in allJoins(items.sublist(0, split), join)) {
        for (final right in allJoins(items.sublist(split), join)) {
          out.add(join(left, right));
        }
      }
    }
    return out;
  }

  /// Every ordering × every full parenthesization of [docs] under the
  /// evidence join, as manifests.
  Set<String> allAssociations(List<DelDoc> docs) {
    final results = <String>{};
    for (final order in permutations(docs)) {
      for (final joined in allJoins(order, joinDelDocs)) {
        results.add(delManifest(joined));
      }
    }
    return results;
  }

  group('T009b — the evidence join is a semilattice over add AND remove', () {
    // The four device states deliberately mix every evidence shape: live-only,
    // tombstone-only, live+tombstone (a conflict carried IN the evidence),
    // unknown mtime, zero-byte value, and keys absent on some sides. Both
    // operations — add (a live field appearing) and remove (a tombstone
    // appearing) — are in the set, which is exactly what T009's grow-only
    // union could not express.
    final deviceA = {'x': live('vx', 5), 'empty': live('', null)};
    final deviceB = {'x': tombOnly(8)};
    final deviceC = {'x': live('vz', 9), 'y': tombOnly(3)};
    final deviceD = {'x': live('vx', 5, tomb: 2), 'y': live('vy', 4)};

    test('associative at three and four devices, over every ordering and '
        'every full parenthesization', () {
      final three = allAssociations([doc(deviceA), doc(deviceB), doc(deviceC)]);
      expect(three, hasLength(1), reason: 'observed distinct results: $three');

      final four = allAssociations([
        doc(deviceA),
        doc(deviceB),
        doc(deviceC),
        doc(deviceD),
      ]);
      expect(four, hasLength(1), reason: 'observed distinct results: $four');

      // The converged state really contains both operations' evidence: the
      // newest live candidate AND the newest tombstone, per key.
      final joined = [
        doc(deviceA),
        doc(deviceB),
        doc(deviceC),
        doc(deviceD),
      ].reduce(joinDelDocs);
      expect(joined['x']!.live!.value, 'vz');
      expect(joined['x']!.tomb, 8);
      expect(joined['y']!.tomb, 3);
      expect(joined['empty']!.live!.value, '');
    });

    test('commutative and idempotent', () {
      final docs = [doc(deviceA), doc(deviceB), doc(deviceC), doc(deviceD)];
      for (final a in docs) {
        for (final b in docs) {
          expect(
            delManifest(joinDelDocs(a, b)),
            delManifest(joinDelDocs(b, a)),
          );
        }
        expect(delManifest(joinDelDocs(a, a)), delManifest(a));
      }
      final joined = docs.reduce(joinDelDocs);
      for (final a in docs) {
        expect(delManifest(joinDelDocs(joined, a)), delManifest(joined));
      }
      expect(delManifest(joinDelDocs(joined, joined)), delManifest(joined));
    });

    test('tombstoned on both sides stays deleted and preserves the newest '
        'deletion data, from either perspective', () {
      // FR-5: "Tombstoned both sides: remain deleted; preserve newest
      // supported deletion data." The clock is the data; the join must carry
      // the newest one whichever side it came from — an oldest-clock join, or
      // a first-operand join, discards deletion data one perspective and is
      // perspective-dependent the other.
      final a = doc({'x': tombOnly(50)});
      final b = doc({'x': tombOnly(70)});

      final fromA = joinDelDocs(a, b);
      final fromB = joinDelDocs(b, a);
      expect(classOf(fromA['x']!), RecClass.deleted);
      expect(fromA['x']!.tomb, 70, reason: 'the newest deletion data travels');
      expect(delManifest(fromA), delManifest(fromB));
    });

    test('a repeated delete is idempotent', () {
      final d = doc({'x': tombOnly(50)});
      expect(delManifest(joinDelDocs(d, d)), delManifest(d));
      // And at the system level: re-syncing the same deletion changes nothing.
      final remote = DelRemote(doc({'x': tombOnly(50)}));
      final before = delManifest(remote.content);
      expect(
        DelCommitSession(local: doc({'x': tombOnly(50)}), remote: remote).run(),
        Outcome.finalized,
      );
      expect(delManifest(remote.content), before);
    });
  });

  group('T009b — classification implements the FR-4 rows and FR-5 rules', () {
    test('absence without deletion evidence is a union, never a deletion', () {
      // FR-4: fieldLocalOnly / fieldRemoteOnly — and FR-5 rule 1 for records:
      // "Live one side + absent other without matching tombstone: preserve
      // live record." Both mirrored perspectives.
      final present = doc({'x': live('v', 5)});
      final absent = doc(<String, RecState>{});

      for (final pair in [
        [present, absent],
        [absent, present],
      ]) {
        final merged = mergeDeletionDocs(pair[0], pair[1]);
        expect(merged.needsReview, isFalse);
        expect(classOf(merged.doc['x']!), RecClass.live);
        expect(merged.doc['x']!.live!.value, 'v');
      }
    });

    test(
      'a proven deletion marker against a present side is a '
      'deletionConflict with default preserve — never an automatic delete',
      () {
        // FR-4's two deletion-evidence rows (`fieldDeletionConflict`) and FR-5
        // rule 2, which share one algebra here: present one side, tombstone
        // strictly newer than the live mtime on the other. The classification
        // is a conflict; the undecided merge routes to review (explicit
        // keep/delete required) and the EVIDENCE keeps both the live value and
        // the tombstone — default preserve, nothing silently deleted.
        final liveSide = doc({'x': live('v', 5)});
        final tombSide = doc({'x': tombOnly(50)});

        for (final pair in [
          [liveSide, tombSide],
          [tombSide, liveSide],
        ]) {
          final joined = joinDelDocs(pair[0], pair[1]);
          expect(classOf(joined['x']!), RecClass.deletionConflict);
          expect(joined['x']!.live!.value, 'v', reason: 'default preserve');
          expect(joined['x']!.tomb, 50);

          final undecided = mergeDeletionDocs(pair[0], pair[1]);
          expect(
            undecided.needsReview,
            isTrue,
            reason: 'FR-5: explicit Keep/Delete required, never policy',
          );
          expect(undecided.pending, {'x'});
        }
      },
    );

    test(
      'an empty value and a zero-byte attachment are present, not absent',
      () {
        // FR-4: "Empty string/zero-byte attachment counts as present." Presence
        // is independent from value: an empty live field without a marker is an
        // ordinary union member, and WITH a newer marker it is a full
        // deletionConflict — not a silent delete of "nothing".
        final emptySide = doc({'att': live('', 5)});
        expect(classOf(emptySide['att']!), RecClass.live);

        final merged = mergeDeletionDocs(emptySide, doc(<String, RecState>{}));
        expect(merged.doc['att'], isNotNull);
        expect(classOf(merged.doc['att']!), RecClass.live);

        final withMarker = joinDelDocs(emptySide, doc({'att': tombOnly(50)}));
        expect(classOf(withMarker['att']!), RecClass.deletionConflict);
      },
    );

    test('an unknown modification time cannot supersede a tombstone', () {
      // FR-3's "unknown carries no evidence", applied to deletion (gap G1):
      // superseding a tombstone requires PROOF of an edit after the delete,
      // and an unknown mtime proves nothing. Treating it as newer would
      // silently resurrect on the weakest possible evidence.
      final s = joinRec(RecState(live: const Field('v', null)), tombOnly(50));
      expect(classOf(s), RecClass.deletionConflict);
      expect(
        mergeDeletionDocs(
          doc({'x': live('v', null)}),
          doc({'x': tombOnly(50)}),
        ).needsReview,
        isTrue,
      );
    });

    test('delete versus concurrent edit: a strictly newer edit supersedes the '
        'tombstone; a newer tombstone reopens the conflict — same verdict '
        'from both perspectives', () {
      // Gap G1's rule, asserted in both directions. FR-5 defines "matching"
      // by identity only; the temporal reading here is the data-preserving
      // one: an edit after the delete is proof of life.
      final editNewer = joinRec(
        RecState(live: const Field('v', 70)),
        tombOnly(50),
      );
      expect(classOf(editNewer), RecClass.live);
      expect(editNewer.tomb, 50, reason: 'superseded, but never forgotten');

      final tombNewer = joinRec(
        RecState(live: const Field('v', 50)),
        tombOnly(70),
      );
      expect(classOf(tombNewer), RecClass.deletionConflict);

      // G3: the equal-clock tie breaks toward preservation.
      final tie = joinRec(RecState(live: const Field('v', 50)), tombOnly(50));
      expect(classOf(tie), RecClass.live);

      // Mirrored perspectives agree — the classification reads the joined
      // evidence, which the semilattice tests prove order-independent.
      expect(
        delManifest(
          joinDelDocs(doc({'x': live('v', 70)}), doc({'x': tombOnly(50)})),
        ),
        delManifest(
          joinDelDocs(doc({'x': tombOnly(50)}), doc({'x': live('v', 70)})),
        ),
      );
    });
  });

  group('T009b — Keep and Delete decisions converge (FR-5)', () {
    test('an explicit Delete stays deleted when an offline peer re-imports '
        'the value — the tombstone is retained and the record is never '
        'silently resurrected', () {
      // FR-5: "Delete emits no live/recycle-bin object and retains valid
      // tombstone." The retained tombstone is the whole convergence argument:
      // without it the peer that still holds the live value re-adds it and
      // the delete is silently undone.
      final deleted = mergeDeletionDocs(
        doc({'x': live('v', 10, tomb: 50)}),
        doc({'x': tombOnly(50)}),
        ledger: const {'x': deleteDecision},
      );
      expect(deleted.needsReview, isFalse);
      expect(classOf(deleted.doc['x']!), RecClass.deleted);
      expect(deleted.doc['x']!.tomb, 50, reason: 'FR-5: tombstone retained');

      // The offline peer still holds the live value. Undecided, its merge is
      // a deletionConflict routed to review — NOT a silent resurrection (and
      // not a silent delete either).
      final peerUndecided = mergeDeletionDocs(
        doc({'x': live('v', 10)}),
        deleted.doc,
      );
      expect(
        peerUndecided.needsReview,
        isTrue,
        reason: 'gap G4: each device decides',
      );

      // Once the peer decides Delete too, the record stays deleted.
      final peerDecided = mergeDeletionDocs(
        doc({'x': live('v', 10)}),
        deleted.doc,
        ledger: const {'x': deleteDecision},
      );
      expect(peerDecided.needsReview, isFalse);
      expect(classOf(peerDecided.doc['x']!), RecClass.deleted);
    });

    test('an explicit Keep neutralizes the tombstone convergently — a peer '
        'still holding the tombstone does not reopen the conflict, across '
        'repeated sessions', () {
      // FR-5: "Keep emits live record and removes/neutralizes matching
      // tombstone." Gap G2: the neutralization must DOMINATE on every device,
      // or the peer's retained tombstone reopens the conflict forever.
      final remote = DelRemote(doc({'x': live('v', 10, tomb: 50)}));

      // Device A decides Keep and commits.
      expect(
        DelCommitSession(
          local: doc({'x': live('v', 10)}),
          remote: remote,
          ledger: const {'x': keepDecision},
        ).run(),
        Outcome.finalized,
      );
      expect(classOf(remote.content['x']!), RecClass.live);
      final settled = delManifest(remote.content);

      // Device B still holds the tombstone (and the stale live value) and has
      // NO ledger entry: the neutralized state must not re-conflict for it.
      final deviceB = doc({'x': live('v', 10, tomb: 50)});
      for (var round = 0; round < 3; round++) {
        expect(
          DelCommitSession(local: deviceB, remote: remote).run(),
          Outcome.finalized,
          reason: 'a neutralized tombstone must not reopen review',
        );
        expect(delManifest(remote.content), settled, reason: 'no oscillation');
      }
      expect(remote.content['x']!.live!.value, 'v');
      expect(
        remote.content['x']!.tomb,
        50,
        reason: 'neutralized, not erased: the join stays monotone',
      );
    });

    test('Keep re-emits the live field AT the tombstone clock — never a '
        'newer, invented time', () {
      // Gap G2's own claim, pinned (tester finding F1): "bumping to the
      // tombstone's clock invents no new time". A Keep that stamped tomb+1
      // would fabricate evidence newer than the deletion itself, and the
      // fabricated mtime would beat a GENUINE peer edit made at that very
      // clock — user data lost to a timestamp nobody set.
      final kept = mergeDeletionDocs(
        doc({'x': live('v', 10)}),
        doc({'x': tombOnly(50)}),
        ledger: const {'x': keepDecision},
      );
      expect(kept.needsReview, isFalse);
      expect(
        kept.doc['x']!.live!.mtime,
        50,
        reason: 'exactly the tombstone clock: no invented time',
      );
      expect(kept.doc['x']!.tomb, 50);

      // The outcome the exact clock decides: a genuine peer edit at clock+1
      // is strictly newer than the kept field and must win the next LWW
      // round. A fabricated mtime of tomb+1 would tie it and fall through to
      // the value order, where 'v' beats 'a' — the peer's real edit silently
      // discarded.
      final afterPeer = mergeDeletionDocs(kept.doc, doc({'x': live('a', 51)}));
      expect(afterPeer.needsReview, isFalse);
      expect(
        afterPeer.doc['x']!.live!.value,
        'a',
        reason: 'the genuine edit at clock 51 beats the kept field at 50',
      );
    });

    test('a stale decision reopens review instead of silently applying', () {
      // Same class as T009's Case Q: a decision that no longer names the
      // state on the table is not a decision. Both stale shapes:
      //
      // 1. Delete recorded, but a NEWER edit superseded the tombstone —
      //    silently deleting would discard an edit the user never saw lose.
      final staleDelete = mergeDeletionDocs(
        doc({'x': live('v2', 70)}),
        doc({'x': tombOnly(50)}),
        ledger: const {'x': deleteDecision},
      );
      expect(staleDelete.needsReview, isTrue);
      expect(staleDelete.pending, {'x'});

      // Premise guard: without the ledger entry the same state is simply
      // live — the review is caused by the stale decision, nothing else.
      final undecided = mergeDeletionDocs(
        doc({'x': live('v2', 70)}),
        doc({'x': tombOnly(50)}),
      );
      expect(undecided.needsReview, isFalse);
      expect(classOf(undecided.doc['x']!), RecClass.live);

      // 2. Keep recorded, but the value is no longer live anywhere — silently
      //    staying deleted would drop an explicit preservation decision.
      final staleKeep = mergeDeletionDocs(
        doc({'x': tombOnly(50)}),
        doc(<String, RecState>{}),
        ledger: const {'x': keepDecision},
      );
      expect(staleKeep.needsReview, isTrue);
      expect(staleKeep.pending, {'x'});
    });

    test('an undecided deletion conflict blocks the commit in review — it is '
        'never auto-resolved by the cycle', () {
      final remote = DelRemote(doc({'x': tombOnly(50)}));
      final session = DelCommitSession(
        local: doc({'x': live('v', 10)}),
        remote: remote,
      );
      expect(session.run(), Outcome.needsReview);
      expect(
        remote.writeCount,
        0,
        reason: 'nothing is written while the conflict is undecided',
      );
    });
  });

  group('T009b — multi-device sessions over a bare get/put remote', () {
    test('resurrection at the system level: the deleted record stays deleted '
        'across a late rejoin and repeated re-syncs', () {
      // A deletes and commits; B was offline and still holds the live value.
      final remote = DelRemote(doc({'x': live('v', 10), 'keep': live('k', 1)}));
      expect(
        DelCommitSession(
          local: doc({'x': live('v', 10, tomb: 50), 'keep': live('k', 1)}),
          remote: remote,
          ledger: const {'x': deleteDecision},
        ).run(),
        Outcome.finalized,
      );
      expect(classOf(remote.content['x']!), RecClass.deleted);

      // B rejoins late, undecided: review, and the remote does not move.
      final bLocal = doc({'x': live('v', 10), 'keep': live('k', 1)});
      final before = delManifest(remote.content);
      expect(
        DelCommitSession(local: bLocal, remote: remote).run(),
        Outcome.needsReview,
      );
      expect(delManifest(remote.content), before, reason: 'no resurrection');

      // B decides Delete: converges, stays deleted, and re-syncing twice more
      // is a no-op — system-level idempotence over the remove operation.
      for (var pass = 0; pass < 3; pass++) {
        expect(
          DelCommitSession(
            local: bLocal,
            remote: remote,
            ledger: const {'x': deleteDecision},
          ).run(),
          Outcome.finalized,
        );
        expect(classOf(remote.content['x']!), RecClass.deleted);
        expect(remote.content['x']!.tomb, 50);
        expect(remote.content['keep']!.live!.value, 'k');
      }
    });

    test('three devices converge to the same state in any sync order, with a '
        'deletion in flight', () {
      // Device A deleted record x (and has decided so); device B still holds
      // the stale live x (and has also decided Delete — gap G4: the ledger is
      // per-device); device C contributes an unrelated addition. Every one of
      // the six sequential sync orders must converge to the same manifest:
      // x deleted with the newest tombstone, y live — add and remove
      // converging together.
      final devices = <String, ({DelDoc local, Map<String, String> ledger})>{
        'A': (local: {'x': tombOnly(50)}, ledger: const {'x': deleteDecision}),
        'B': (local: {'x': live('v', 10)}, ledger: const {'x': deleteDecision}),
        'C': (local: {'y': live('w', 7)}, ledger: const <String, String>{}),
      };

      String syncInOrder(List<String> order) {
        final remote = DelRemote(doc(<String, RecState>{}));
        for (final name in order) {
          final d = devices[name]!;
          expect(
            DelCommitSession(
              local: doc(d.local),
              remote: remote,
              ledger: d.ledger,
            ).run(),
            Outcome.finalized,
            reason: '$order/$name',
          );
        }
        return delManifest(remote.content);
      }

      final baseline = syncInOrder(['A', 'B', 'C']);
      for (final order in [
        ['A', 'C', 'B'],
        ['B', 'A', 'C'],
        ['B', 'C', 'A'],
        ['C', 'A', 'B'],
        ['C', 'B', 'A'],
      ]) {
        expect(
          syncInOrder(order),
          baseline,
          reason: 'sync order $order must not change the converged state',
        );
      }

      // And the converged state is the right one, not merely a shared one.
      final remote = DelRemote(doc(<String, RecState>{}));
      for (final name in ['A', 'B', 'C']) {
        final d = devices[name]!;
        DelCommitSession(
          local: doc(d.local),
          remote: remote,
          ledger: d.ledger,
        ).run();
      }
      expect(classOf(remote.content['x']!), RecClass.deleted);
      expect(remote.content['x']!.tomb, 50);
      expect(classOf(remote.content['y']!), RecClass.live);
    });

    test('a tombstone-only divergence is a REAL divergence: the semantic '
        'short-circuit must not finalize away the newest deletion data', () {
      // N4, extended to the deletion channel (tester finding F2): the
      // manifest is the arbiter of the semantic short-circuit, so deletion
      // evidence omitted from the manifest is deletion evidence a divergence
      // round silently never writes. Here the peer overwrites the remote
      // with the SAME live value but WITHOUT our tombstone: the two states
      // are manifest-different only in `tomb`, and the cycle must treat that
      // as a divergence to re-write, not a semantic equality to finalize.
      final remote = DelRemote(doc({'x': live('v', 60)}));
      var injected = false;

      final session = DelCommitSession(
        local: doc({'x': live('v', 60, tomb: 50)}),
        remote: remote,
        onAfterWrite: () {
          if (injected) return;
          injected = true;
          final x = doc({'x': live('v', 60)});
          remote.put(delSerialize(x), x);
        },
      );

      expect(session.run(), Outcome.finalized);
      expect(
        session.roundsUsed,
        1,
        reason:
            'the short-circuit must NOT fire on a tombstone-only difference',
      );
      expect(
        remote.content['x']!.tomb,
        50,
        reason: 'the deletion evidence is re-written, not finalized away',
      );

      // The premise, held directly: two states differing only in their
      // deletion evidence are manifest-different.
      expect(
        delManifest(doc({'x': live('v', 60)})),
        isNot(delManifest(doc({'x': live('v', 60, tomb: 50)}))),
      );
    });

    test('a tombstone landing between our write and the verification survives '
        'the divergence round', () {
      // The T009 injection point, with a deletion as the payload: the peer's
      // remove and our add must BOTH be in the converged state.
      final remote = DelRemote(doc({'shared': live('s', 1)}));
      var injected = false;

      final session = DelCommitSession(
        local: doc({'shared': live('s', 1), 'mine': live('m', 2)}),
        remote: remote,
        onAfterWrite: () {
          if (injected) return;
          injected = true;
          final x = doc({'shared': live('s', 1), 'gone': tombOnly(50)});
          remote.put(delSerialize(x), x);
        },
      );

      expect(session.run(), Outcome.finalized);
      expect(session.roundsUsed, lessThanOrEqualTo(3));
      expect(classOf(remote.content['mine']!), RecClass.live);
      expect(
        classOf(remote.content['gone']!),
        RecClass.deleted,
        reason: 'the deletion evidence survives the divergence round',
      );
      expect(remote.content['gone']!.tomb, 50);
    });
  });
}
