// T009 — Gate 0 convergence model validation for spec 008 FR-7.
//
// This is a MODEL test, not an integration test. It runs entirely in memory:
// no network, no filesystem, no KDBX, no `lib/` dependency. It exists because
// three defects that each prevented the FR-7 write-verify-converge cycle from
// converging (no re-anchoring of the expected base, no semantic arbiter, a
// perspective-dependent tie-break) were found by reading prose, and a property
// that only prose asserts is a property nothing enforces.
//
// The model below is deliberately the smallest thing that can express the
// cycle's failure modes: a document is a map of field keys to (value, mtime),
// serialization is nondeterministic (a fresh salt every time, standing in for
// KDBX salts and IVs), and the remote is a single mutable slot with no
// compare-and-swap — the measured shape of Google Drive.
//
// Properties asserted, per `feasibility-report.md` §"T009":
//   1. bounded convergence to a stable state          (guards C1, C7)
//   2. no record or one-sided field lost, any order   (founding invariant)
//   3. no oscillation on a timestamp tie              (guards C4, C4b)
//   4. semantically complete union terminates         (guards C2)
//   5. explicit user decisions survive a re-merge     (guards C3)
//   6. non-executable verification is ambiguous       (guards C5)
//   7. the merge is a join-semilattice: associative,
//      commutative and idempotent, at 3 and 4 devices (guards N1, N3)

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// One field of an entry: a value plus its KDBX modification time.
///
/// [mtime] has whole-second granularity on purpose — that is what makes a tie
/// an ordinary event rather than an exotic one, and a tie is what defect C4
/// turned into an infinite oscillation.
///
/// [mtime] is nullable because FR-3 names an **unknown** timestamp explicitly.
/// A model that cannot express one cannot assert anything about it (defect N3).
class Field {
  const Field(this.value, this.mtime);

  final String value;
  final int? mtime;

  @override
  bool operator ==(Object other) =>
      other is Field && other.value == value && other.mtime == mtime;

  @override
  int get hashCode => Object.hash(value, mtime);

  @override
  String toString() => '$value@$mtime';
}

/// A document is a map of field key to [Field]. A missing key is *absent*, and
/// absence is never deletion evidence (spec 008 FR-4).
typedef Doc = Map<String, Field>;

/// FR-3's globally deterministic total order.
///
/// Unsigned lexicographic comparison of the candidate values **as UTF-8 bytes**,
/// shortest-is-smaller on a common prefix. The winner is the **greater** byte
/// sequence. The direction is arbitrary by design; what matters is that it is
/// total and computed from the data alone, so two devices comparing the same
/// unordered pair select the same winner and the merge function is commutative.
///
/// The encoding is **not** an implementation detail, and `String.codeUnits` —
/// which this used to compare — is the wrong one. `codeUnits` are UTF-16 units,
/// and UTF-16 order is not UTF-8 order: UTF-16 encodes an astral character as a
/// surrogate pair in `U+D800..DFFF`, which sorts *below* the BMP range
/// `U+E000..FFFF`, whereas the same character's UTF-8 bytes — and its code
/// point — sort *above* it. The two orders therefore elect different winners on
/// a real pair of values, so a model built on `codeUnits` would prove its
/// properties about a total order the spec does not prescribe, and the
/// commutativity T009 demonstrates would not be the commutativity of the
/// implemented rule. That is the "the model validates itself instead of the
/// specification" failure, in the one place the spec is most explicit.
///
/// UTF-8 is also what makes the order agree with the code-point order, since
/// UTF-8 is order-preserving over code points. Both facts are asserted in
/// "the tie-break orders by UTF-8 bytes, not by UTF-16 code units".
int compareValues(String a, String b) {
  final ua = utf8.encode(a);
  final ub = utf8.encode(b);
  for (var i = 0; i < ua.length && i < ub.length; i++) {
    if (ua[i] != ub[i]) return ua[i] < ub[i] ? -1 : 1;
  }
  return ua.length.compareTo(ub.length);
}

/// FR-3's total order over a field, `(mtime, value)` with unknown lowest.
///
/// An unknown modification time carries no evidence, so it sorts **below** every
/// known one; two unknowns fall through to the value order. Treating "unknown"
/// as a bare tie — the previous rule — made the order partial: with mixed
/// known/unknown mtimes `(A|B)|C` and `A|(B|C)` selected different winners, so
/// the merge stopped being associative (defect N3).
///
/// Returns > 0 when [a] wins, < 0 when [b] wins, 0 when the two are identical.
int compareFields(Field a, Field b) {
  final am = a.mtime;
  final bm = b.mtime;
  if (am != bm) {
    if (am == null) return -1;
    if (bm == null) return 1;
    return am.compareTo(bm);
  }
  return compareValues(a.value, b.value);
}

/// The winning field's own timestamp is the one that travels with it; the
/// notes union has no single winner, so it takes the greatest known mtime and
/// stays unknown only when every contributing side was unknown.
int? maxMtime(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a >= b ? a : b;
}

/// FR-3's notes separator. Segments are delimited by it on both input and
/// output, so the operation is closed over its own output.
///
/// It is a **sentinel**, not ordinary Markdown. The union property does not
/// depend on which separator is chosen, so restricting it to a sequence a human
/// would not type is free — and the plain `\n\n---\n\n` was not free. A user
/// whose own notes contain a Markdown thematic break had two distinct damages
/// inflicted on an already-conflicted field:
///
///   1. **insertion** — the other device's text was sorted *between* the user's
///      own paragraphs, not appended after them;
///   2. **silent deletion** — the set union deduplicates segments the user
///      legitimately repeated, so `TODO / rotate key / TODO` came back as two
///      segments. That is not a reordering; it is loss of written text.
///
/// `U+241E SYMBOL FOR RECORD SEPARATOR` (`␞`) is the discriminator: it is a
/// printable glyph, so the fused field still reads as a rule rather than
/// running two notes together invisibly, and it is on no keyboard layout and
/// carries no meaning in prose, so it does not occur in a notes field by
/// accident. The `---` on either side keeps it legible to a human reading the
/// merged result.
///
/// Both damages are eliminated for ordinary user text, because ordinary text
/// splits into exactly one segment: the field is an atom, it cannot be split
/// open and interleaved, and no segment of it can be deduplicated against
/// another. Asserted below in "the sentinel separator leaves ordinary user
/// text intact".
const String notesSeparator = '\n\n---\u241E---\n\n';

