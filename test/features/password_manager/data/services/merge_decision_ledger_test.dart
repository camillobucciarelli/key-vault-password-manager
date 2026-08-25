// spec-008 T401b — the session-lived sticky decision ledger.
//
// Pure unit tests: no KDBX file, no filesystem, no mutex. [KdbxFieldPresent]
// is constructed directly from its plain public constructor, which is all
// the ledger's own contract needs.
//
// Scope, against `spec.md` FR-7 §"Explicit user decisions are sticky across
// a re-merge" and criterion 15h:
//   * a recorded decision replays even when a fresh tie-break default would
//     pick the OTHER side — LWW/the tie-break never override a sticky
//     decision;
//   * a decision whose value no longer matches EITHER current candidate
//     reopens (`MergeLedgerStale`), never silently resolved;
//   * "never shown" and "stale" are distinguishable states;
//   * an operation (bothNotes/keep/delete) always replays verbatim, with no
//     candidate check;
//   * a credential-block decision is keyed by entry UUID alone and survives
//     even when its content shifts, as long as every shared member still
//     matches — and reopens as ONE unit, never split per member, the moment
//     any one member's value no longer matches (this is 15n's
//     "survives a re-merge as one unit" clause).
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/kdbx_merge_adapter.dart';
import 'package:password_manager/features/password_manager/data/services/merge_decision_ledger.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_merge_models.dart';

KdbxFieldPresent _present(String value, {bool protected = false}) =>
    KdbxFieldPresent(
      semanticValue: value,
      isProtected: protected,
      length: value.length,
    );

const _ref = (
  entryUuid: 'entry-1',
  fieldKind: KdbxMergeFieldKind.string,
  canonicalKey: 'notes',
);

