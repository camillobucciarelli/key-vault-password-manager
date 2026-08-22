// spec-008 T307 — presence and UUID tests for the production merge adapter.
//
// Scope, exactly as the task defines it:
//   * every T304 failure mode — nil UUID, duplicate entry UUID, duplicate group
//     UUID, group/entry collision, cross-side object-kind mismatch;
//   * T305's lineage refusal and the unsupported-construct refusal;
//   * the FR-4 presence matrix inside ONE shared entry UUID: local-only and
//     remote-only custom fields and attachments, empty-string vs missing,
//     zero-byte attachment vs missing, protection flags, and equal name with
//     different bytes.
//
// Two things every refusal test asserts beyond the code: that the failure is a
// typed `SyncMergeFailure`, and that it carries nothing else. A refusal that
// leaks the offending UUID into its message would satisfy FR-2's classification
// and violate FR-2's redaction in the same line.
//
// Coherence with the T009/T009b convergence models is asserted where the
// adapter is the thing those models assumed: the models take "presence" as
// given and prove convergence over it, so what the adapter must demonstrate is
// that its presence evidence has the shape the models assumed — absence is
// never deletion evidence, and an empty value is present.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
// `forceSetUuid` is how a fixture gives two replicas a shared lineage and how
// the T304 collision cases are authored. Gate 0 recorded it as living outside
// the public export surface. It is needed by the FIXTURES only — the adapter
// itself is built on the public API alone.
// ignore: implementation_imports
import 'package:kdbx/src/kdbx_object.dart' show KdbxObjectInternal;
import 'package:password_manager/features/password_manager/data/services/kdbx_merge_adapter.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_merge_models.dart';
import 'package:password_manager/features/password_manager/domain/repositories/sync_merge_repository.dart';

// Obviously fake, non-secret test material.
const _password = 'adapter-not-a-real-password';
const _sharedEntryUuid = 'BBBBBBBBBBBBBBBBBBBBAQ==';
const _childGroupUuid = 'BBBBBBBBBBBBBBBBBBBBAg==';

Credentials _credentials() => Credentials(ProtectedValue.fromString(_password));

/// A minimal two-side-able database: one child group and one entry with a
/// stable UUID, so both replicas address the same objects.
KdbxFile _buildSide(Credentials credentials) {
  final file = KdbxFormat().create(
    credentials,
    'Adapter DB',
    generator: 'spec-008-t307',
  );
  final root = file.body.rootGroup;
  final child = file.createGroup(parent: root, name: 'Child')
    ..forceSetUuid(KdbxUuid(_childGroupUuid));
  final entry = KdbxEntry.create(file, child)
    ..forceSetUuid(KdbxUuid(_sharedEntryUuid));
  child.addEntry(entry);
  entry
    ..setString(KdbxKeyCommon.TITLE, PlainValue('Shared'))
    ..setString(KdbxKeyCommon.USER_NAME, PlainValue('alice'));
  return file;
}

/// Two replicas sharing a lineage, as a real local/remote pair does.
({KdbxFile local, KdbxFile remote}) _replicaPair(Credentials credentials) {
  final local = _buildSide(credentials);
  final remote = _buildSide(credentials);
  remote.body.rootGroup.forceSetUuid(local.body.rootGroup.uuid);
  return (local: local, remote: remote);
}

KdbxEntry _sharedEntry(KdbxFile file) => file.body.rootGroup
    .getAllEntries()
    .firstWhere((e) => e.uuid.uuid == _sharedEntryUuid);

/// Looks a field up the way KDBX matches keys: case-insensitively. A helper
/// that matched a verbatim spelling would reproduce the F1 defect inside the
/// test harness and hide it again.
KdbxFieldDiff _diffFor(
  KdbxPresenceDiff diff,
  KdbxMergeFieldKind kind,
  String key,
) => diff.fieldDiffs.singleWhere(
  (d) => d.fieldKind == kind && d.canonicalKey == canonicalFieldKey(key),
  orElse: () => throw StateError('no $kind diff for "$key"'),
);

Matcher _failsWith(MergeFailureCode code) =>
    throwsA(isA<SyncMergeFailure>().having((f) => f.code, 'code', code));