/// FR-3's notes merge: an **ordered, deduplicated union of segments**.
///
/// Fixing the operand order of a binary concatenation (defect C4b) is enough for
/// two devices and not enough for three: concatenation is not associative, so
/// `(A‖B)‖C` and `A‖(B‖C)` produce different notes, different manifests, and the
/// C2 short-circuit stops firing — after which the next merge concatenates the
/// concatenations and duplicates text the user wrote (defect N1).
///
/// A sorted deduplicated union is associative, commutative and idempotent, which
/// is exactly the join-semilattice property the cycle needs. Empty segments are
/// dropped: they carry no user text and would otherwise leave a leading
/// separator when one side's notes are empty.
String mergeNotes(String a, String b) {
  final segments = <String>{
    ...a.split(notesSeparator),
    ...b.split(notesSeparator),
  }..removeWhere((s) => s.isEmpty);
  final ordered = segments.toList()..sort(compareValues);
  return ordered.join(notesSeparator);
}

/// The canonical semantic manifest: everything that is semantically meaningful,
/// and nothing that legitimately differs between two serializations of the same
/// logical database. In the real adapter this excludes KDF salt, master seed,
/// IV, ciphertext and `HeaderHash`; here it excludes the salt.
String manifest(Doc doc) {
  final keys = doc.keys.toList()..sort();
  return keys
      .map((k) => '$k=${doc[k]!.value}@${doc[k]!.mtime ?? 'unknown'}')
      .join(';');
}

/// Serialization is nondeterministic, exactly as KDBX serialization is: the
/// same logical content produces different bytes every time. This single fact
/// is what makes a byte comparison insufficient as an arbiter (defect C2).
int _saltCounter = 0;
String serialize(Doc doc) => '${manifest(doc)}#salt${_saltCounter++}';

/// The outcome of one commit session.
enum Outcome {
  /// Step 5 proved the remote holds our merged state.
  finalized,

  /// Step 3 found the remote no longer at the expected base; nothing written.
  staleRemote,

  /// A re-merge produced a conflict the user has never seen. The commit ends
  /// and the session returns to review (FR-7 sticky-decision rule).
  needsReview,

  /// The step-5 read-back could not be executed at all. Neither equal nor
  /// different; enters the FR-10 triage (defect C5).
  ambiguous,

  /// The retry budget was spent. The merged local file and the dated backup
  /// survive; the mapping is never marked synced.
  unresolved,
}

class MergeResult {
  MergeResult.merged(this.doc)
    : newConflicts = const <String>{},
      needsReview = false;

  MergeResult.review(this.newConflicts)
    : doc = const <String, Field>{},
      needsReview = true;

  final Doc doc;
  final Set<String> newConflicts;
  final bool needsReview;
}

/// Merge two sides of a document.
///
/// [ledger] holds the user's explicit decisions, keyed by field key, and is
/// re-applied on every round: an explicit decision beats LWW, beats the
/// tie-break and beats the shortcuts (defect C3).
///
/// When [reportNewConflicts] is true — every round after the first — a
/// differing field with no ledger entry is a conflict the user has never seen,
/// and it is NOT resolved automatically.
MergeResult mergeDocs(
  Doc local,
  Doc remote, {
  Map<String, String> ledger = const <String, String>{},
  bool reportNewConflicts = false,
  Set<String> notesKeys = const <String>{},
}) {
  final result = <String, Field>{};
  final unseen = <String>{};

  for (final key in {...local.keys, ...remote.keys}) {
    final l = local[key];
    final r = remote[key];

    // One-sided data is an automatic union member and is never a conflict.
    if (l == null) {
      result[key] = r!;
      continue;
    }
    if (r == null) {
      result[key] = l;
      continue;
    }
    if (l.value == r.value) {
      result[key] = compareFields(l, r) >= 0 ? l : r;
      continue;
    }

    // An explicit user decision is sticky and is replayed before any policy.
    //
    // FR-7 invariant: a live decision names one of the two values now on the
    // table. `l.value == decided ? l : r` is only a decision replay while that
    // holds; if `decided` matches neither operand it silently degenerates into
    // "take the second operand", which is order-dependent — defect C4's class,
    // relocated into the ledger branch — and discards the sticky decision
    // without reopening review. Today FR-4 (the decision is always one of the
    // two values presented) and the session lifetime of the ledger make it
    // unreachable; neither is enforced by anything but this check.
    final decided = ledger[key];
    if (decided != null) {
      if (decided != l.value && decided != r.value) {
        // Fail safe, not fail silent: the decision does not apply to this pair,
        // so this is a conflict the user has not decided. Route it to review
        // rather than picking an operand. Throwing would abort a sync over a
        // stale ledger entry and lose the merge; reopening review is the path
        // FR-7 already defines for an undecided conflict and it keeps both
        // candidates alive.
        unseen.add(key);
        continue;
      }
      result[key] = l.value == decided ? l : r;
      continue;
    }

    if (reportNewConflicts) {
      unseen.add(key);
      continue;
    }

    if (notesKeys.contains(key)) {
      // Ordered, deduplicated union of segments — associative, so a third
      // device merging in a different order reaches the same value.
      result[key] = Field(
        mergeNotes(l.value, r.value),
        maxMtime(l.mtime, r.mtime),
      );
      continue;
    }

    // Last-writer-wins on the KDBX modification time and, where that is a tie
    // or unknown, the globally deterministic total order over the values.
    // Never "local": `compareFields` reads the data alone.
    result[key] = compareFields(l, r) >= 0 ? l : r;
  }

  if (unseen.isNotEmpty) return MergeResult.review(unseen);
  return MergeResult.merged(result);
}

/// A bare `get`/`put` remote: one mutable slot, no compare-and-swap. This is
/// the measured shape of Google Drive (feasibility report, §"B1 live-network
/// re-spike").
class Remote {
  Remote(Doc initial)
    : content = Map<String, Field>.from(initial),
      bytes = serialize(initial);

  Doc content;
  String bytes;

  /// When true the step-5 read-back cannot be executed — a timeout or a
  /// disconnect. Not an error branch of the comparison: a third outcome.
  bool readBackFails = false;

  int writeCount = 0;

  void put(String newBytes, Doc newContent) {
    bytes = newBytes;
    content = Map<String, Field>.from(newContent);
    writeCount++;
  }

  /// Returns null when the read-back cannot be performed at all.
  String? getChecksum() => readBackFails ? null : bytes;
}

/// The FR-7 write-verify-converge cycle. Storage-agnostic: `get` + `put` only.
///
/// [budget] is the FR-7 retry budget of 3 divergence rounds per commit session.
/// [onBeforeWrite] fires inside the race window the cycle deliberately narrows
/// but cannot close on a non-CAS backend: after the step-3 revalidation and
/// before the step-4 write. [onAfterWrite] fires between the write and the
/// verification.
class CommitSession {
  CommitSession({
    required this.local,
    required this.remote,
    this.ledger = const <String, String>{},
    this.notesKeys = const <String>{},
    this.budget = 3,
    this.onBeforeWrite,
    this.onAfterWrite,
  });

  final Doc local;
  final Remote remote;
  final Map<String, String> ledger;
  final Set<String> notesKeys;
  final int budget;
  final void Function()? onBeforeWrite;
  final void Function()? onAfterWrite;