void main() {
  group('15h — a recorded decision survives a re-merge, not reversed by the '
      'tie-break', () {
    test('replaying against the SAME pair returns the recorded choice, even '
        'when the OTHER side is the fresh tie-break winner', () {
      final ledger = MergeDecisionLedger();
      final local = _present('aaa'); // the LESSER value under FR-3 rule 3.
      final remote = _present('zzz'); // the tie-break's fresh default winner.

      // The user explicitly picked LOCAL, against the tie-break's own
      // default (which would elect remote, the greater byte sequence).
      ledger.recordField(_ref, MergeChoice.local, decidedValue: local);

      final replay = ledger.replayField(
        _ref,
        currentLocal: local,
        currentRemote: remote,
      );

      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.local);
    });

    test('a conflict first introduced by a re-merge and never shown is '
        'flagged, not auto-resolved', () {
      final ledger = MergeDecisionLedger();
      final replay = ledger.replayField(
        _ref,
        currentLocal: _present('a'),
        currentRemote: _present('b'),
      );
      expect(replay, isA<MergeLedgerNeverShown>());
    });
  });

  group('the replay invariant: decided must name one of the two current '
      'candidates', () {
    test('a decision whose value no longer matches EITHER current candidate '
        'reopens instead of picking a side', () {
      final ledger = MergeDecisionLedger();
      ledger.recordField(
        _ref,
        MergeChoice.local,
        decidedValue: _present('decided-value'),
      );

      // Neither current candidate is the decided value — a state spec.md
      // records as unreachable today (FR-4 + session-scoping guarantee it),
      // but the ledger must still handle it defensively rather than guess.
      final replay = ledger.replayField(
        _ref,
        currentLocal: _present('something-else'),
        currentRemote: _present('something-else-again'),
      );

      expect(replay, isA<MergeLedgerStale>());
    });

    test('"never shown" and "stale" are distinguishable, not collapsed to '
        'one signal', () {
      final ledger = MergeDecisionLedger();
      ledger.recordField(
        _ref,
        MergeChoice.remote,
        decidedValue: _present('gone-now'),
      );

      final neverShown = ledger.replayField(
        (
          entryUuid: 'entry-2',
          fieldKind: KdbxMergeFieldKind.string,
          canonicalKey: 'url',
        ),
        currentLocal: _present('x'),
        currentRemote: _present('y'),
      );
      final stale = ledger.replayField(
        _ref,
        currentLocal: _present('x'),
        currentRemote: _present('y'),
      );

      expect(neverShown, isA<MergeLedgerNeverShown>());
      expect(stale, isA<MergeLedgerStale>());
      expect(neverShown.runtimeType, isNot(stale.runtimeType));
    });

    test('a decision that still matches ONE side, even if the OTHER side '
        'also changed, replays — the invariant is "matches one candidate", '
        'not "matches the original pair exactly"', () {
      final ledger = MergeDecisionLedger();
      final decided = _present('kept-value');
      ledger.recordField(_ref, MergeChoice.local, decidedValue: decided);

      final replay = ledger.replayField(
        _ref,
        currentLocal: decided, // unchanged
        currentRemote: _present('a-third-value'), // remote moved again
      );

      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.local);
    });

    test('same-side-flip: decided as remote, but the decided value now sits '
        'on currentLocal (carried forward by the round-1 apply step) while '
        'currentRemote moved again — replays as LOCAL, the side that '
        'currently holds it, not the originally recorded tag', () {
      final ledger = MergeDecisionLedger();
      final decided = _present('B');
      ledger.recordField(_ref, MergeChoice.remote, decidedValue: decided);

      final replay = ledger.replayField(
        _ref,
        currentLocal: decided, // carried forward by the round-1 apply step
        currentRemote: _present('C'), // moved again by a concurrent writer
      );

      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.local);
    });

    test('same-side-flip, mirrored: decided as local, but the decided value '
        'is later found on currentRemote — replays as REMOTE', () {
      final ledger = MergeDecisionLedger();
      final decided = _present('B');
      ledger.recordField(_ref, MergeChoice.local, decidedValue: decided);

      final replay = ledger.replayField(
        _ref,
        currentLocal: _present('C'),
        currentRemote: decided,
      );

      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.remote);
    });
  });

  group('operations (bothNotes/keep/delete) always replay verbatim', () {
    test('bothNotes needs no candidate snapshot and always replays', () {
      final ledger = MergeDecisionLedger();
      ledger.recordField(_ref, MergeChoice.bothNotes);

      final replay = ledger.replayField(
        _ref,
        currentLocal: _present('anything'),
        currentRemote: _present('anything-else'),
      );

      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.bothNotes);
    });

    test('keep/delete on a record replays with no candidate check at all', () {
      final ledger = MergeDecisionLedger();
      ledger.recordRecord('record-1', MergeChoice.delete);
      final replay = ledger.replayRecord('record-1');
      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.delete);
    });

    test('an unrecorded record is never shown', () {
      final ledger = MergeDecisionLedger();
      expect(
        ledger.replayRecord('record-missing'),
        isA<MergeLedgerNeverShown>(),
      );
    });
  });

  group('shortcut decisions are recorded the same way as a manual choice', () {
    test('recordField has no separate "shortcut" path — a Prefer-local '
        'answer replays identically to a manually confirmed one', () {
      final ledger = MergeDecisionLedger();
      final local = _present('local-wins');
      ledger.recordField(_ref, MergeChoice.local, decidedValue: local);

      final replay = ledger.replayField(
        _ref,
        currentLocal: local,
        currentRemote: _present('remote-value'),
      );
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.local);
    });
  });

  group('T401c — credential-block decisions are keyed by entry UUID alone, '
      'and reopen as ONE unit (15n)', () {
    test('a block decision survives even though the anchor member would '
        'change on a re-merge, because the key is the entry UUID, never a '
        'field ref', () {
      final ledger = MergeDecisionLedger();
      const entryUuid = 'entry-block-1';
      final decided = {
        'password': _present('secretC', protected: true),
        'username': _present('A'),
      };
      ledger.recordCredentialBlock(
        entryUuid,
        MergeChoice.remote,
        decidedValue: decided,
      );

      // A re-merge where every member's value is UNCHANGED still replays,
      // regardless of which member would now be the "anchor" for display.
      final replay = ledger.replayCredentialBlock(
        entryUuid,
        currentLocal: {
          'password': _present('secretB'),
          'username': _present('Z'),
        },
        currentRemote: decided,
      );

      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.remote);
    });

    test('one member moving reopens the WHOLE block, never a subset of it '
        '— the ledger has no way to represent a partial block decision', () {
      final ledger = MergeDecisionLedger();
      const entryUuid = 'entry-block-2';
      ledger.recordCredentialBlock(
        entryUuid,
        MergeChoice.remote,
        decidedValue: {
          'password': _present('secretC'),
          'username': _present('A'),
        },
      );

      // Password still matches the decided remote snapshot, but username
      // does not (a later round changed it) — the WHOLE block must reopen,
      // not just the username member.
      final replay = ledger.replayCredentialBlock(
        entryUuid,
        currentLocal: {
          'password': _present('secretB'),
          'username': _present('Z'),
        },
        currentRemote: {
          'password': _present('secretC'),
          'username': _present('A-changed-again'),
        },
      );

      expect(replay, isA<MergeLedgerStale>());
    });

    test('same-side-flip: decided as remote, but the decided block now sits '
        'on currentLocal while currentRemote moved again — replays as '
        'LOCAL', () {
      final ledger = MergeDecisionLedger();
      const entryUuid = 'entry-block-3';
      final decided = {
        'password': _present('secretB', protected: true),
        'username': _present('B'),
      };
      ledger.recordCredentialBlock(
        entryUuid,
        MergeChoice.remote,
        decidedValue: decided,
      );

      final replay = ledger.replayCredentialBlock(
        entryUuid,
        currentLocal: decided, // carried forward by the round-1 apply step
        currentRemote: {
          'password': _present('secretC', protected: true),
          'username': _present('C'),
        },
      );

      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.local);
    });

    test('same-side-flip, mirrored: decided as local, but the decided block '
        'is later found on currentRemote — replays as REMOTE', () {
      final ledger = MergeDecisionLedger();
      const entryUuid = 'entry-block-4';
      final decided = {
        'password': _present('secretB', protected: true),
        'username': _present('B'),
      };
      ledger.recordCredentialBlock(
        entryUuid,
        MergeChoice.local,
        decidedValue: decided,
      );

      final replay = ledger.replayCredentialBlock(
        entryUuid,
        currentLocal: {
          'password': _present('secretC', protected: true),
          'username': _present('C'),
        },
        currentRemote: decided,
      );

      expect(replay, isA<MergeLedgerReplayed>());
      expect((replay as MergeLedgerReplayed).choice, MergeChoice.remote);
    });

    test('an unrecorded block is never shown', () {
      final ledger = MergeDecisionLedger();
      final replay = ledger.replayCredentialBlock(
        'entry-block-unknown',
        currentLocal: const {},
        currentRemote: const {},
      );
      expect(replay, isA<MergeLedgerNeverShown>());
    });
  });
}