void main() {
  const adapter = KdbxMergeAdapter();
  late Credentials credentials;

  setUp(() => credentials = _credentials());

  // ===========================================================================
  // T304 — pre-diff UUID validation. Every failure is refused BEFORE a diff,
  // and therefore before any session, backup, local write or upload can exist:
  // `validatePair` is the only producer of the `KdbxMergePair` that
  // `diffPresence` consumes.
  // ===========================================================================
  group('T304 pre-diff UUID validation', () {
    test('a clean replica pair validates', () {
      final pair = _replicaPair(credentials);
      expect(
        () => adapter.validatePair(local: pair.local, remote: pair.remote),
        returnsNormally,
      );
    });

    test('nil live UUID is unsupportedKdbxData', () {
      final pair = _replicaPair(credentials);
      _sharedEntry(pair.local).forceSetUuid(KdbxUuid.NIL);

      expect(
        () => adapter.validatePair(local: pair.local, remote: pair.remote),
        _failsWith(MergeFailureCode.unsupportedKdbxData),
      );
    });

    test('duplicate entry UUID is unsupportedKdbxData', () {
      final pair = _replicaPair(credentials);
      final extra = KdbxEntry.create(pair.local, pair.local.body.rootGroup)
        ..forceSetUuid(KdbxUuid(_sharedEntryUuid));
      pair.local.body.rootGroup.addEntry(extra);

      expect(
        () => adapter.validatePair(local: pair.local, remote: pair.remote),
        _failsWith(MergeFailureCode.unsupportedKdbxData),
      );
    });

    test('duplicate group UUID is unsupportedKdbxData', () {
      final pair = _replicaPair(credentials);
      pair.local
          .createGroup(parent: pair.local.body.rootGroup, name: 'Twin')
          .forceSetUuid(KdbxUuid(_childGroupUuid));

      expect(
        () => adapter.validatePair(local: pair.local, remote: pair.remote),
        _failsWith(MergeFailureCode.unsupportedKdbxData),
      );
    });

    test('group/entry UUID collision is unsupportedKdbxData', () {
      // The case a per-collection uniqueness check passes: the UUID is unique
      // among entries and unique among groups, and still invalid.
      final pair = _replicaPair(credentials);
      _sharedEntry(pair.local).forceSetUuid(KdbxUuid(_childGroupUuid));

      expect(
        () => adapter.validatePair(local: pair.local, remote: pair.remote),
        _failsWith(MergeFailureCode.unsupportedKdbxData),
      );
    });

    test('group/entry UUID collision is caught WITHIN one side — proved by '
        'validating a side against itself', () {
      // F3. The cross-side test below compares two DIFFERENT files, so the
      // cross-side kind check fires and the per-side collision check is never
      // reached: a mutation degrading `_validateSide` to per-collection
      // uniqueness survived it. Self-comparison removes the cross-side path
      // entirely — both indexes are the same index, so no kind can mismatch —
      // leaving only the per-side check able to fail.
      final pair = _replicaPair(credentials);
      _sharedEntry(pair.local).forceSetUuid(KdbxUuid(_childGroupUuid));

      expect(
        () => adapter.validatePair(local: pair.local, remote: pair.local),
        _failsWith(MergeFailureCode.unsupportedKdbxData),
      );
    });

    test('cross-side object-kind mismatch is unsupportedKdbxData, and each '
        'side alone is valid', () {
      final pair = _replicaPair(credentials);
      // A UUID present on neither side yet, so only the CROSS-side comparison
      // can fail — otherwise the test would pass for the wrong reason.
      final shared = KdbxUuid.random();
      final localEntry = KdbxEntry.create(pair.local, pair.local.body.rootGroup)
        ..forceSetUuid(shared);
      pair.local.body.rootGroup.addEntry(localEntry);
      pair.remote
          .createGroup(parent: pair.remote.body.rootGroup, name: 'Same Uuid')
          .forceSetUuid(shared);

      // Each side is internally valid: same-side validation cannot see this.
      expect(
        () => adapter.validatePair(local: pair.local, remote: pair.local),
        returnsNormally,
      );
      expect(
        () => adapter.validatePair(local: pair.remote, remote: pair.remote),
        returnsNormally,
      );

      expect(
        () => adapter.validatePair(local: pair.local, remote: pair.remote),
        _failsWith(MergeFailureCode.unsupportedKdbxData),
      );
    });

    test('the same entry UUID on both sides under different conditions is '
        'valid — it is the ordinary shared-record case', () {
      // The counterpart of the collision tests: a UUID appearing twice is only
      // a violation WITHIN one side. Across sides it is what "the same record"
      // means, whatever else differs about it (parent group, values,
      // attachments, protection).
      final pair = _replicaPair(credentials);
      final local = _sharedEntry(pair.local);
      final remote = _sharedEntry(pair.remote);

      local.setString(KdbxKeyCommon.URL, PlainValue('https://a.invalid'));
      remote.setString(KdbxKeyCommon.URL, PlainValue('https://b.invalid'));
      remote.setString(
        KdbxKeyCommon.PASSWORD,
        ProtectedValue.fromString('remote-secret'),
      );
      // Different parent group on the remote side.
      KdbxDao(pair.remote).move(remote, pair.remote.body.rootGroup);

      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      final diff = adapter.diffPresence(validated);

      expect(diff.localOnlyEntryUuids, isEmpty);
      expect(diff.remoteOnlyEntryUuids, isEmpty);
      expect(
        _diffFor(
          diff,
          KdbxMergeFieldKind.string,
          KdbxKeyCommon.KEY_URL,
        ).classification,
        KdbxFieldClassification.fieldConflict,
      );
    });

    test('the refusal carries a safe code and no object label', () {
      final pair = _replicaPair(credentials);
      final offending = _sharedEntry(pair.local).uuid.uuid;
      _sharedEntry(pair.local).forceSetUuid(KdbxUuid.NIL);

      try {
        adapter.validatePair(local: pair.local, remote: pair.remote);
        fail('expected a SyncMergeFailure');
      } on SyncMergeFailure catch (failure) {
        expect(failure.code, MergeFailureCode.unsupportedKdbxData);
        expect(failure.localCommitCompleted, isFalse);
        expect(failure.toString(), isNot(contains(offending)));
        expect(failure.toString(), isNot(contains('Shared')));
      }
    });
  });

  // ===========================================================================
  // T305 — lineage and unsupported-construct guards.
  // ===========================================================================
  group('T305 lineage and unsupported guards', () {
    test('mismatched root group UUID is wrongLineage', () {
      final local = _buildSide(credentials);
      final foreign = _buildSide(credentials);
      // Two independently created databases never share a root UUID, which is
      // why a shared remote file id is not lineage evidence (FR-2).
      expect(local.body.rootGroup.uuid, isNot(foreign.body.rootGroup.uuid));

      expect(
        () => adapter.validatePair(local: local, remote: foreign),
        _failsWith(MergeFailureCode.wrongLineage),
      );
    });

    test('a per-side UUID violation is refused before the lineage check, so '
        'two nil roots cannot pass by comparing equal', () {
      final local = _buildSide(credentials);
      final foreign = _buildSide(credentials);
      local.body.rootGroup.forceSetUuid(KdbxUuid.NIL);
      foreign.body.rootGroup.forceSetUuid(KdbxUuid.NIL);

      // Lineage alone would say "match". The per-side gate runs first.
      expect(local.body.rootGroup.uuid, foreign.body.rootGroup.uuid);
      expect(
        () => adapter.validatePair(local: local, remote: foreign),
        _failsWith(MergeFailureCode.unsupportedKdbxData),
      );
    });

    test('a pair that is BOTH structurally invalid and of a different lineage '
        'reports unsupportedKdbxData, not wrongLineage', () {
      // F2. This is what the per-side-before-lineage order actually pins. The
      // previous justification — "two nil roots would pass lineage" — was
      // false: the per-side check catches them either way, so swapping the two
      // blocks survived the whole suite. What genuinely changes with the order
      // is the code REPORTED when both are violated, and it matters:
      // `wrongLineage` tells the user "these are two different databases",
      // which is the wrong remedy for one that is corrupt.
      final local = _buildSide(credentials);
      final foreign = _buildSide(credentials);
      expect(local.body.rootGroup.uuid, isNot(foreign.body.rootGroup.uuid));
      _sharedEntry(local).forceSetUuid(KdbxUuid.NIL);

      expect(
        () => adapter.validatePair(local: local, remote: foreign),
        _failsWith(MergeFailureCode.unsupportedKdbxData),
      );
    });

    test('a reopened save of the same database keeps its lineage', () async {
      final local = _buildSide(credentials);
      final replica = await adapter.openSide(
        bytes: Uint8List.fromList(await local.save()),
        credentials: credentials,
      );

      expect(
        () => adapter.validatePair(local: local, remote: replica),
        returnsNormally,
      );
    });

    test(
      'an unsupported KDBX major version is unsupportedKdbxConstruct',
      () async {
        const majorVersionOffset = 10;
        final bytes = Uint8List.fromList(await _buildSide(credentials).save());
        ByteData.sublistView(
          bytes,
        ).setUint16(majorVersionOffset, 9, Endian.little);

        await expectLater(
          adapter.openSide(bytes: bytes, credentials: credentials),
          _failsWith(MergeFailureCode.unsupportedKdbxConstruct),
        );
      },
    );

    test('a header the parser cannot read at all is also '
        'unsupportedKdbxConstruct, not a silent empty side', () async {
      // Gate 0 recorded that below 3.x the failure is a RangeError, not a
      // KdbxUnsupportedException. One refusal covers both.
      const majorVersionOffset = 10;
      final bytes = Uint8List.fromList(await _buildSide(credentials).save());
      ByteData.sublistView(
        bytes,
      ).setUint16(majorVersionOffset, 2, Endian.little);

      await expectLater(
        adapter.openSide(bytes: bytes, credentials: credentials),
        _failsWith(MergeFailureCode.unsupportedKdbxConstruct),
      );
    });

    test(
      'wrong credentials are NOT reported as an unsupported construct',
      () async {
        final bytes = Uint8List.fromList(await _buildSide(credentials).save());

        await expectLater(
          adapter.openSide(
            bytes: bytes,
            credentials: Credentials(
              ProtectedValue.fromString('wrong-$_password'),
            ),
          ),
          throwsA(isNot(isA<SyncMergeFailure>())),
        );
      },
    );
  });

  // ===========================================================================
  // T306/T307 — the FR-4 presence matrix, inside ONE shared entry UUID.
  // ===========================================================================
  group('T306 field presence diff', () {
    late KdbxFile local;
    late KdbxFile remote;
    late KdbxEntry localEntry;
    late KdbxEntry remoteEntry;

    setUp(() {
      final pair = _replicaPair(credentials);
      local = pair.local;
      remote = pair.remote;
      localEntry = _sharedEntry(local);
      remoteEntry = _sharedEntry(remote);
    });

    KdbxPresenceDiff run() => adapter.diffPresence(
      adapter.validatePair(local: local, remote: remote),
    );

    test('present and equal on both sides is identical, not a conflict', () {
      final diff = run();
      expect(
        _diffFor(
          diff,
          KdbxMergeFieldKind.string,
          KdbxKeyCommon.KEY_USER_NAME,
        ).classification,
        KdbxFieldClassification.identical,
      );
    });

    test('present and different on both sides is a fieldConflict', () {
      localEntry.setString(KdbxKey('Custom_Note'), PlainValue('local'));
      remoteEntry.setString(KdbxKey('Custom_Note'), PlainValue('remote'));

      expect(
        _diffFor(
          run(),
          KdbxMergeFieldKind.string,
          'Custom_Note',
        ).classification,
        KdbxFieldClassification.fieldConflict,
      );
    });

    test('a local-only custom field is fieldLocalOnly and stays present', () {
      localEntry.setString(KdbxKey('Custom_LocalOnly'), PlainValue('kept'));

      final field = _diffFor(
        run(),
        KdbxMergeFieldKind.string,
        'Custom_LocalOnly',
      );
      expect(field.classification, KdbxFieldClassification.fieldLocalOnly);
      expect(field.local, isA<KdbxFieldPresent>());
      expect(field.remote, isA<KdbxFieldMissing>());
    });

    test('a remote-only custom field is fieldRemoteOnly and stays present', () {
      remoteEntry.setString(
        KdbxKey('Custom_RemoteOnly'),
        ProtectedValue.fromString('kept'),
      );

      final field = _diffFor(
        run(),
        KdbxMergeFieldKind.string,
        'Custom_RemoteOnly',
      );
      expect(field.classification, KdbxFieldClassification.fieldRemoteOnly);
      expect(field.local, isA<KdbxFieldMissing>());
      expect((field.remote as KdbxFieldPresent).isProtected, isTrue);
    });

    test('an empty string is PRESENT, not missing — the FR-4 case the spec '
        'calls out by name', () {
      localEntry.setString(KdbxKey('Custom_Empty'), PlainValue(''));

      final field = _diffFor(run(), KdbxMergeFieldKind.string, 'Custom_Empty');
      // Empty vs missing is a ONE-SIDED field, i.e. an automatic union member.
      // If empty collapsed to missing, this row would not exist at all — which
      // is exactly how a user's deliberate blanking gets silently dropped.
      expect(field.classification, KdbxFieldClassification.fieldLocalOnly);
      expect(field.local.isPresent, isTrue);
      expect((field.local as KdbxFieldPresent).semanticValue, '');
      expect(field.remote.isPresent, isFalse);
    });

    test('empty on one side and non-empty on the other is a conflict, not a '
        'one-sided field', () {
      localEntry.setString(KdbxKey('Custom_Blank'), PlainValue(''));
      remoteEntry.setString(KdbxKey('Custom_Blank'), PlainValue('text'));

      expect(
        _diffFor(
          run(),
          KdbxMergeFieldKind.string,
          'Custom_Blank',
        ).classification,
        KdbxFieldClassification.fieldConflict,
      );
    });

    test('a protection-flag change alone is a conflict, not identical', () {
      localEntry.setString(KdbxKey('Custom_Prot'), PlainValue('same'));
      remoteEntry.setString(
        KdbxKey('Custom_Prot'),
        ProtectedValue.fromString('same'),
      );

      final field = _diffFor(run(), KdbxMergeFieldKind.string, 'Custom_Prot');
      expect(field.classification, KdbxFieldClassification.fieldConflict);
      expect((field.local as KdbxFieldPresent).isProtected, isFalse);
      expect((field.remote as KdbxFieldPresent).isProtected, isTrue);
    });

    // -----------------------------------------------------------------------
    // F1 — KDBX keys are case-insensitive. The adapter must match the way KDBX
    // matches, or a real conflict is reported as two automatic unions the user
    // never sees, and the "union" it proposes cannot even be written back.
    // -----------------------------------------------------------------------
    test('a custom field spelled differently on the two sides is ONE '
        'fieldConflict, not two one-sided unions', () {
      localEntry.setString(KdbxKey('Custom_Totp'), PlainValue('AAA'));
      remoteEntry.setString(KdbxKey('custom_totp'), PlainValue('BBB'));

      final diff = run();
      final rows = diff.fieldDiffs.where(
        (d) =>
            d.fieldKind == KdbxMergeFieldKind.string &&
            d.canonicalKey == 'custom_totp',
      );

      expect(
        rows,
        hasLength(1),
        reason:
            'KDBX stores these as ONE key; two rows means the user is shown '
            'two automatic unions instead of the conflict, and the proposed '
            'union collapses onto one key on write, losing a value silently.',
      );
      expect(rows.single.classification, KdbxFieldClassification.fieldConflict);
      expect(diff.oneSidedFieldCount, 0);
    });

    test('an attachment spelled differently on the two sides is ONE '
        'fieldConflict, not two one-sided unions', () {
      localEntry.createBinary(
        isProtected: false,
        name: 'Doc.PDF',
        bytes: Uint8List.fromList([1]),
      );
      remoteEntry.createBinary(
        isProtected: false,
        name: 'doc.pdf',
        bytes: Uint8List.fromList([2]),
      );

      final rows = run().fieldDiffs.where(
        (d) =>
            d.fieldKind == KdbxMergeFieldKind.attachment &&
            d.canonicalKey == 'doc.pdf',
      );

      expect(rows, hasLength(1));
      expect(rows.single.classification, KdbxFieldClassification.fieldConflict);
    });

    test('divergent key spelling is reported, both spellings preserved, and '
        'no winner is invented', () {
      localEntry.setString(KdbxKey('Custom_Totp'), PlainValue('same'));
      remoteEntry.setString(KdbxKey('custom_totp'), PlainValue('same'));

      final field = _diffFor(run(), KdbxMergeFieldKind.string, 'custom_totp');
      // Equal values: FR-4's "present, equal" row still holds, so the spelling
      // difference must NOT be promoted into a conflict the user has to answer.
      expect(field.classification, KdbxFieldClassification.identical);
      expect(field.keySpellingDiverges, isTrue);
      expect(field.localKey, 'Custom_Totp');
      expect(field.remoteKey, 'custom_totp');
      expect(field.canonicalKey, 'custom_totp');
    });

    test('matching spelling does not report a divergence', () {
      localEntry.setString(KdbxKey('Custom_Same'), PlainValue('a'));
      remoteEntry.setString(KdbxKey('Custom_Same'), PlainValue('b'));

      expect(
        _diffFor(
          run(),
          KdbxMergeFieldKind.string,
          'Custom_Same',
        ).keySpellingDiverges,
        isFalse,
      );
    });

    test('canonicalFieldKey is EXACTLY KdbxKey semantics, not an '
        'approximation', () {
      // R1. The rest of the suite pins canonicalFieldKey in ONE direction:
      // under-normalising dies (that was F1). Over-normalising survived —
      // `.toLowerCase().trim()` and a stray combining-mark strip both passed
      // the whole adapter suite.
      //
      // That is F1's exact mirror image, with the same consequence. KDBX holds
      // `Note` and `Note ` as two distinct keys; a canonicaliser that trims
      // fuses them into one row, the user picks one value, and at apply time a
      // whole field disappears. It is precisely the edit that arrives as
      // "harmless cleanup" in a refactoring PR.
      //
      // So the property asserted is equivalence with `KdbxKey`, in both
      // directions, over a battery of the pairs where Unicode case folding is
      // actually contentious — not a sample of the cases the implementation
      // happens to handle.
      const battery = <String>[
        // Sharp s: uppercases to two characters, so a fold-based
        // implementation and a lowercase-based one disagree.
        '\u00df', 'SS', 'ss', 'Stra\u00dfe', 'STRASSE',
        // Turkish dotted/dotless I — the classic locale-sensitive trap.
        '\u0130', '\u0131', 'i', 'I', 'i\u0307',
        // Greek sigma: two lowercase forms for one uppercase.
        '\u03a3', '\u03c3', '\u03c2',
        // Singleton case mappings: Kelvin sign, Angstrom sign.
        '\u212a', 'K', 'k', '\u212b', '\u00c5', '\u00e5',
        // Titlecase digraphs: three cases, not two.
        '\u01c4', '\u01c5', '\u01c6',
        // Ligature: case-folds to two characters under full folding.
        '\ufb01', 'fi', 'FI',
        // Astral pair (Deseret): needs surrogate-aware mapping.
        '\u{10400}', '\u{10428}',
        // NFC vs NFD — canonically equivalent, different code points.
        'caf\u00e9', 'cafe\u0301', 'CAF\u00c9', 'CAFE\u0301',
        // Whitespace: the cases a `.trim()` would destroy.
        '', ' ', '  ', 'a', 'a ', ' a', 'Note', 'Note ',
        // Fullwidth forms.
        '\uff21', '\uff41',
        // Ordinary keys, so the battery is not all edge cases.
        'Title', 'title', 'Custom_Totp', 'custom_totp', 'URL',
      ];

      for (final a in battery) {
        expect(
          canonicalFieldKey(a).hashCode,
          KdbxKey(a).hashCode,
          reason: 'hash disagrees for ${a.codeUnits}',
        );
        for (final b in battery) {
          expect(
            canonicalFieldKey(a) == canonicalFieldKey(b),
            KdbxKey(a) == KdbxKey(b),
            reason: 'a=${a.codeUnits} b=${b.codeUnits}',
          );
        }
      }
    });

    test('KdbxKey case-insensitivity is a property of the library, not an '
        'assumption of this test', () {
      // If this ever changes upstream, the tests above would keep passing for
      // the wrong reason.
      expect(KdbxKey('Custom_Totp'), KdbxKey('custom_totp'));
      localEntry
        ..setString(KdbxKey('Custom_Totp'), PlainValue('AAA'))
        ..setString(KdbxKey('custom_totp'), PlainValue('BBB'));
      expect(
        localEntry.stringEntries.map((e) => e.key.key),
        contains('Custom_Totp'),
        reason: 'KDBX keeps ONE key, with the spelling it first stored',
      );
      expect(
        localEntry.stringEntries
            .where((e) => canonicalFieldKey(e.key.key) == 'custom_totp')
            .length,
        1,
      );
    });

    test('Title vs title behaves — the case that masked the defect', () {
      // Both sides already hold a `Title` string, so `setString` with a
      // differently-spelled key resolves through `KdbxKey.==` onto the key
      // already stored and KDBX keeps the original spelling. This path was
      // always correct, which is exactly why the first implementation looked
      // right: the defect needs the two sides to create the key
      // INDEPENDENTLY, which only happens in a merge.
      remoteEntry.setString(KdbxKey('title'), PlainValue('Changed'));

      expect(
        remoteEntry.stringEntries.map((e) => e.key.key),
        contains(KdbxKeyCommon.KEY_TITLE),
      );
      final rows = run().fieldDiffs.where(
        (d) =>
            d.fieldKind == KdbxMergeFieldKind.string &&
            d.canonicalKey == 'title',
      );
      expect(rows, hasLength(1));
      expect(rows.single.classification, KdbxFieldClassification.fieldConflict);
    });

    // -----------------------------------------------------------------------
    // F7 — no silent normalisation of values.
    // -----------------------------------------------------------------------
    test('NFC and NFD spellings of the same text are a conflict, never '
        'silently normalised', () {
      // "é" as one code point vs "e" + combining acute. Visually identical,
      // different stored bytes. Normalising would rewrite a value the user
      // stored; in a password field that is a credential that stops working.
      localEntry.setString(KdbxKey('Custom_Uni'), PlainValue('caf\u00e9'));
      remoteEntry.setString(KdbxKey('Custom_Uni'), PlainValue('cafe\u0301'));

      expect(
        _diffFor(run(), KdbxMergeFieldKind.string, 'Custom_Uni').classification,
        KdbxFieldClassification.fieldConflict,
      );
    });

    test('trailing whitespace is a conflict, never trimmed away', () {
      // Guard against a future "helpful" `trim()` in the comparison.
      localEntry.setString(KdbxKey('Custom_Ws'), PlainValue('secret'));
      remoteEntry.setString(KdbxKey('Custom_Ws'), PlainValue('secret '));

      final field = _diffFor(run(), KdbxMergeFieldKind.string, 'Custom_Ws');
      expect(field.classification, KdbxFieldClassification.fieldConflict);
      expect((field.remote as KdbxFieldPresent).semanticValue, 'secret ');
    });

    test(
      'key matching is case-insensitive but never case-folding the VALUE',
      () {
        localEntry.setString(KdbxKey('Custom_Case'), PlainValue('Value'));
        remoteEntry.setString(KdbxKey('Custom_Case'), PlainValue('value'));

        expect(
          _diffFor(
            run(),
            KdbxMergeFieldKind.string,
            'Custom_Case',
          ).classification,
          KdbxFieldClassification.fieldConflict,
        );
      },
    );

    // -----------------------------------------------------------------------
    // F8 — the null StringValue branch, and what persistence does to it.
    // -----------------------------------------------------------------------
    test('setString(key, null) REMOVES the key, so it is missing — not a '
        'present empty value', () {
      // `_strings` is typed `Map<KdbxKey, StringValue?>`, which reads as though
      // a stored null were a third state. It is not: `setString` with null
      // deletes the entry (kdbx 2.5.0 `kdbx_entry.dart:341-352`, where
      // `removeString` is literally an alias for it). Pinned because the
      // adapter's own `?? \'\'` invites the opposite conclusion.
      localEntry.setString(KdbxKey('Custom_Null'), PlainValue('x'));
      localEntry.setString(KdbxKey('Custom_Null'), null);

      expect(
        run().fieldDiffs.where((d) => d.canonicalKey == 'custom_null'),
        isEmpty,
      );
    });

    test('the null-StringValue branch is defensive only, and yields present '
        'empty if it is ever reached', () {
      // The nullable type is reachable from the type system and from nothing
      // else: the XML reader always constructs a `PlainValue`
      // (`kdbx_entry.dart:187-197`) and `setString` cannot store a null. The
      // branch is covered directly rather than through a vault that cannot
      // produce it.
      final present = KdbxFieldPresent.string(null);
      expect(present.isPresent, isTrue);
      expect(present.semanticValue, '');
      expect(present.isProtected, isFalse);
    });

    test('an empty value survives a round trip as a present empty string, so '
        'the in-memory states collapse after persistence', () async {
      localEntry.setString(KdbxKey('Custom_Empty2'), PlainValue(''));
      final reopened = await adapter.openSide(
        bytes: Uint8List.fromList(await local.save()),
        credentials: credentials,
      );

      final stored = reopened.body.rootGroup
          .getAllEntries()
          .firstWhere((e) => e.uuid.uuid == _sharedEntryUuid)
          .getString(KdbxKey('Custom_Empty2'));
      expect(stored, isNotNull, reason: '<Value/> reads back as PlainValue');
      expect(stored!.getText(), '');

      final field = _diffFor(
        adapter.diffPresence(
          adapter.validatePair(local: reopened, remote: remote),
        ),
        KdbxMergeFieldKind.string,
        'Custom_Empty2',
      );
      expect(field.classification, KdbxFieldClassification.fieldLocalOnly);
      expect((field.local as KdbxFieldPresent).semanticValue, '');
    });

    test('a local-only attachment is fieldLocalOnly', () {
      localEntry.createBinary(
        isProtected: true,
        name: 'local-only.bin',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      final field = _diffFor(
        run(),
        KdbxMergeFieldKind.attachment,
        'local-only.bin',
      );
      expect(field.classification, KdbxFieldClassification.fieldLocalOnly);
      expect((field.local as KdbxFieldPresent).isProtected, isTrue);
      expect(field.remote, isA<KdbxFieldMissing>());
    });

    test('a remote-only attachment is fieldRemoteOnly', () {
      remoteEntry.createBinary(
        isProtected: false,
        name: 'remote-only.bin',
        bytes: Uint8List.fromList([4, 5]),
      );

      expect(
        _diffFor(
          run(),
          KdbxMergeFieldKind.attachment,
          'remote-only.bin',
        ).classification,
        KdbxFieldClassification.fieldRemoteOnly,
      );
    });

    test('a zero-byte attachment is PRESENT, not missing', () {
      localEntry.createBinary(
        isProtected: false,
        name: 'zero.bin',
        bytes: Uint8List(0),
      );

      final field = _diffFor(run(), KdbxMergeFieldKind.attachment, 'zero.bin');
      expect(field.classification, KdbxFieldClassification.fieldLocalOnly);
      expect(field.local.isPresent, isTrue);
      expect((field.local as KdbxFieldPresent).length, 0);
    });

    test('equal attachment name with different bytes is a conflict', () {
      localEntry.createBinary(
        isProtected: false,
        name: 'payload.bin',
        bytes: Uint8List.fromList([1, 1, 1]),
      );
      remoteEntry.createBinary(
        isProtected: false,
        name: 'payload.bin',
        bytes: Uint8List.fromList([2, 2, 2]),
      );

      final field = _diffFor(
        run(),
        KdbxMergeFieldKind.attachment,
        'payload.bin',
      );
      expect(field.classification, KdbxFieldClassification.fieldConflict);
      expect(
        (field.local as KdbxFieldPresent).semanticValue,
        isNot((field.remote as KdbxFieldPresent).semanticValue),
      );
    });

    test('equal attachment name with equal bytes is identical', () {
      final bytes = Uint8List.fromList([7, 7, 7]);
      localEntry.createBinary(
        isProtected: false,
        name: 'same.bin',
        bytes: bytes,
      );
      remoteEntry.createBinary(
        isProtected: false,
        name: 'same.bin',
        bytes: Uint8List.fromList(bytes),
      );

      expect(
        _diffFor(
          run(),
          KdbxMergeFieldKind.attachment,
          'same.bin',
        ).classification,
        KdbxFieldClassification.identical,
      );
    });

    test('an attachment differing only in protection is a conflict', () {
      final bytes = Uint8List.fromList([9]);
      localEntry.createBinary(
        isProtected: false,
        name: 'prot.bin',
        bytes: bytes,
      );
      remoteEntry.createBinary(
        isProtected: true,
        name: 'prot.bin',
        bytes: Uint8List.fromList(bytes),
      );

      expect(
        _diffFor(
          run(),
          KdbxMergeFieldKind.attachment,
          'prot.bin',
        ).classification,
        KdbxFieldClassification.fieldConflict,
      );
    });

    test('a string key and an attachment sharing a name are two fields', () {
      localEntry.setString(KdbxKey('shadow'), PlainValue('a string'));
      remoteEntry.createBinary(
        isProtected: false,
        name: 'shadow',
        bytes: Uint8List.fromList([0]),
      );

      final diff = run();
      expect(
        _diffFor(diff, KdbxMergeFieldKind.string, 'shadow').classification,
        KdbxFieldClassification.fieldLocalOnly,
      );
      expect(
        _diffFor(diff, KdbxMergeFieldKind.attachment, 'shadow').classification,
        KdbxFieldClassification.fieldRemoteOnly,
      );
    });

    test('the original key spelling survives verbatim, case included', () {
      localEntry.setString(KdbxKey('Custom_TOTP Seed'), PlainValue('x'));

      final field = _diffFor(
        run(),
        KdbxMergeFieldKind.string,
        'Custom_TOTP Seed',
      );
      // The canonical key is the match key; the verbatim spelling is preserved
      // as payload, per side (FR-1 "original key spelling").
      expect(field.canonicalKey, 'custom_totp seed');
      expect(field.localKey, 'Custom_TOTP Seed');
      expect(field.remoteKey, isNull);
    });

    test('missing on both sides emits no field at all', () {
      expect(
        run().fieldDiffs.where((d) => d.canonicalKey == 'custom_nowhere'),
        isEmpty,
      );
    });

    test('one-sided fields are counted for the redacted review summary', () {
      localEntry.setString(KdbxKey('Custom_L'), PlainValue('l'));
      remoteEntry.setString(KdbxKey('Custom_R'), PlainValue('r'));
      localEntry.createBinary(
        isProtected: false,
        name: 'l.bin',
        bytes: Uint8List(0),
      );

      expect(run().oneSidedFieldCount, 3);
    });

    test('the diff is deterministic and side-symmetric in its key set, so two '
        'devices produce the same evidence', () {
      localEntry.setString(KdbxKey('b'), PlainValue('1'));
      remoteEntry.setString(KdbxKey('a'), PlainValue('2'));

      final forward = run().fieldDiffs.map(
        (d) => '${d.fieldKind}:${d.canonicalKey}',
      );
      final reversed = adapter
          .diffPresence(adapter.validatePair(local: remote, remote: local))
          .fieldDiffs
          .map((d) => '${d.fieldKind}:${d.canonicalKey}');

      expect(forward, orderedEquals(reversed.toList()));
    });

    test('fields of a one-sided entry are not field decisions — the whole '
        'record is an automatic union member', () {
      final localOnly = KdbxEntry.create(local, local.body.rootGroup);
      local.body.rootGroup.addEntry(localOnly);
      localOnly.setString(KdbxKeyCommon.TITLE, PlainValue('Local Only'));

      final diff = run();
      expect(diff.localOnlyEntryUuids, contains(localOnly.uuid.uuid));
      expect(
        diff.fieldDiffs.where((d) => d.entryUuid == localOnly.uuid.uuid),
        isEmpty,
      );
    });

    test('a one-sided group is a record-level union member', () {
      final group = remote.createGroup(
        parent: remote.body.rootGroup,
        name: 'Remote Only Group',
      );

      final diff = run();
      expect(diff.remoteOnlyGroupUuids, contains(group.uuid.uuid));
      expect(diff.localOnlyGroupUuids, isEmpty);
    });
  });

  // ===========================================================================
  // Coherence with the T009/T009b convergence models.
  //
  // Those models prove the merge converges GIVEN a presence model in which
  // absence is never deletion evidence and an empty value is a value. The
  // adapter is the thing that supplies that model, so what it owes them is the
  // shape, not a second convergence proof.
  // ===========================================================================
  group('coherence with the T009/T009b convergence models', () {
    test('a missing field never classifies as deletion evidence', () {
      final pair = _replicaPair(credentials);
      _sharedEntry(pair.local).setString(KdbxKey('gone'), PlainValue('v'));

      final diff = adapter.diffPresence(
        adapter.validatePair(local: pair.local, remote: pair.remote),
      );

      // T009b's premise: a delete requires a tombstone. KDBX has none per
      // field, so every classification the adapter can emit is a union or a
      // value conflict — asserted over the whole enum, so a future member
      // added without deletion evidence breaks this test rather than silently
      // deleting a field.
      expect(
        diff.fieldDiffs.map((d) => d.classification).toSet(),
        everyElement(
          isIn(const [
            KdbxFieldClassification.identical,
            KdbxFieldClassification.fieldConflict,
            KdbxFieldClassification.fieldLocalOnly,
            KdbxFieldClassification.fieldRemoteOnly,
          ]),
        ),
      );
      expect(KdbxFieldClassification.values, hasLength(4));
    });

    test('an entry live on one side and absent on the other is preserved as '
        'one-sided, never inferred deleted', () {
      final pair = _replicaPair(credentials);
      final onlyLocal = KdbxEntry.create(pair.local, pair.local.body.rootGroup);
      pair.local.body.rootGroup.addEntry(onlyLocal);

      final diff = adapter.diffPresence(
        adapter.validatePair(local: pair.local, remote: pair.remote),
      );

      expect(diff.localOnlyEntryUuids, contains(onlyLocal.uuid.uuid));
    });
  });
}