  /// Divergence rounds actually consumed. Rounds that terminate early — a
  /// semantic short-circuit, a return to review — are not charged to the budget.
  int roundsUsed = 0;

  /// The retained local merged state. By the founding invariant it is never
  /// discarded before a read-back proves the remote contains it.
  Doc? retainedMerged;

  Outcome run() {
    // Step 1 — read the remote and record its checksum as the expected base.
    var expectedBase = remote.bytes;

    // Step 2 — merge locally against that base.
    final first = mergeDocs(
      local,
      remote.content,
      ledger: ledger,
      notesKeys: notesKeys,
    );
    if (first.needsReview) return Outcome.needsReview;
    var merged = first.doc;
    retainedMerged = merged;

    while (true) {
      // Step 3 — revalidate under the mutex, immediately before writing.
      // The comparison is against the CURRENT expected base, which the
      // divergence branch re-anchors. Comparing against the step-1 base here is
      // exactly defect C1: every retry would abort on its first comparison.
      if (remote.bytes != expectedBase) return Outcome.staleRemote;

      // The race the cycle narrows but cannot close without conditionalWrite.
      onBeforeWrite?.call();

      // Step 4 — write the merged bytes.
      final myBytes = serialize(merged);
      remote.put(myBytes, merged);

      onAfterWrite?.call();

      // Step 5 — verify by read-back. Three outcomes, not two.
      final observed = remote.getChecksum();
      if (observed == null) return Outcome.ambiguous;
      if (observed == myBytes) return Outcome.finalized;

      // --- divergence branch ---

      // 1. Re-anchor the expected base to what we just observed.
      expectedBase = observed;
      final observedContent = Map<String, Field>.from(remote.content);

      // 2. Short-circuit on semantic equivalence. The byte comparison above is
      //    the detector; the manifest is the arbiter. Without this, two devices
      //    whose union is already complete re-write each other until the budget
      //    is gone, over a conflict that does not exist.
      if (manifest(observedContent) == manifest(merged)) {
        return Outcome.finalized;
      }

      if (roundsUsed >= budget) return Outcome.unresolved;
      roundsUsed++;

      // 3. Re-merge, preserving the user's explicit decisions. A conflict the
      //    user has never been shown reopens review rather than resolving by
      //    policy inside a flow the user believes they already confirmed.
      final again = mergeDocs(
        merged,
        observedContent,
        ledger: ledger,
        reportNewConflicts: true,
        notesKeys: notesKeys,
      );
      if (again.needsReview) return Outcome.needsReview;
      merged = again.doc;
      retainedMerged = merged;
    }
  }
}

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

