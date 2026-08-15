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

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// One field of an entry: a value plus its KDBX modification time.
///
/// [mtime] has whole-second granularity on purpose — that is what makes a tie
/// an ordinary event rather than an exotic one, and a tie is what defect C4
/// turned into an infinite oscillation.
class Field {
  const Field(this.value, this.mtime);

  final String value;
  final int mtime;

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
/// Unsigned lexicographic comparison of the candidate values, shortest-is-
/// smaller on a common prefix. The winner is the **greater** sequence. The
/// direction is arbitrary by design; what matters is that it is total and
/// computed from the data alone, so two devices comparing the same unordered
/// pair select the same winner and the merge function is commutative.
int compareValues(String a, String b) {
  final ua = a.codeUnits;
  final ub = b.codeUnits;
  for (var i = 0; i < ua.length && i < ub.length; i++) {
    if (ua[i] != ub[i]) return ua[i] < ub[i] ? -1 : 1;
  }
  return ua.length.compareTo(ub.length);
}

/// FR-3's deterministic notes concatenation.
///
/// Operand order is fixed by [compareValues], NOT by `local + remote`. Ordering
/// by perspective would make two devices produce `A‖B` and `B‖A` — two byte
/// sequences and two semantic manifests — so the notes field alone would keep
/// the cycle divergent forever (defect C4b).
String concatNotes(String a, String b) =>
    compareValues(a, b) <= 0 ? '$a\n\n---\n\n$b' : '$b\n\n---\n\n$a';

/// The canonical semantic manifest: everything that is semantically meaningful,
/// and nothing that legitimately differs between two serializations of the same
/// logical database. In the real adapter this excludes KDF salt, master seed,
/// IV, ciphertext and `HeaderHash`; here it excludes the salt.
String manifest(Doc doc) {
  final keys = doc.keys.toList()..sort();
  return keys.map((k) => '$k=${doc[k]!.value}@${doc[k]!.mtime}').join(';');
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
      result[key] = l.mtime >= r.mtime ? l : r;
      continue;
    }

    // An explicit user decision is sticky and is replayed before any policy.
    final decided = ledger[key];
    if (decided != null) {
      result[key] = l.value == decided ? l : r;
      continue;
    }

    if (reportNewConflicts) {
      unseen.add(key);
      continue;
    }

    if (notesKeys.contains(key)) {
      // Deterministic both-sides concatenation, operand order fixed by value.
      result[key] = Field(
        concatNotes(l.value, r.value),
        l.mtime >= r.mtime ? l.mtime : r.mtime,
      );
      continue;
    }

    // Last-writer-wins on the KDBX modification time...
    if (l.mtime != r.mtime) {
      result[key] = l.mtime > r.mtime ? l : r;
      continue;
    }
    // ...and, on a tie, the globally deterministic total order. Never "local".
    result[key] = compareValues(l.value, r.value) >= 0 ? l : r;
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
  });
}