void main() {
  Doc doc(Map<String, Field> m) => Map<String, Field>.from(m);

  group('T009 property 1 — bounded convergence (guards C1, C7)', () {
    test('a writer landing after our write converges in one round', () {
      // B lands between A's step-4 write and A's step-5 verification. A detects
      // it, re-anchors, re-merges and converges without either side losing data.
      final remote = Remote(doc({'a': const Field('r0', 10)}));
      var injected = false;

      final session = CommitSession(
        local: doc({
          'a': const Field('r0', 10),
          'localOnly': const Field('L', 11),
        }),
        remote: remote,
        onAfterWrite: () {
          if (injected) return;
          injected = true;
          final x = doc({
            'a': const Field('r0', 10),
            'remoteOnly': const Field('X', 12),
          });
          remote.put(serialize(x), x);
        },
      );

      expect(session.run(), Outcome.finalized);
      expect(session.roundsUsed, lessThanOrEqualTo(3));
      // Neither side's one-sided field was dropped on the way.
      expect(remote.content.containsKey('localOnly'), isTrue);
      expect(remote.content.containsKey('remoteOnly'), isTrue);
    });

    test('a writer landing inside the race window IS clobbered, and converges '
        'only when that device resynchronizes', () {
      // This is the honest shape of the guarantee on a bare `get`/`put`
      // backend, and the test asserts the limitation rather than wishing it
      // away. B writes between A's step-3 revalidation and A's step-4 write, so
      // A overwrites B and A's own step 5 legitimately confirms A's bytes. B's
      // contribution is NOT on the remote at that instant.
      final remote = Remote(doc({'a': const Field('r0', 10)}));
      final bLocal = doc({
        'a': const Field('r0', 10),
        'fromB': const Field('X', 12),
      });
      var injected = false;

      final a = CommitSession(
        local: doc({'a': const Field('r0', 10), 'fromA': const Field('L', 11)}),
        remote: remote,
        onBeforeWrite: () {
          if (injected) return;
          injected = true;
          remote.put(serialize(bLocal), bLocal);
        },
      );

      expect(a.run(), Outcome.finalized);
      expect(remote.content.containsKey('fromA'), isTrue);
      expect(
        remote.content.containsKey('fromB'),
        isFalse,
        reason:
            'the lost update is real on a backend without '
            'conditionalWrite; FR-7 makes it detected, not prevented',
      );

      // The recovery is delegated to B, which by the founding invariant still
      // holds its merged state locally and re-proposes it on its next sync.
      // This is the resynchronization condition declared in "Out of scope /
      // residual limits": if B never returns, `fromB` is gone permanently.
      final b = CommitSession(local: bLocal, remote: remote);
      expect(b.run(), Outcome.finalized);
      expect(remote.content.containsKey('fromA'), isTrue);
      expect(remote.content.containsKey('fromB'), isTrue);
    });

    test('re-anchoring is what makes the retry possible at all', () {
      // Regression guard for C1 stated as an observable: after a divergence
      // round the session must NOT report staleRemote. It reported exactly that
      // on every retry while the base stayed pinned to the step-1 read.
      final remote = Remote(doc({'a': const Field('r0', 10)}));
      var injected = false;

      final session = CommitSession(
        local: doc({'a': const Field('r0', 10), 'l': const Field('L', 11)}),
        remote: remote,
        onAfterWrite: () {
          if (injected) return;
          injected = true;
          final x = doc({
            'a': const Field('r0', 10),
            'x': const Field('X', 12),
          });
          remote.put(serialize(x), x);
        },
      );

      final outcome = session.run();
      expect(outcome, isNot(Outcome.staleRemote));
      expect(outcome, Outcome.finalized);
    });

    test(
      'a continuously writing peer exhausts the budget and ends unresolved',
      () {
        final remote = Remote(doc({'a': const Field('r0', 10)}));
        var n = 0;

        final session = CommitSession(
          local: doc({'a': const Field('r0', 10), 'l': const Field('L', 11)}),
          remote: remote,
          onAfterWrite: () {
            // A peer that never stops writing genuinely new content.
            final x = doc({
              'a': const Field('r0', 10),
              'peer$n': Field('P$n', 20 + n),
            });
            n++;
            remote.put(serialize(x), x);
          },
        );

        expect(session.run(), Outcome.unresolved);
        expect(session.roundsUsed, 3, reason: 'FR-7 retry budget is 3');
        // The invariant: the merged state is retained, never discarded.
        expect(session.retainedMerged, isNotNull);
        expect(session.retainedMerged!.containsKey('l'), isTrue);
      },
    );
  });

  group('T009 property 2 — nothing is lost, under any interleaving', () {
    test('every injection point converges to the full union once both devices '
        'have synced', () {
      // Both injection points are enumerated: inside the race window (where the
      // peer is clobbered and recovers on its next sync) and after the write
      // (where the peer is detected immediately). In both cases, once every
      // device has synchronized, no one-sided field is missing.
      for (final injectBeforeWrite in [true, false]) {
        final why = 'injectBeforeWrite=$injectBeforeWrite';
        final remote = Remote(doc({'shared': const Field('s', 5)}));
        final peerLocal = doc({
          'shared': const Field('s', 5),
          'fromPeer': const Field('P', 7),
        });
        var injected = false;

        void inject() {
          if (injected) return;
          injected = true;
          remote.put(serialize(peerLocal), peerLocal);
        }

        final mine = CommitSession(
          local: doc({
            'shared': const Field('s', 5),
            'fromMe': const Field('M', 6),
          }),
          remote: remote,
          onBeforeWrite: injectBeforeWrite ? inject : null,
          onAfterWrite: injectBeforeWrite ? null : inject,
        );

        expect(mine.run(), Outcome.finalized, reason: why);

        // The peer resynchronizes. When it was detected at step 5 this is a
        // no-op that finalizes on the semantic short-circuit; when it was
        // clobbered this is the recovery.
        final peer = CommitSession(local: peerLocal, remote: remote);
        expect(peer.run(), Outcome.finalized, reason: why);

        expect(remote.content.keys.toSet(), {
          'shared',
          'fromMe',
          'fromPeer',
        }, reason: why);
      }
    });

    test('the sentinel separator leaves ordinary user text intact', () {
      // The two damages the plain Markdown separator `\n\n---\n\n` inflicted on
      // a user who wrote a thematic break in their own notes. Both are asserted
      // as *absent*, and each is paired with a demonstration that it was real
      // under the old separator — otherwise these assertions are vacuous.
      const oldSeparator = '\n\n---\n\n';
      String mergeWith(String sep, String a, String b) {
        final segments = <String>{...a.split(sep), ...b.split(sep)}
          ..removeWhere((s) => s.isEmpty);
        return (segments.toList()..sort(compareValues)).join(sep);
      }

      // Damage 1 — insertion. The peer's text was sorted BETWEEN the user's own
      // paragraphs, not appended after them.
      const mine =
          'Zeta account recovery codes${oldSeparator}Alpha backup email';
      const theirs = 'Mike says rotate this quarterly';
      expect(
        mergeWith(oldSeparator, mine, theirs),
        isNot(contains(mine)),
        reason: 'premise: the old separator really did split and interleave',
      );
      expect(
        mergeNotes(mine, theirs),
        contains(mine),
        reason: "the user's own paragraphs stay contiguous and in their order",
      );
      expect(mergeNotes(mine, theirs), contains(theirs));

      // Damage 2 — silent deletion. A legitimately repeated paragraph was
      // deduplicated away by the set union: three segments in, two out.
      const repeated = 'TODO${oldSeparator}rotate key${oldSeparator}TODO';
      expect(
        mergeWith(oldSeparator, repeated, 'zzz').split(oldSeparator),
        hasLength(3),
        reason:
            'premise: TODO/rotate key/TODO + zzz is 4 segments and the old '
            'separator returned 3 — one of the two TODOs was lost',
      );
      expect(
        mergeNotes(repeated, 'zzz'),
        contains(repeated),
        reason: 'no segment of the user text is deduplicated against another',
      );

      // Ordinary paragraphs separated by a blank line were never affected, and
      // still are not: they are not a separator on either scheme.
      const paragraphs = 'para one\n\npara two';
      expect(mergeNotes(paragraphs, 'other'), contains(paragraphs));

      // What makes it work: ordinary text is a single indivisible segment.
      expect(mine.split(notesSeparator), hasLength(1));
      expect(repeated.split(notesSeparator), hasLength(1));

      // The residual cost, stated rather than hidden: a user who types U+241E
      // between two rules is still split. Nothing eliminates that; the sentinel
      // makes it a case that does not arise by writing Markdown.
      expect('a${notesSeparator}b'.split(notesSeparator), hasLength(2));
    });

    test('the sentinel does not weaken the union property', () {
      // The separator is free: associativity, commutativity and idempotence are
      // properties of the set union, not of the delimiter. Re-asserted here so
      // that changing the sentinel again cannot quietly break the semilattice.
      expect(
        mergeNotes(mergeNotes('zeta', 'alpha'), 'mike'),
        mergeNotes('zeta', mergeNotes('alpha', 'mike')),
      );
      expect(mergeNotes('alpha', 'zeta'), mergeNotes('zeta', 'alpha'));
      final once = mergeNotes('alpha', 'zeta');
      expect(mergeNotes(once, once), once);
      expect(once.split(notesSeparator), ['alpha', 'zeta']);
    });

    test('a one-sided field is never selected away by a conflict elsewhere', () {
      final remote = Remote(
        doc({
          'title': const Field('remoteTitle', 20),
          'remoteOnly': const Field('R', 1),
        }),
      );

      final session = CommitSession(
        local: doc({
          'title': const Field('localTitle', 10),
          'localOnly': const Field('L', 1),
        }),
        remote: remote,
      );

      expect(session.run(), Outcome.finalized);
      expect(remote.content['localOnly']?.value, 'L');
      expect(remote.content['remoteOnly']?.value, 'R');
      // The real conflict resolves by LWW; the one-sided fields are untouched.
      expect(remote.content['title']?.value, 'remoteTitle');
    });

    test('three devices reach the same remote state in any merge order', () {
      // The scenario that exposed N1. Every enumeration in this suite used to
      // stop at two devices, and a binary concatenation is deterministic at two
      // and non-associative at three: two devices that merged the same three
      // notes in a different order held different values, so the C2 manifest
      // short-circuit stopped firing and the next merge concatenated the
      // concatenations, duplicating text the user wrote.
      Doc device(String note) =>
          doc({'Notes': Field(note, 100), 'shared': const Field('s', 5)});
      final devices = {
        'zeta': device('zeta'),
        'alpha': device('alpha'),
        'mike': device('mike'),
      };

      String syncInOrder(List<String> order) {
        final remote = Remote(doc({'shared': const Field('s', 5)}));
        for (final name in order) {
          final session = CommitSession(
            local: devices[name]!,
            remote: remote,
            notesKeys: const {'Notes'},
          );
          expect(session.run(), Outcome.finalized, reason: '$order/$name');
        }
        return manifest(remote.content);
      }

      final baseline = syncInOrder(['zeta', 'alpha', 'mike']);
      for (final order in [
        ['zeta', 'mike', 'alpha'],
        ['alpha', 'zeta', 'mike'],
        ['alpha', 'mike', 'zeta'],
        ['mike', 'zeta', 'alpha'],
        ['mike', 'alpha', 'zeta'],
      ]) {
        expect(
          syncInOrder(order),
          baseline,
          reason: 'merge order $order must not change the converged state',
        );
      }

      // Every device's text survives, exactly once each.
      final notes = baseline;
      for (final segment in ['zeta', 'alpha', 'mike']) {
        expect(
          notesSeparator.allMatches(notes).length + 1,
          3,
          reason: 'three segments, no duplication',
        );
        expect(notes, contains(segment));
      }
    });

    test('a device rejoining late contributes without duplicating anything', () {
      // C syncs only after A and B have converged, then everyone re-syncs. The
      // late arrival must add its segment and nothing else, and the second pass
      // over already-merged content must be a no-op.
      final remote = Remote(doc({'shared': const Field('s', 5)}));
      Doc device(String note) =>
          doc({'Notes': Field(note, 100), 'shared': const Field('s', 5)});
      final a = device('alpha');
      final b = device('bravo');
      final c = device('charlie');

      for (final d in [a, b]) {
        expect(
          CommitSession(
            local: d,
            remote: remote,
            notesKeys: const {'Notes'},
          ).run(),
          Outcome.finalized,
        );
      }
      final beforeLateJoin = manifest(remote.content);

      expect(
        CommitSession(
          local: c,
          remote: remote,
          notesKeys: const {'Notes'},
        ).run(),
        Outcome.finalized,
      );
      final afterLateJoin = manifest(remote.content);
      expect(afterLateJoin, isNot(beforeLateJoin));
      expect(remote.content['Notes']!.value.split(notesSeparator), [
        'alpha',
        'bravo',
        'charlie',
      ]);

      // Everyone re-syncs, twice. Idempotence at the system level: no round
      // may add, drop or reorder a segment.
      for (var pass = 0; pass < 2; pass++) {
        for (final d in [a, b, c]) {
          expect(
            CommitSession(
              local: d,
              remote: remote,
              notesKeys: const {'Notes'},
            ).run(),
            Outcome.finalized,
          );
          expect(manifest(remote.content), afterLateJoin);
        }
      }
    });
  });

  group('T009 property 3 — no oscillation on a tie (guards C4, C4b)', () {
    test('mirrored perspectives choose the same winner', () {
      // The same unordered pair of candidates, seen from both devices. If the
      // default were "local", these two would disagree and flip the field back
      // and forth across sync sessions, where a per-session budget cannot help.
      const a = Field('alpha', 100);
      const b = Field('beta', 100);

      final fromA = mergeDocs(doc({'f': a}), doc({'f': b}));
      final fromB = mergeDocs(doc({'f': b}), doc({'f': a}));

      expect(fromA.doc['f'], fromB.doc['f']);
      expect(manifest(fromA.doc), manifest(fromB.doc));
    });

    test('the tie-break is a strict total order over the candidate values', () {
      expect(compareValues('a', 'b'), lessThan(0));
      expect(compareValues('b', 'a'), greaterThan(0));
      expect(compareValues('ab', 'abc'), lessThan(0));
      expect(compareValues('x', 'x'), 0);
    });

    test('the tie-break orders by UTF-8 bytes, not by UTF-16 code units', () {
      // FR-3 prescribes a comparison of **byte** sequences, and `spec.md` now
      // names the encoding: UTF-8. Dart's `String.codeUnits` are UTF-16 units,
      // and the two orders are genuinely different relations — not two spellings
      // of one. This test exists so that restoring `codeUnits` fails loudly
      // instead of quietly re-proving the properties about the wrong order.
      //
      // The discriminating pair:
      //   * `astral`  U+1F600 GRINNING FACE — UTF-8 `F0 9F 98 80`,
      //               UTF-16 surrogate pair `D83D DE00`;
      //   * `bmpHigh` U+FFFD REPLACEMENT CHARACTER — UTF-8 `EF BF BD`,
      //               UTF-16 `FFFD`.
      //
      // First unit: UTF-16 has `D83D < FFFD`, UTF-8 has `F0 > EF`. The orders
      // are opposite, so "the greater sequence wins" elects a different winner
      // on the same unordered pair. An emoji in a notes or title field against
      // any character in `U+E000..FFFF` — private use area, specials,
      // presentation forms — reaches this.
      const astral = '\u{1F600}';
      const bmpHigh = '\uFFFD';

      int byCodeUnits(String a, String b) {
        final ua = a.codeUnits;
        final ub = b.codeUnits;
        for (var i = 0; i < ua.length && i < ub.length; i++) {
          if (ua[i] != ub[i]) return ua[i] < ub[i] ? -1 : 1;
        }
        return ua.length.compareTo(ub.length);
      }

      // Premise: the pair really does discriminate. Without this the assertions
      // below would hold under either implementation and guard nothing.
      expect(
        byCodeUnits(astral, bmpHigh),
        lessThan(0),
        reason: 'premise: UTF-16 sorts the surrogate D83D below FFFD',
      );
      expect(
        compareValues(astral, bmpHigh),
        greaterThan(0),
        reason: 'UTF-8 sorts F0 above EF — the opposite verdict',
      );

      // Stated as the outcome that matters: who wins the tie-break.
      String winner(int Function(String, String) cmp) =>
          cmp(astral, bmpHigh) >= 0 ? astral : bmpHigh;
      expect(winner(byCodeUnits), bmpHigh);
      expect(winner(compareValues), astral);
      expect(winner(byCodeUnits), isNot(winner(compareValues)));

      // And the winner the model actually elects on a timestamp tie is the
      // UTF-8 one, so the divergence is not confined to the pure comparator.
      final l = doc({'f': const Field(astral, 100)});
      final r = doc({'f': const Field(bmpHigh, 100)});
      expect(mergeDocs(l, r).doc['f']!.value, astral);
      expect(mergeDocs(r, l).doc['f']!.value, astral);

      // The notes union sorts its segments with the same comparator, so it
      // inherits the same order rather than defining a second one.
      expect(
        mergeNotes(astral, bmpHigh).split(notesSeparator),
        [bmpHigh, astral],
        reason: 'ascending UTF-8 byte order: EF BF BD before F0 9F 98 80',
      );

      // UTF-8 is order-preserving over code points, so the byte order and the
      // code-point order are the same relation. UTF-16 is not.
      int byCodePoint(String a, String b) {
        final ra = a.runes.toList();
        final rb = b.runes.toList();
        for (var i = 0; i < ra.length && i < rb.length; i++) {
          if (ra[i] != rb[i]) return ra[i] < rb[i] ? -1 : 1;
        }
        return ra.length.compareTo(rb.length);
      }

      for (final pair in [
        [astral, bmpHigh],
        [bmpHigh, astral],
        ['\uE000', astral],
        ['a', astral],
        ['\u00E9', '\u0100'],
        ['\u07FF', '\u0800'],
      ]) {
        expect(
          compareValues(pair[0], pair[1]).sign,
          byCodePoint(pair[0], pair[1]).sign,
          reason: 'UTF-8 byte order must equal code-point order for $pair',
        );
      }
    });

    test('the deterministic notes merge is perspective-independent', () {
      const l = Field('note-local', 42);
      const r = Field('note-remote', 42);

      final fromA = mergeDocs(
        doc({'Notes': l}),
        doc({'Notes': r}),
        notesKeys: const {'Notes'},
      );
      final fromB = mergeDocs(
        doc({'Notes': r}),
        doc({'Notes': l}),
        notesKeys: const {'Notes'},
      );

      expect(fromA.doc['Notes']!.value, fromB.doc['Notes']!.value);
      expect(fromA.doc['Notes']!.value, contains('note-local'));
      expect(fromA.doc['Notes']!.value, contains('note-remote'));
    });

    test('two devices tied on a field converge instead of ping-ponging', () {
      // A commits, then B commits against A's result. With a perspective-
      // dependent tie-break B would flip the field back and A would flip it
      // again on its next sync, indefinitely.
      final remote = Remote(doc({'f': const Field('alpha', 100)}));

      final a = CommitSession(
        local: doc({'f': const Field('alpha', 100)}),
        remote: remote,
      );
      expect(a.run(), Outcome.finalized);
      final afterA = manifest(remote.content);

      final b = CommitSession(
        local: doc({'f': const Field('beta', 100)}),
        remote: remote,
      );
      expect(b.run(), Outcome.finalized);
      final afterB = manifest(remote.content);

      // B's commit settles on a winner; A re-syncing must not move it back.
      final aAgain = CommitSession(
        local: Map<String, Field>.from(remote.content),
        remote: remote,
      );
      expect(aAgain.run(), Outcome.finalized);
      expect(manifest(remote.content), afterB);
      expect(
        afterA,
        isNot(afterB),
        reason:
            'the scenario must really have moved the field once, '
            'otherwise the stability assertion is vacuous',
      );
    });

    test('two devices that each keep their own value stop the remote moving '
        'across sessions', () {
      // The system-level guard for C4. The test above passes even under a
      // `prefer local` tie-break, because the re-syncing device adopts the
      // remote content wholesale and so has nothing to flip back. The failure
      // mode C4 actually prevents is cross-session oscillation between two
      // devices that each RETAIN their own candidate, which is the ordinary
      // case: two phones, each holding its own edit at the same second.
      final remote = Remote(doc({'f': const Field('alpha', 100)}));
      final deviceA = doc({'f': const Field('alpha', 100)});
      final deviceB = doc({'f': const Field('beta', 100)});

      final observed = <String>[];
      for (var round = 0; round < 6; round++) {
        final local = round.isEven ? deviceA : deviceB;
        expect(
          CommitSession(local: local, remote: remote).run(),
          Outcome.finalized,
        );
        observed.add(manifest(remote.content));
      }

      // Under a perspective-dependent tie-break this list alternates forever:
      // A writes `alpha`, B writes `beta`, and no per-session retry budget can
      // see it, because each session finalizes happily on its own terms.
      expect(
        observed.skip(1).toSet(),
        hasLength(1),
        reason:
            'the remote must settle on one winner and stay there; '
            'observed sequence: $observed',
      );
      expect(
        observed.first,
        isNot(observed[1]),
        reason:
            'B must really have moved the field once, otherwise the '
            'stability assertion is vacuous',
      );
      // And it settled on the value the total order selects, not on whichever
      // device happened to write last.
      expect(remote.content['f']!.value, 'beta');
    });
  });

  group('T009 property 4 — a complete union terminates (guards C2)', () {
    test('semantically equal but byte-different content finalizes at once', () {
      final content = doc({'a': const Field('same', 1)});
      final remote = Remote(content);
      var injected = false;

      // The peer writes semantically identical content with a fresh salt, so
      // the bytes differ and the byte comparison correctly reports a
      // difference. Only the manifest can tell there is nothing to merge.
      final session = CommitSession(
        local: content,
        remote: remote,
        onAfterWrite: () {
          if (injected) return;
          injected = true;
          remote.put(serialize(content), content);
        },
      );

      expect(session.run(), Outcome.finalized);
      expect(
        session.roundsUsed,
        0,
        reason: 'a non-divergence must not consume the retry budget',
      );
      expect(
        remote.writeCount,
        2,
        reason: 'exactly our write plus the peer write; no re-write loop',
      );
    });

    test('a peer that keeps rewriting the same content still finalizes', () {
      // The system-level guard for C2. The test above dies under the mutation
      // only on its `roundsUsed == 0` assertion: with a single peer write the
      // session finalizes either way, and only the budget accounting changes.
      // Here the peer re-serializes the same semantic content after every one
      // of our writes — the steady state of two devices already in agreement.
      // Without the manifest arbiter the session burns all 3 rounds on a
      // conflict that does not exist and ends `unresolved`, so the OUTCOME,
      // not just a counter, depends on the short-circuit.
      final content = doc({'a': const Field('same', 1)});
      final remote = Remote(content);

      final session = CommitSession(
        local: content,
        remote: remote,
        onAfterWrite: () => remote.put(serialize(content), content),
      );

      expect(
        session.run(),
        Outcome.finalized,
        reason:
            'a semantically complete union must terminate, not exhaust '
            'the retry budget',
      );
      expect(session.roundsUsed, 0);
      expect(
        remote.writeCount,
        2,
        reason: 'our single write plus the peer write; no re-write loop',
      );
    });

    test('byte comparison alone would report divergence here', () {
      // Guards the premise of the test above: this is not a vacuous assertion.
      final content = doc({'a': const Field('same', 1)});
      expect(serialize(content), isNot(serialize(content)));
      expect(manifest(content), manifest(content));
    });
  });

  group('T009 property 5 — user decisions are sticky (guards C3)', () {
    test('an explicit decision is not reversed by LWW on a re-merge', () {
      // The user chose the local value; the peer's value is strictly newer, so
      // an unguarded LWW re-merge would silently overturn the choice.
      final remote = Remote(doc({'pwd': const Field('old', 1)}));
      var injected = false;

      final session = CommitSession(
        local: doc({'pwd': const Field('chosen', 5)}),
        remote: remote,
        ledger: const {'pwd': 'chosen'},
        onAfterWrite: () {
          if (injected) return;
          injected = true;
          final x = doc({
            'pwd': const Field('peerNewer', 999),
            'extra': const Field('E', 3),
          });
          remote.put(serialize(x), x);
        },
      );

      expect(session.run(), Outcome.finalized);
      expect(
        remote.content['pwd']?.value,
        'chosen',
        reason: 'the explicit decision must survive the re-merge',
      );
      expect(remote.content['extra']?.value, 'E');
    });

    test('a decision survives two consecutive divergence rounds', () {
      // One round proves the ledger is replayed once. The failure mode is a
      // ledger that is consulted on the first re-merge and then dropped, which
      // a single-round test cannot see.
      final remote = Remote(doc({'pwd': const Field('old', 1)}));
      var n = 0;

      final session = CommitSession(
        local: doc({'pwd': const Field('chosen', 5)}),
        remote: remote,
        ledger: const {'pwd': 'chosen'},
        onAfterWrite: () {
          if (n >= 2) return;
          final x = doc({
            'pwd': Field('peerNewer$n', 900 + n),
            'peer$n': Field('P$n', 10 + n),
          });
          n++;
          remote.put(serialize(x), x);
        },
      );

      expect(session.run(), Outcome.finalized);
      expect(session.roundsUsed, 2);
      expect(remote.content['pwd']?.value, 'chosen');
      expect(remote.content.keys, containsAll(['peer0', 'peer1']));
    });

    test('a ledger decision naming neither candidate reopens review instead of '
        'silently taking an operand', () {
      // Case Q. Today unreachable: FR-4 guarantees the recorded decision is one
      // of the two values presented, and the ledger does not outlive the
      // session. Nothing asserted either constraint, and the degenerate branch
      // — `l.value == decided ? l : r` with `decided` on neither side — is
      // "return the second operand", i.e. order-dependent, i.e. defect C4's
      // class inside the ledger branch, with the decision dropped in silence.
      //
      // This matters because it fails as SILENT DATA LOSS, not as an error, so
      // if the ledger ever becomes cross-session (spec 011) it opens with no
      // symptom. The invariant is asserted here so a future violation fails.
      final l = doc({'pwd': const Field('local', 5)});
      final r = doc({'pwd': const Field('remote', 5)});
      const stale = {'pwd': 'neitherOfThem'};

      final fromL = mergeDocs(l, r, ledger: stale);
      final fromR = mergeDocs(r, l, ledger: stale);

      expect(
        fromL.needsReview,
        isTrue,
        reason: 'a decision that does not apply is not a decision',
      );
      expect(fromL.newConflicts, {'pwd'});
      expect(
        fromR.needsReview,
        isTrue,
        reason: 'and the classification does not depend on operand order',
      );
      expect(fromR.newConflicts, fromL.newConflicts);

      // The premise: under the degenerate branch these two orders disagree,
      // which is exactly the commutativity violation the review measured.
      Field degenerate(Doc a, Doc b) =>
          a['pwd']!.value == stale['pwd'] ? a['pwd']! : b['pwd']!;
      expect(
        degenerate(l, r),
        isNot(degenerate(r, l)),
        reason: 'premise: silently applying the stale entry is order-dependent',
      );

      // A live decision — one that does name a candidate — still applies, so
      // the guard has not swallowed the sticky-decision rule itself.
      final live = mergeDocs(l, r, ledger: const {'pwd': 'remote'});
      expect(live.needsReview, isFalse);
      expect(live.doc['pwd']!.value, 'remote');
      expect(
        mergeDocs(r, l, ledger: const {'pwd': 'remote'}).doc['pwd']!.value,
        'remote',
      );
    });

    test('a conflict never shown to the user reopens review', () {
      final remote = Remote(doc({'a': const Field('base', 1)}));
      var injected = false;

      final session = CommitSession(
        local: doc({'a': const Field('base', 1), 'mine': const Field('M', 2)}),
        remote: remote,
        onAfterWrite: () {
          if (injected) return;
          injected = true;
          // `mine` now differs on both sides, and the user has never seen it.
          final x = doc({
            'a': const Field('base', 1),
            'mine': const Field('theirs', 9),
          });
          remote.put(serialize(x), x);
        },
      );

      expect(session.run(), Outcome.needsReview);
      // The merged state is retained; nothing was resolved by policy.
      expect(session.retainedMerged!['mine']?.value, 'M');
    });
  });

  group('T009 property 7 — the merge is a join-semilattice (guards N1, N3)', () {
    // Two devices only need the merge to be commutative. Three need it to be
    // associative as well, and nothing in this suite used to have three. Both
    // N1 (notes concatenation) and N3 (unknown timestamps) are invisible at two
    // devices and break the C2 short-circuit at three.
    Doc mergeOf(Doc a, Doc b) =>
        mergeDocs(a, b, notesKeys: const {'Notes'}).doc;

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

    /// Every association of [docs] under [mergeOf], as manifests: both folds,
    /// plus the balanced pairing once there are four operands.
    Set<String> allAssociations(List<Doc> docs) {
      final results = <String>{};
      for (final order in permutations(docs)) {
        results.add(manifest(order.reduce(mergeOf)));
        results.add(
          manifest(order.reversed.reduce((acc, d) => mergeOf(d, acc))),
        );
        if (order.length == 4) {
          results.add(
            manifest(
              mergeOf(mergeOf(order[0], order[1]), mergeOf(order[2], order[3])),
            ),
          );
        }
      }
      return results;
    }

    test('the notes union is associative at three and four devices', () {
      const zeta = 'zeta';
      const alpha = 'alpha';
      const mike = 'mike';
      const delta = 'delta';

      expect(
        mergeNotes(mergeNotes(zeta, alpha), mike),
        mergeNotes(zeta, mergeNotes(alpha, mike)),
      );
      expect(
        mergeNotes(mergeNotes(zeta, alpha), mergeNotes(mike, delta)),
        mergeNotes(zeta, mergeNotes(alpha, mergeNotes(mike, delta))),
      );

      // And under every ordering of the operands, not just these two shapes.
      final four = [zeta, alpha, mike, delta];
      final seen = <String>{};
      for (final order in permutations(four)) {
        seen.add(order.reduce(mergeNotes));
        seen.add(order.reversed.reduce((acc, s) => mergeNotes(s, acc)));
        seen.add(
          mergeNotes(
            mergeNotes(order[0], order[1]),
            mergeNotes(order[2], order[3]),
          ),
        );
      }
      expect(seen, hasLength(1), reason: 'observed distinct results: $seen');
      expect(seen.single.split(notesSeparator), [alpha, delta, mike, zeta]);
    });

    test('the notes union is idempotent — re-merging duplicates nothing', () {
      final once = mergeNotes('alpha', 'zeta');
      expect(mergeNotes(once, once), once);
      expect(mergeNotes(once, 'zeta'), once);
      expect(mergeNotes(once, 'alpha'), once);
      expect(
        mergeNotes(mergeNotes(once, 'mike'), 'mike'),
        mergeNotes(once, 'mike'),
      );
      // The failure this asserts against: a segment appearing twice.
      expect(mergeNotes(once, once).split(notesSeparator), ['alpha', 'zeta']);
    });

    test('a binary concatenation would have failed the test above', () {
      // Guards the premise: the property is not vacuously true of any merge.
      String concat(String a, String b) => compareValues(a, b) <= 0
          ? '$a$notesSeparator$b'
          : '$b$notesSeparator$a';
      expect(
        concat(concat('zeta', 'alpha'), 'mike'),
        isNot(concat('zeta', concat('alpha', 'mike'))),
      );
    });

    test('the whole merge is associative at three and four devices', () {
      Doc device(String note, String value, int? mtime) => doc({
        'Notes': Field(note, 100),
        'f': Field(value, mtime),
        'shared': const Field('s', 5),
      });

      expect(
        allAssociations([
          device('zeta', 'x', 100),
          device('alpha', 'y', 100),
          device('mike', 'z', 100),
        ]),
        hasLength(1),
      );
      expect(
        allAssociations([
          device('zeta', 'x', 100),
          device('alpha', 'y', 100),
          device('mike', 'z', 100),
          device('delta', 'w', 100),
        ]),
        hasLength(1),
      );
    });

    test('an unknown timestamp does not break associativity', () {
      // The N3 case, verbatim: with "unknown" treated as a bare tie the winner
      // was `z` under one association and `x` under another.
      final a = doc({'f': const Field('x', 5)});
      final b = doc({'f': const Field('y', null)});
      final c = doc({'f': const Field('z', 3)});

      expect(allAssociations([a, b, c]), hasLength(1));
      expect(
        mergeOf(mergeOf(a, b), c)['f']!.value,
        'x',
        reason: 'the newest known timestamp wins; unknown carries no evidence',
      );

      // Four devices, mixed known and unknown on both sides of the order.
      expect(
        allAssociations([
          a,
          b,
          c,
          doc({'f': const Field('w', null)}),
        ]),
        hasLength(1),
      );
    });

    test('an unknown timestamp loses to any known one, and two unknowns fall '
        'back to the value order', () {
      expect(
        compareFields(const Field('z', null), const Field('a', 1)),
        lessThan(0),
      );
      expect(
        compareFields(const Field('a', 1), const Field('z', null)),
        greaterThan(0),
      );
      expect(
        compareFields(const Field('b', null), const Field('a', null)),
        greaterThan(0),
      );
      expect(compareFields(const Field('a', null), const Field('a', null)), 0);
      // Mirrored perspectives still agree, which is why it is a tie-break.
      final l = doc({'f': const Field('a', null)});
      final r = doc({'f': const Field('b', null)});
      expect(mergeOf(l, r)['f'], mergeOf(r, l)['f']);
    });

    test('the merge is commutative and idempotent', () {
      final a = doc({
        'Notes': const Field('alpha', 100),
        'f': const Field('x', 7),
      });
      final b = doc({
        'Notes': const Field('zeta', 100),
        'f': const Field('y', null),
      });

      expect(manifest(mergeOf(a, b)), manifest(mergeOf(b, a)));
      expect(manifest(mergeOf(a, a)), manifest(a));
      expect(manifest(mergeOf(b, b)), manifest(b));

      final joined = mergeOf(a, b);
      expect(manifest(mergeOf(joined, a)), manifest(joined));
      expect(manifest(mergeOf(joined, b)), manifest(joined));
      expect(manifest(mergeOf(joined, joined)), manifest(joined));
    });

    test('the semilattice still holds on the values where the byte order and '
        'the UTF-16 order disagree', () {
      // The tie-break comparator moved from UTF-16 code units to UTF-8 bytes.
      // The three properties are claims about the relation being a total order,
      // not about *which* total order it is, so they are expected to survive the
      // change — and "expected to" is exactly the assumption this suite exists
      // to refuse. Every other property test here runs on ASCII, where the two
      // encodings agree and the change is invisible. They are re-measured here
      // on the values that actually moved.
      const astral = '\u{1F600}';
      const bmpHigh = '\uFFFD';
      const pua = '\uE000';
      const ascii = 'a';

      Doc device(String s) => doc({
        'Notes': Field(s, 100),
        'f': Field(s, 100),
        'shared': const Field('s', 5),
      });
      final devices = [astral, bmpHigh, pua, ascii].map(device).toList();

      // Associativity: every ordering and every association reach one state.
      expect(allAssociations(devices.sublist(0, 3)), hasLength(1));
      expect(allAssociations(devices), hasLength(1));

      // Commutativity, pairwise over the whole set.
      for (final a in devices) {
        for (final b in devices) {
          expect(manifest(mergeOf(a, b)), manifest(mergeOf(b, a)));
        }
      }

      // Idempotence, on each operand and on the join.
      final joined = devices.reduce(mergeOf);
      for (final d in devices) {
        expect(manifest(mergeOf(d, d)), manifest(d));
        expect(manifest(mergeOf(joined, d)), manifest(joined));
      }
      expect(manifest(mergeOf(joined, joined)), manifest(joined));

      // And the join really did select under the new order: the greatest UTF-8
      // byte sequence wins the tie-break, which is the astral character. Under
      // UTF-16 code units this would be U+FFFD and the segments would be in a
      // different order — so these two assertions also pin the encoding.
      expect(joined['f']!.value, astral);
      expect(joined['Notes']!.value.split(notesSeparator), [
        ascii, // 61
        pua, // EE 80 80
        bmpHigh, // EF BF BD
        astral, // F0 9F 98 80
      ]);
    });
  });

  group('T009 property 6 — a failed verification is not a passed one (C5)', () {
    test('a non-executable read-back is ambiguous, never finalized', () {
      final remote = Remote(doc({'a': const Field('r', 1)}));

      final session = CommitSession(
        local: doc({'a': const Field('r', 1), 'l': const Field('L', 2)}),
        remote: remote,
        onAfterWrite: () => remote.readBackFails = true,
      );

      final outcome = session.run();
      expect(outcome, Outcome.ambiguous);
      expect(outcome, isNot(Outcome.finalized));
      expect(outcome, isNot(Outcome.unresolved));
      // The merged state survives for the FR-10 triage to act on.
      expect(session.retainedMerged, isNotNull);
    });

    test('a read-back that fails on a later round is ambiguous too', () {
      // The classification must not depend on which round the read-back failed
      // in: the second read-back runs after a re-anchor and a re-merge, which
      // is a different path through the cycle.
      final remote = Remote(doc({'a': const Field('r', 1)}));
      var injected = false;

      final session = CommitSession(
        local: doc({'a': const Field('r', 1), 'l': const Field('L', 2)}),
        remote: remote,
        onAfterWrite: () {
          if (injected) {
            remote.readBackFails = true;
            return;
          }
          injected = true;
          final x = doc({'a': const Field('r', 1), 'x': const Field('X', 3)});
          remote.put(serialize(x), x);
        },
      );

      expect(session.run(), Outcome.ambiguous);
      expect(session.roundsUsed, 1, reason: 'it really reached a later round');
      // Both contributions are retained locally for the FR-10 triage.
      expect(session.retainedMerged!.keys, containsAll(['l', 'x']));
    });
  });
}
