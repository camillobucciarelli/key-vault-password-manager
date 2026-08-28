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
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
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

/// Emits a tombstone for [uuid] in [file] carrying exactly [deletedAt].
void _stampTombstone(KdbxFile file, KdbxUuid uuid, DateTime deletedAt) {
  file.ctx.addDeletedObject(uuid);
  // ignore: invalid_use_of_visible_for_testing_member
  file.body.deletedObjects
      .firstWhere((o) => o.uuid == uuid)
      .deletionTime
      .set(deletedAt);
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

/// FR-3a's default block choice, computed the same way a real caller (the
/// repository) would — via [compareCredentialBlockImage], not a hardcoded
/// literal — so tests that use this exercise the real comparator.
MergeChoice _defaultBlockChoiceOf(KdbxPresenceDiff diff, String entryUuid) {
  final fields = credentialBlockFieldsOf(diff, entryUuid);
  final localImage = <String, KdbxFieldPresent>{
    for (final f in fields)
      if (f.local is KdbxFieldPresent)
        f.canonicalKey: f.local as KdbxFieldPresent,
  };
  final remoteImage = <String, KdbxFieldPresent>{
    for (final f in fields)
      if (f.remote is KdbxFieldPresent)
        f.canonicalKey: f.remote as KdbxFieldPresent,
  };
  return compareCredentialBlockImage(localImage, remoteImage) >= 0
      ? MergeChoice.local
      : MergeChoice.remote;
}

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
  // T308 — FR-5 record-level deletion evidence.
  //
  // The whole group exists because of one fact about this app: deleting an
  // entry MOVES IT TO THE RECYCLE BIN. So the "deleted" record is still a live
  // object in the KDBX tree — shared with the other side, with fields that keep
  // diffing — and the bin group shows up as an ordinary one-sided group. The
  // presence sets say nothing about any of it, which is why bin membership is
  // re-derived from the tree here rather than read off a UUID difference.
  // ===========================================================================
  group('T308 record deletion evidence', () {
    KdbxRecordDiff recordFor(KdbxPresenceDiff diff, String uuid) =>
        diff.recordDiffs.singleWhere((r) => r.objectUuid == uuid);

    KdbxPresenceDiff run(KdbxFile local, KdbxFile remote) => adapter
        .diffPresence(adapter.validatePair(local: local, remote: remote));

    test('an entry binned on one side and live on the other is a deletion '
        'conflict, not a shared record with field conflicts', () {
      final pair = _replicaPair(credentials);
      // Diverge the fields too: without the bin, this pair would produce a
      // perfectly ordinary field conflict, which is exactly the failure mode —
      // the user would be asked to pick a username for a record they deleted.
      _sharedEntry(
        pair.local,
      ).setString(KdbxKeyCommon.USER_NAME, PlainValue('changed-locally'));
      KdbxDao(pair.remote).deleteEntry(_sharedEntry(pair.remote));

      final diff = run(pair.local, pair.remote);
      final record = recordFor(diff, _sharedEntryUuid);

      expect(
        record.classification,
        KdbxRecordClassification.recordDeletionConflict,
      );
      expect(record.local.evidence, KdbxRecordEvidence.live);
      expect(record.remote.evidence, KdbxRecordEvidence.recycled);
      expect(
        diff.fieldDiffs.where((d) => d.entryUuid == _sharedEntryUuid),
        isEmpty,
        reason:
            'the existence of the record is what is being decided; its fields '
            'are not a separate question',
      );
      expect(diff.deletionConflicts, hasLength(1));
    });

    test('the recycle-bin GROUP is an ordinary one-sided union, not a deleted '
        'record', () {
      // The bin is a container the other side has never seen. Preserving it is
      // FR-1; classifying it as deleted would drop everything inside it.
      final pair = _replicaPair(credentials);
      KdbxDao(pair.remote).deleteEntry(_sharedEntry(pair.remote));
      final binUuid = pair.remote.recycleBin!.uuid.uuid;

      final diff = run(pair.local, pair.remote);

      expect(
        recordFor(diff, binUuid).classification,
        KdbxRecordClassification.recordRemoteOnly,
      );
      expect(diff.remoteOnlyGroupUuids, contains(binUuid));
    });

    test('binned on BOTH sides is deleted, and asks the user nothing', () {
      final pair = _replicaPair(credentials);
      KdbxDao(pair.local).deleteEntry(_sharedEntry(pair.local));
      KdbxDao(pair.remote).deleteEntry(_sharedEntry(pair.remote));

      final diff = run(pair.local, pair.remote);

      expect(
        recordFor(diff, _sharedEntryUuid).classification,
        KdbxRecordClassification.recordDeleted,
      );
      expect(diff.deletionConflicts, isEmpty);
    });

    test('a permanent tombstone NEWER than the live side is a deletion '
        'conflict', () {
      final pair = _replicaPair(credentials);
      _sharedEntry(
        pair.local,
      ).times.lastModificationTime.set(DateTime.utc(2020));
      KdbxDao(pair.remote).deletePermanently(_sharedEntry(pair.remote));

      final record = recordFor(run(pair.local, pair.remote), _sharedEntryUuid);
      expect(
        record.classification,
        KdbxRecordClassification.recordDeletionConflict,
      );
      expect(record.remote.evidence, KdbxRecordEvidence.tombstoned);
    });

    test('a tombstone OLDER than the live side is superseded: the record is a '
        'one-sided union, not a deletion (T009b G1)', () {
      // Proof of life after the delete. The data-preserving reading, and the
      // one the deletion-convergence model was validated against — a tombstone
      // that outranked a later edit would delete work the user did after it.
      final pair = _replicaPair(credentials);
      KdbxDao(pair.remote).deletePermanently(_sharedEntry(pair.remote));
      _sharedEntry(
        pair.local,
      ).times.lastModificationTime.set(DateTime.utc(2099));

      final record = recordFor(run(pair.local, pair.remote), _sharedEntryUuid);
      expect(record.classification, KdbxRecordClassification.recordLocalOnly);
      expect(record.remote.evidence, KdbxRecordEvidence.tombstoned);
    });

    test('an EQUAL clock breaks toward preservation (T009b G3)', () {
      final pair = _replicaPair(credentials);
      KdbxDao(pair.remote).deletePermanently(_sharedEntry(pair.remote));
      // ignore: invalid_use_of_visible_for_testing_member
      final deletedAt = pair.remote.body.deletedObjects.single.deletionTime
          .get()!;
      _sharedEntry(pair.local).times.lastModificationTime.set(deletedAt);

      expect(
        recordFor(
          run(pair.local, pair.remote),
          _sharedEntryUuid,
        ).classification,
        KdbxRecordClassification.recordLocalOnly,
        reason: 'the tie must not delete; G2 relies on exactly this',
      );
    });

    test(
      'plain absence is never deletion evidence, whatever the clocks say',
      () {
        final pair = _replicaPair(credentials);
        final localOnly = KdbxEntry.create(
          pair.local,
          pair.local.body.rootGroup,
        )..forceSetUuid(KdbxUuid.random());
        pair.local.body.rootGroup.addEntry(localOnly);
        localOnly.times.lastModificationTime.set(DateTime.utc(2000));

        final diff = run(pair.local, pair.remote);
        expect(
          recordFor(diff, localOnly.uuid.uuid).classification,
          KdbxRecordClassification.recordLocalOnly,
        );
        expect(diff.deletionConflicts, isEmpty);
      },
    );

    test('the classification set is closed, so a new member cannot arrive '
        'without a decision about what it means', () {
      expect(KdbxRecordClassification.values, hasLength(5));
      expect(KdbxRecordEvidence.values, hasLength(4));
    });
  });

  // ===========================================================================
  // T303 — the redaction of the data layer's own `toString`s.
  //
  // The T303 tests elsewhere cover the port's SURFACE, which is the domain
  // boundary. They say nothing about the types on this side of it, and those
  // are the ones holding decrypted values: `KdbxFieldPresent.semanticValue` is
  // plaintext, and `toString` is what an interpolation into a log line, an
  // error message or a crash report calls. Rewriting any of these to
  // interpolate its own state used to break no test at all — the classes
  // asserted the property in prose ("Deliberately redacted. This object holds a
  // decrypted value.") and nothing enforced it.
  // ===========================================================================
  group('T303 data-layer toString redaction', () {
    // Classes whose `toString` must be a constant literal that says
    // "redacted": each one can reach a decrypted value, directly or through a
    // field.
    const guarded = <String>[
      'KdbxFieldPresent',
      'KdbxFieldDiff',
      'KdbxRecordSide',
      'KdbxRecordDiff',
      'KdbxPresenceDiff',
      'KdbxMergeSide',
      'KdbxMergePair',
      'KdbxMergeResolution',
    ];

    // Holds nothing at all, so its `toString` may name its own type — but it
    // must still be a constant literal, or a future field arrives with an
    // interpolation already in place.
    const constantOnly = <String>['KdbxFieldMissing'];

    late CompilationUnit unit;

    setUpAll(() {
      const path =
          'lib/features/password_manager/data/services/kdbx_merge_adapter.dart';
      unit = parseString(
        content: File(path).readAsStringSync(),
        path: path,
      ).unit;
    });

    test('every type that can hold decrypted data declares a toString that '
        'returns a constant literal', () {
      for (final name in [...guarded, ...constantOnly]) {
        final declaration = unit.declarations
            .whereType<ClassDeclaration>()
            .singleWhere(
              (d) => d.namePart.typeName.lexeme == name,
              orElse: () => throw StateError('no class "$name"'),
            );
        final toString = declaration.body.members
            .whereType<MethodDeclaration>()
            .where((m) => m.name.lexeme == 'toString');

        expect(
          toString,
          hasLength(1),
          reason:
              '$name has no toString, so it falls back to the default — which '
              'is safe today and silently stops being safe the moment someone '
              'adds one. Declare it explicitly.',
        );

        final body = toString.single.body;
        expect(
          body,
          isA<ExpressionFunctionBody>(),
          reason: '$name.toString must be a single expression',
        );
        final expression = (body as ExpressionFunctionBody).expression;
        expect(
          expression,
          isA<SimpleStringLiteral>(),
          reason:
              '$name.toString returns ${expression.runtimeType}. Only a '
              'constant literal is allowed: an interpolation is how a '
              'decrypted value reaches a log line, and it is one character '
              'away at all times.',
        );
        if (guarded.contains(name)) {
          expect(
            (expression as SimpleStringLiteral).value,
            contains('redacted'),
            reason: '$name.toString must say it is redacted',
          );
        }
      }
    });

    test('the guarded list covers every class in the file that is not a pure '
        'enum or a value-free marker', () {
      // Fail-closed: a NEW class in the adapter is a violation until someone
      // decides it belongs on the list or argues why it does not.
      const exempt = <String>{
        // Stateless.
        'KdbxMergeAdapter',
        // The sealed base of the presence pair: no fields, and both of its
        // subclasses are covered above.
        'KdbxFieldPresence',
      };
      final declared = unit.declarations
          .whereType<ClassDeclaration>()
          .map((d) => d.namePart.typeName.lexeme)
          .where((name) => !name.startsWith('_'))
          .toSet();

      expect(
        declared.difference({...guarded, ...constantOnly, ...exempt}),
        isEmpty,
        reason:
            'a new public class in the merge adapter is not covered by the '
            'toString guard. Add it to `guarded`, or to `exempt` with a reason '
            '— it holds no data worth redacting.',
      );
    });

    test('a redacted toString actually redacts, at runtime', () {
      // The source rules above are structural; this is the property itself, so
      // the two cannot both be satisfied by a clever literal.
      const secret = 'plaintext-that-must-not-appear';
      final present = KdbxFieldPresent(
        semanticValue: secret,
        isProtected: true,
        length: secret.length,
      );

      expect(present.toString(), isNot(contains(secret)));
      expect(present.semanticValue, secret, reason: 'still readable in data/');
    });
  });

  // ===========================================================================
  // T309 / FR-1 — the serialization-parity gate.
  //
  // This group exists because the gate had no test at all: deleting
  // `serializeCandidate` outright left the whole suite green, so the last
  // defence before the bytes that will replace a vault was indistinguishable
  // from a no-op. Both of its refusal branches are exercised here — the reopen
  // that fails, and the reopen that succeeds while the MANIFEST does not
  // survive, which is the half a credentials test can never reach.
  // ===========================================================================
  group('T309 serialization parity gate', () {
    test('a candidate that does not reopen with the given credentials is '
        'serializationParityFailed', () async {
      final candidate = _buildSide(credentials);

      await expectLater(
        adapter.serializeCandidate(
          candidate: candidate,
          credentials: Credentials(ProtectedValue.fromString('other-pw')),
        ),
        _failsWith(MergeFailureCode.serializationParityFailed),
      );
    });

    test('a candidate that reopens but whose MANIFEST does not survive is '
        'also serializationParityFailed', () async {
      // The failure a credentials check can never see: the file opens
      // perfectly and its CONTENT changed in transit.
      //
      // The vehicle is the one path that produces a null `StringValue`, which
      // this adapter's own documentation calls out: `KdbxEntry.renameKey` with
      // an absent `oldKey` writes `_strings[newKey] = null` with no guard
      // (kdbx 2.5.0). In memory that key holds null; serialized it becomes
      // `<Value/>` and reads back as a present EMPTY string. So a buggy apply
      // step that renamed a key that was not there would invent a field out of
      // nothing, the vault would open, and only the manifest comparison would
      // notice. FR-4 spends a whole row on empty-versus-missing precisely
      // because the two are not the same thing.
      final candidate = _buildSide(credentials);
      _sharedEntry(candidate).renameKey(KdbxKey('Absent'), KdbxKey('Ghost'));

      // It really does open — so the credentials branch cannot be what
      // rejects it, and this test cannot pass for the previous test's reason.
      final bytes = Uint8List.fromList(await candidate.save());
      final reopened = await KdbxFormat().read(bytes, credentials);
      expect(
        _sharedEntry(candidate).getString(KdbxKey('Ghost')),
        isNull,
        reason: 'in memory the key holds a null StringValue',
      );
      expect(
        reopened.body.rootGroup
            .getAllEntries()
            .firstWhere((e) => e.uuid.uuid == _sharedEntryUuid)
            .getString(KdbxKey('Ghost'))
            ?.getText(),
        '',
        reason: 'on disk it is a present empty string — a different fact',
      );

      await expectLater(
        adapter.serializeCandidate(
          candidate: candidate,
          credentials: credentials,
        ),
        _failsWith(MergeFailureCode.serializationParityFailed),
      );
    });

    test(
      'a consistent candidate passes and returns bytes that reopen',
      () async {
        // The positive control: without it the two refusals above would also
        // pass on a gate that refused everything.
        final candidate = _buildSide(credentials);

        final bytes = await adapter.serializeCandidate(
          candidate: candidate,
          credentials: credentials,
        );
        final reopened = await KdbxFormat().read(bytes, credentials);
        expect(reopened.body.rootGroup.uuid, candidate.body.rootGroup.uuid);
      },
    );
  });

  // ===========================================================================
  // FR-5 — deletion evidence survives the merge with its own clock.
  // ===========================================================================
  group('FR-5 tombstone clock preservation', () {
    test('a tombstone copied from the other side keeps its ORIGINAL deletion '
        'time, never the current clock', () async {
      // `KdbxReadWriteContext.addDeletedObject` declares a `now` parameter and
      // drops it, so every tombstone it emits is stamped with the current
      // clock. Re-stamping a COPIED tombstone is a data-loss defect, not a
      // cosmetic one: under T009b's G1 a tombstone matches when it is strictly
      // newer than the live mtime, so an inflated clock makes the tombstone
      // outrank edits a peer legitimately made after the deletion.
      final pair = _replicaPair(credentials);
      final orphan = KdbxUuid.random();
      final past = DateTime.utc(2001, 2, 3, 4, 5, 6);
      pair.remote.ctx.addDeletedObject(orphan);
      // ignore: invalid_use_of_visible_for_testing_member
      pair.remote.body.deletedObjects
          .firstWhere((o) => o.uuid == orphan)
          .deletionTime
          .set(past);

      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      final candidate = adapter.applyMerge(
        pair: validated,
        diff: adapter.diffPresence(validated),
        resolution: KdbxMergeResolution(),
      );

      expect(tombstonesOf(candidate)[orphan.uuid], past);
      expect(
        tombstonesOf(candidate)[orphan.uuid],
        isNot(
          isA<DateTime>().having((t) => t.year, 'year', DateTime.now().year),
        ),
      );
    });
  });

  // ===========================================================================
  // FR-3 — the DIRECTION of the time join.
  //
  // The commutativity test is blind to this by construction: taking the older
  // time is just as deterministic and just as commutative as taking the newer
  // one, so inverting the comparator survives it. The direction is not
  // cosmetic — an mtime pushed backwards makes T009b's G1 ("a tombstone
  // matches when it is strictly newer than the live mtime") fire more often,
  // which biases the merge toward DELETING. That is the only way this join can
  // be wrong in a damaging direction, and it is the one the other tests miss.
  // ===========================================================================
  group('FR-3 the time join takes the newer side', () {
    test('a merged object carries the NEWER of the two modification times', () {
      final older = DateTime.utc(2020, 5, 1);
      final newer = DateTime.utc(2023, 9, 17);

      ({DateTime? entry, DateTime? group}) mergedTimes({
        required DateTime localAt,
        required DateTime remoteAt,
      }) {
        final pair = _replicaPair(credentials);
        for (final side in [
          (file: pair.local, at: localAt),
          (file: pair.remote, at: remoteAt),
        ]) {
          _sharedEntry(side.file).times.lastModificationTime.set(side.at);
          side.file.body.rootGroup.times.lastModificationTime.set(side.at);
        }
        // Force the merge to actually touch the objects, so the wall clock
        // would otherwise win: a remote-only field on the shared entry, and a
        // remote-only record under the root group.
        _sharedEntry(
          pair.remote,
        ).setString(KdbxKey('Custom_RemoteOnly'), PlainValue('v'));
        _sharedEntry(pair.remote).times.lastModificationTime.set(remoteAt);
        final extra = KdbxEntry.create(pair.remote, pair.remote.body.rootGroup)
          ..forceSetUuid(KdbxUuid.random());
        pair.remote.body.rootGroup.addEntry(extra);
        pair.remote.body.rootGroup.times.lastModificationTime.set(remoteAt);

        final validated = adapter.validatePair(
          local: pair.local,
          remote: pair.remote,
        );
        final candidate = adapter.applyMerge(
          pair: validated,
          diff: adapter.diffPresence(validated),
          resolution: KdbxMergeResolution(),
        );
        return (
          entry: _sharedEntry(candidate).times.lastModificationTime.get(),
          group: candidate.body.rootGroup.times.lastModificationTime.get(),
        );
      }

      final localIsNewer = mergedTimes(localAt: newer, remoteAt: older);
      expect(localIsNewer.entry, newer);
      expect(localIsNewer.group, newer);

      final remoteIsNewer = mergedTimes(localAt: older, remoteAt: newer);
      expect(remoteIsNewer.entry, newer);
      expect(remoteIsNewer.group, newer);
    });
  });

  // ===========================================================================
  // FR-1 — metadata is MERGED, not taken from whichever side is the base.
  //
  // The candidate is built from the local file, and for a while that quietly
  // meant the local side won every metadata field unconditionally: a database
  // renamed on one device lost its name after a merge on the other, with no
  // conflict, no decision, no summary row and no refusal. The evidence FR-3
  // needs does exist — KDBX stores a change clock beside each of these fields
  // — so this is resolved automatically, exactly like a value conflict with
  // two known timestamps.
  // ===========================================================================
  group('FR-1 metadata merge', () {
    KdbxFile mergeOf(KdbxFile local, KdbxFile remote) {
      final validated = adapter.validatePair(local: local, remote: remote);
      return adapter.applyMerge(
        pair: validated,
        diff: adapter.diffPresence(validated),
        resolution: KdbxMergeResolution(),
      );
    }

    test('a newer remote rename survives the merge instead of vanishing', () {
      final pair = _replicaPair(credentials);
      final older = DateTime.utc(2020);
      final newer = DateTime.utc(2021);

      pair.local.body.meta
        ..databaseName.set('QA')
        ..databaseNameChanged.set(older)
        ..databaseDescription.set('')
        ..databaseDescriptionChanged.set(older)
        ..defaultUserName.set('')
        ..defaultUserNameChanged.set(older)
        ..historyMaxItems.set(20)
        ..settingsChanged.set(older);
      pair.remote.body.meta
        ..databaseName.set('RENAMED-ON-REMOTE')
        ..databaseNameChanged.set(newer)
        ..databaseDescription.set('DESCRIPTION-ONLY-ON-REMOTE')
        ..databaseDescriptionChanged.set(newer)
        ..defaultUserName.set('remote-default-user')
        ..defaultUserNameChanged.set(newer)
        ..historyMaxItems.set(42)
        ..settingsChanged.set(newer);
      pair.remote.body.meta.customData['qa-key'] = 'qa-remote-value';

      final meta = mergeOf(pair.local, pair.remote).body.meta;

      expect(meta.databaseName.get(), 'RENAMED-ON-REMOTE');
      expect(meta.databaseNameChanged.get(), newer);
      expect(meta.databaseDescription.get(), 'DESCRIPTION-ONLY-ON-REMOTE');
      expect(meta.defaultUserName.get(), 'remote-default-user');
      expect(meta.historyMaxItems.get(), 42);
      expect(meta.customData['qa-key'], 'qa-remote-value');
    });

    test('an OLDER remote value does not overwrite the local one', () {
      // The direction matters: a merge that always took the remote side would
      // pass the test above and destroy local edits instead of remote ones.
      final pair = _replicaPair(credentials);
      pair.local.body.meta
        ..databaseName.set('NEWER-LOCAL')
        ..databaseNameChanged.set(DateTime.utc(2021));
      pair.remote.body.meta
        ..databaseName.set('OLDER-REMOTE')
        ..databaseNameChanged.set(DateTime.utc(2020));

      final meta = mergeOf(pair.local, pair.remote).body.meta;

      expect(meta.databaseName.get(), 'NEWER-LOCAL');
      expect(meta.databaseNameChanged.get(), DateTime.utc(2021));
    });

    test('the metadata merge is commutative, clocks included', () {
      String render(KdbxMeta meta) => [
        meta.databaseName.get(),
        meta.databaseNameChanged.get(),
        meta.databaseDescription.get(),
        meta.defaultUserName.get(),
        meta.historyMaxItems.get(),
        meta.settingsChanged.get(),
        meta.customData['shared-key'],
      ].join('|');

      void diverge(KdbxFile a, KdbxFile b) {
        a.body.meta
          ..databaseName.set('side-a')
          ..databaseNameChanged.set(DateTime.utc(2021))
          ..historyMaxItems.set(11)
          ..settingsChanged.set(DateTime.utc(2020));
        a.body.meta.customData['shared-key'] = 'from-a';
        b.body.meta
          ..databaseName.set('side-b')
          ..databaseNameChanged.set(DateTime.utc(2020))
          ..historyMaxItems.set(22)
          ..settingsChanged.set(DateTime.utc(2021));
        b.body.meta.customData['shared-key'] = 'from-b';
      }

      final forward = _replicaPair(credentials);
      diverge(forward.local, forward.remote);
      final mirrored = _replicaPair(credentials);
      diverge(mirrored.remote, mirrored.local);

      expect(
        render(mergeOf(forward.local, forward.remote).body.meta),
        render(mergeOf(mirrored.local, mirrored.remote).body.meta),
      );
    });

    test(
      'an exact clock tie is broken by the value, not by the perspective',
      () {
        final tie = DateTime.utc(2021, 6, 1);

        KdbxFile merged({required String local, required String remote}) {
          final pair = _replicaPair(credentials);
          pair.local.body.meta
            ..databaseName.set(local)
            ..databaseNameChanged.set(tie);
          pair.remote.body.meta
            ..databaseName.set(remote)
            ..databaseNameChanged.set(tie);
          return mergeOf(pair.local, pair.remote);
        }

        expect(
          merged(local: 'alpha', remote: 'zulu').body.meta.databaseName.get(),
          'zulu',
        );
        expect(
          merged(local: 'zulu', remote: 'alpha').body.meta.databaseName.get(),
          'zulu',
        );
      },
    );

    test('a side with NO recycle bin adopts the other side\'s, so the imported '
        'bin group is not left orphaned in the normal tree', () {
      // The functional half of the bug, not just a convergence one: without
      // this the bin group arrives as a one-sided union while `recycleBinUUID`
      // stays null, so the user sees a group full of deleted entries in the
      // ordinary tree — and the next delete creates a SECOND bin beside it.
      final pair = _replicaPair(credentials);
      expect(pair.local.body.meta.recycleBinUUID.get(), isNull);

      // A record the local side has never seen, which the remote created and
      // then deleted. It is a one-sided union that happens to live in the bin,
      // NOT a deletion conflict — so it arrives with its container.
      final doomed = KdbxEntry.create(pair.remote, pair.remote.body.rootGroup)
        ..forceSetUuid(KdbxUuid.random());
      pair.remote.body.rootGroup.addEntry(doomed);
      doomed.setString(KdbxKeyCommon.TITLE, PlainValue('Remote Only'));
      KdbxDao(pair.remote).deleteEntry(doomed);
      final remoteBin = pair.remote.recycleBin!.uuid;

      final candidate = mergeOf(pair.local, pair.remote);

      expect(candidate.body.meta.recycleBinUUID.get(), remoteBin);
      expect(candidate.recycleBin, isNotNull);
      expect(candidate.recycleBin!.uuid, remoteBin);
      // ...and the adopted bin really is the imported group, so the deleted
      // record is inside it rather than loose in the ordinary tree.
      expect(
        candidate.recycleBin!.getAllEntries().map((e) => e.uuid.uuid),
        contains(doomed.uuid.uuid),
      );
    });

    test('custom icons the remote holds for records that never moved are '
        'carried over, not only the ones an imported record references', () {
      final pair = _replicaPair(credentials);
      final icon = KdbxCustomIcon(
        uuid: KdbxUuid.random(),
        data: Uint8List.fromList(const [7, 7, 7]),
      );
      pair.remote.body.meta.addCustomIcon(icon);

      final candidate = mergeOf(pair.local, pair.remote);

      expect(candidate.body.meta.customIcons, contains(icon.uuid));
    });

    // MEDIUM-5 (Gate 3 residual). The recycle-bin block adopts the enabled
    // flag, the UUID and the clock together because all three hang off
    // `RecycleBinChanged`; the comment said so and nothing asserted it. The
    // mutant "adopt the UUID, keep the local flag" survived the whole suite.
    //
    // What it costs, precisely — the damage is NOT inside this app: neither
    // `KdbxDao.deleteEntry` nor any code here reads `RecycleBinEnabled`, so a
    // delete still lands in the bin locally. It costs (a) a permanent
    // `/meta/recycleBinEnabled` divergence between the two devices, which is a
    // manifest key FR-7 step 5 arbitrates on, and (b) correctness in every
    // other KDBX client: KeePass and KeePassXC do honour the flag, so a vault
    // carrying a valid `RecycleBinUUID` with `RecycleBinEnabled` false deletes
    // permanently there.
    test('the recycle-bin flag, UUID and clock move as ONE unit', () {
      final older = DateTime.utc(2020);
      final newer = DateTime.utc(2021);
      final remoteBin = KdbxUuid.random();

      final pair = _replicaPair(credentials);
      // Order matters in the fixture for the same reason it matters in the
      // implementation: `recycleBinUUID` stamps `recycleBinChanged` to NOW on
      // every write, so the clock is set last on both sides.
      pair.local.body.meta
        ..recycleBinEnabled.set(false)
        ..recycleBinChanged.set(older);
      pair.remote.body.meta
        ..recycleBinEnabled.set(true)
        ..recycleBinUUID.set(remoteBin)
        ..recycleBinChanged.set(newer);

      final meta = mergeOf(pair.local, pair.remote).body.meta;

      expect(meta.recycleBinUUID.get(), remoteBin);
      // The half the mutant drops. Without it the merged side keeps `false`
      // while the other side holds `true`, forever.
      expect(meta.recycleBinEnabled.get(), isTrue);
      expect(meta.recycleBinChanged.get(), newer);
    });

    test('the recycle-bin block is atomic in the LOSING direction too: an '
        'older remote moves neither the flag nor the UUID', () {
      final older = DateTime.utc(2020);
      final newer = DateTime.utc(2021);
      final localBin = KdbxUuid.random();

      final pair = _replicaPair(credentials);
      pair.local.body.meta
        ..recycleBinEnabled.set(true)
        ..recycleBinUUID.set(localBin)
        ..recycleBinChanged.set(newer);
      pair.remote.body.meta
        ..recycleBinEnabled.set(false)
        ..recycleBinUUID.set(KdbxUuid.random())
        ..recycleBinChanged.set(older);

      final meta = mergeOf(pair.local, pair.remote).body.meta;

      expect(meta.recycleBinUUID.get(), localBin);
      expect(meta.recycleBinEnabled.get(), isTrue);
      expect(meta.recycleBinChanged.get(), newer);
    });

    // MEDIUM-6 (Gate 3 residual). "A known clock beats an unknown one" is
    // FR-3's rule 2 and lived only in a doc comment. Inverting it keeps the
    // join commutative — which is exactly why the commutativity test is blind
    // to it — while electing the side that never set the field: a real user
    // edit discarded in favour of a value nobody chose, the same damage
    // direction as HIGH-5.
    //
    // The two values are picked so the rule-3 byte fallback would elect the
    // OPPOSITE side. That makes the assertion kill two mutants, not one: the
    // inversion, and a deletion of both branches that lets an unknown clock
    // fall through to the value order.
    test('a known clock beats an unknown one, whichever side holds it', () {
      final clock = DateTime.utc(2021);

      KdbxMeta merged({
        required String localName,
        required DateTime? localAt,
        required String remoteName,
        required DateTime? remoteAt,
      }) {
        final pair = _replicaPair(credentials);
        pair.local.body.meta
          ..databaseName.set(localName)
          ..databaseNameChanged.set(localAt);
        pair.remote.body.meta
          ..databaseName.set(remoteName)
          ..databaseNameChanged.set(remoteAt);
        return mergeOf(pair.local, pair.remote).body.meta;
      }

      // Local holds the only clock. Its value sorts BELOW the remote's, so a
      // fall-through to rule 3 would elect 'zzz-never-set'.
      final localKnown = merged(
        localName: 'aaa-set-by-the-user',
        localAt: clock,
        remoteName: 'zzz-never-set',
        remoteAt: null,
      );
      expect(localKnown.databaseName.get(), 'aaa-set-by-the-user');
      expect(localKnown.databaseNameChanged.get(), clock);

      // Mirrored: remote holds the only clock, and again its value is the one
      // rule 3 would reject.
      final remoteKnown = merged(
        localName: 'zzz-never-set',
        localAt: null,
        remoteName: 'aaa-set-by-the-user',
        remoteAt: clock,
      );
      expect(remoteKnown.databaseName.get(), 'aaa-set-by-the-user');
      expect(remoteKnown.databaseNameChanged.get(), clock);
    });

    // LOW-5 (Gate 3 residual). The pre-capture of `localSettingsAt` /
    // `remoteSettingsAt` was called a precaution because nobody had shown it
    // non-commutative. It is NOT a precaution: it is load-bearing, and this is
    // the case that proves it.
    //
    // `customData` has no per-key clock, so it resolves on `SettingsChanged` —
    // the same clock the settings block above it OVERWRITES when the remote
    // wins. Read inline instead of pre-captured, the loop then sees
    // `localAt == remoteAt`, mistakes a decided comparison for a tie, and
    // drops to the rule-3 byte order. The local value here is the byte-greater
    // one, so the tie-break elects it and the newer remote edit is lost — and
    // the mirrored merge, where the settings block does NOT fire, keeps its own
    // side instead. Two devices, two answers, forever.
    test('customData resolves on the settings clocks as they were BEFORE the '
        'settings block overwrote them', () {
      final older = DateTime.utc(2020);
      final newer = DateTime.utc(2021);

      // 'zzz' sorts above 'aaa', so rule 3 alone would elect the local side.
      // Rule 1 must elect the remote one: its `SettingsChanged` is newer.
      void diverge(KdbxFile stale, KdbxFile fresh) {
        stale.body.meta
          ..historyMaxItems.set(10)
          ..settingsChanged.set(older);
        stale.body.meta.customData['shared-key'] = 'zzz-from-the-stale-side';
        fresh.body.meta
          ..historyMaxItems.set(99)
          ..settingsChanged.set(newer);
        fresh.body.meta.customData['shared-key'] = 'aaa-from-the-fresh-side';
      }

      final forward = _replicaPair(credentials);
      diverge(forward.local, forward.remote);
      final mirrored = _replicaPair(credentials);
      diverge(mirrored.remote, mirrored.local);

      final forwardMeta = mergeOf(forward.local, forward.remote).body.meta;
      final mirroredMeta = mergeOf(mirrored.local, mirrored.remote).body.meta;

      // The newer side wins the key on both sides of the mirror...
      expect(forwardMeta.customData['shared-key'], 'aaa-from-the-fresh-side');
      expect(mirroredMeta.customData['shared-key'], 'aaa-from-the-fresh-side');
      // ...which is the same statement as: the dimension is commutative.
      expect(
        forwardMeta.customData['shared-key'],
        mirroredMeta.customData['shared-key'],
      );
      expect(forwardMeta.historyMaxItems.get(), 99);
      expect(mirroredMeta.historyMaxItems.get(), 99);
    });

    // LOW-4 (Gate 3 residual), PINNED rather than fixed — the same treatment
    // sibling order and entry history already get, and for a stronger reason.
    //
    // Two icons sharing a UUID and disagreeing on bytes do not converge:
    // `addCustomIcon` is first-wins, so each device keeps its own, and the
    // manifest compares `base64(icon.data)` per UUID. The proposed two-line
    // tie-break on the bytes is NOT implementable against kdbx 2.5.0:
    // `KdbxMeta.customIcons` is an `UnmodifiableMapView` and `addCustomIcon`
    // is the only mutator, so no caller of this library can replace the bytes
    // under an existing UUID. That is also why the state is unreachable from
    // this app: it can only arrive from a foreign writer that reuses a UUID
    // with different bytes, and neither KeePass nor KeePassXC edits an icon in
    // place — icon UUIDs are minted randomly at creation.
    //
    // This test exists to fail the day that stops being true. If a kdbx
    // upgrade adds a real mutator, the tie-break becomes implementable and
    // this assertion is the thing that says so.
    test('LOW-4 pin: same icon UUID with different bytes does NOT converge, '
        'and kdbx exposes no mutator to make it', () {
      final shared = KdbxUuid.random();
      final fromA = Uint8List.fromList(const [1, 1, 1]);
      final fromB = Uint8List.fromList(const [2, 2, 2]);

      // First-wins is the whole mechanism: adding a second icon under a UUID
      // the meta already holds is a no-op, on either side of the mirror.
      final probe = _replicaPair(credentials);
      probe.local.body.meta.addCustomIcon(
        KdbxCustomIcon(uuid: shared, data: fromA),
      );
      probe.local.body.meta.addCustomIcon(
        KdbxCustomIcon(uuid: shared, data: fromB),
      );
      expect(probe.local.body.meta.customIcons[shared]!.data, fromA);

      Uint8List mergedBytes({
        required Uint8List local,
        required Uint8List remote,
      }) {
        final pair = _replicaPair(credentials);
        pair.local.body.meta.addCustomIcon(
          KdbxCustomIcon(uuid: shared, data: local),
        );
        pair.remote.body.meta.addCustomIcon(
          KdbxCustomIcon(uuid: shared, data: remote),
        );
        return mergeOf(
          pair.local,
          pair.remote,
        ).body.meta.customIcons[shared]!.data;
      }

      // Each device keeps its own. Stated as an assertion so the divergence is
      // visible in the suite instead of being discovered by a read-back.
      expect(mergedBytes(local: fromA, remote: fromB), fromA);
      expect(mergedBytes(local: fromB, remote: fromA), fromB);
    });
  });

  group('FR-5 tombstone clocks converge on the newer side', () {
    test('the same record deleted on both sides keeps the NEWER clock, so two '
        'devices converge in one round', () {
      // The earlier implementation returned early whenever the UUID was
      // already tombstoned locally, so each device froze its own clock and
      // neither ever adopted the other's — measured as
      // `ROUND2_CONVERGED=false`, `ROUND3_CONVERGED=false`. The vault CONTENT
      // converged anyway (both clocks sit above the live mtime, so G1
      // classifies identically), but `DeletedObjects` did not, and FR-7 step 5
      // arbitrates on the manifest.
      final orphan = KdbxUuid.random();
      final older = DateTime.utc(2020, 1, 1);
      final newer = DateTime.utc(2020, 1, 1, 0, 0, 3);

      KdbxPresenceDiff diffOf(KdbxFile local, KdbxFile remote) => adapter
          .diffPresence(adapter.validatePair(local: local, remote: remote));

      KdbxFile candidateOf(KdbxFile local, KdbxFile remote) {
        final validated = adapter.validatePair(local: local, remote: remote);
        return adapter.applyMerge(
          pair: validated,
          diff: diffOf(local, remote),
          resolution: KdbxMergeResolution(),
        );
      }

      // Device A deleted it three seconds before device B did.
      final deviceA = _replicaPair(credentials);
      _stampTombstone(deviceA.local, orphan, older);
      _stampTombstone(deviceA.remote, orphan, newer);
      final mergedOnA = candidateOf(deviceA.local, deviceA.remote);

      // Device B sees the same pair from the other side.
      final deviceB = _replicaPair(credentials);
      _stampTombstone(deviceB.local, orphan, newer);
      _stampTombstone(deviceB.remote, orphan, older);
      final mergedOnB = candidateOf(deviceB.local, deviceB.remote);

      expect(tombstonesOf(mergedOnA)[orphan.uuid], newer);
      expect(tombstonesOf(mergedOnB)[orphan.uuid], newer);
      expect(
        tombstonesOf(mergedOnA)[orphan.uuid],
        tombstonesOf(mergedOnB)[orphan.uuid],
        reason: 'one round, not three — the join is a max, not a first-wins',
      );
    });

    test('a local tombstone NEWER than the remote one is kept', () {
      final orphan = KdbxUuid.random();
      final older = DateTime.utc(2019);
      final newer = DateTime.utc(2021);

      final pair = _replicaPair(credentials);
      _stampTombstone(pair.local, orphan, newer);
      _stampTombstone(pair.remote, orphan, older);

      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      final candidate = adapter.applyMerge(
        pair: validated,
        diff: adapter.diffPresence(validated),
        resolution: KdbxMergeResolution(),
      );

      expect(tombstonesOf(candidate)[orphan.uuid], newer);
    });
  });

  // ===========================================================================
  // FR-3 — the both-sides notes union. Not a concatenation.
  // ===========================================================================
  group('FR-3 notes segment union', () {
    test('the sentinel leaves ordinary user text intact — a typed thematic '
        'break is NOT a segment boundary', () {
      const userText = 'Zeta recovery codes\n\n---\n\nAlpha backup email';
      final merged = notesSegmentUnion(userText, 'Mike says rotate quarterly');

      // With a plain `---` separator the peer's sentence would be sorted INTO
      // the middle of a note the user wrote as one block.
      expect(merged, contains(userText));
      expect(merged.split(mergeNotesSeparator), hasLength(2));
    });

    test('a segment the user legitimately repeated is not deduplicated away, '
        'because ordinary text is one atom', () {
      const userText = 'TODO\n\n---\n\nrotate key\n\n---\n\nTODO';
      expect(notesSegmentUnion(userText, 'zzz'), contains(userText));
    });

    test('the union is commutative, associative and idempotent', () {
      const a = 'zeta';
      const b = 'alpha';
      const c = 'mike';

      expect(notesSegmentUnion(a, b), notesSegmentUnion(b, a));
      expect(
        notesSegmentUnion(notesSegmentUnion(a, b), c),
        notesSegmentUnion(a, notesSegmentUnion(b, c)),
      );
      final once = notesSegmentUnion(a, b);
      expect(notesSegmentUnion(once, a), once);
      expect(notesSegmentUnion(once, once), once);
    });

    test('segments sort by UTF-8 bytes, not by UTF-16 code units', () {
      // An astral character's surrogate pair sorts BELOW U+E000..FFFF in
      // UTF-16 and ABOVE it in UTF-8. Two devices disagreeing on the encoding
      // would order the merged notes differently and never converge.
      const astral = '\u{10400}';
      const bmp = '\uE000';
      expect(compareUtf8Bytes(astral, bmp), greaterThan(0));
      expect(
        astral.codeUnits.first.compareTo(bmp.codeUnits.first),
        lessThan(0),
      );
      expect(notesSegmentUnion(astral, bmp).split(mergeNotesSeparator), [
        bmp,
        astral,
      ]);
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

  // ===========================================================================
  // T401a — `compareFieldPresent`: FR-3 rule 3 extended to the protection
  // dimension `KdbxFieldPresent.sameAs` also compares.
  // ===========================================================================
  group('T401a compareFieldPresent — the protection dimension', () {
    KdbxFieldPresent presentOf(String value, {required bool protected}) =>
        KdbxFieldPresent(
          semanticValue: value,
          isProtected: protected,
          length: value.length,
        );

    test('value bytes decide first; protection never overrides a real value '
        'difference', () {
      final greater = presentOf('zzz', protected: false);
      final lesser = presentOf('aaa', protected: true);
      expect(compareFieldPresent(greater, lesser), greaterThan(0));
      expect(compareFieldPresent(lesser, greater), lessThan(0));
    });

    test('on byte-identical values, protected sorts after plain — fixed, '
        'not perspective-dependent', () {
      final plain = presentOf('same', protected: false);
      final protectedValue = presentOf('same', protected: true);
      expect(compareFieldPresent(protectedValue, plain), greaterThan(0));
      expect(compareFieldPresent(plain, protectedValue), lessThan(0));
    });

    test('equal value and equal protection compare exactly equal', () {
      expect(
        compareFieldPresent(
          presentOf('same', protected: true),
          presentOf('same', protected: true),
        ),
        0,
      );
    });

    test(
      'a protection-only conflict is commutative across mirrored '
      'perspectives — the bug this fixes: comparing the value alone left a '
      'bare tie that a naive ">= 0 ? local : remote" always resolved to '
      '"local", so two mirrored devices each kept their OWN flag forever',
      () {
        final plain = presentOf('shared-text', protected: false);
        final protectedValue = presentOf('shared-text', protected: true);

        // forward: local=plain, remote=protected. mirrored: swapped.
        final forwardWinnerIsLocal =
            compareFieldPresent(plain, protectedValue) >= 0;
        final mirroredWinnerIsLocal =
            compareFieldPresent(protectedValue, plain) >= 0;

        // The two booleans must DIFFER, because "local" denotes a different
        // actual candidate in each perspective — that is what makes the
        // ACTUAL winning candidate (protected, since it sorts greater) the
        // same on both devices. Equal booleans would mean both devices kept
        // their own side regardless of content, which is the perspective bug.
        expect(forwardWinnerIsLocal, isFalse);
        expect(mirroredWinnerIsLocal, isTrue);
      },
    );
  });

  // ===========================================================================
  // T401a — the "identical" row's divergent key spelling (FR-4's presence
  // table): equal value, different spelling. Resolved by FR-3's UTF-8 order
  // over the SPELLINGS, never "keep local".
  // ===========================================================================
  group('T401a identical-row key spelling', () {
    KdbxFile mergedWith({
      required String localSpelling,
      required String remoteSpelling,
    }) {
      final pair = _replicaPair(credentials);
      _sharedEntry(
        pair.local,
      ).setString(KdbxKey(localSpelling), PlainValue('same'));
      _sharedEntry(
        pair.remote,
      ).setString(KdbxKey(remoteSpelling), PlainValue('same'));
      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      return adapter.applyMerge(
        pair: validated,
        diff: adapter.diffPresence(validated),
        resolution: KdbxMergeResolution(),
      );
    }

    String? spellingOf(KdbxFile file) => _sharedEntry(file).stringEntries
        .firstWhere((e) => canonicalFieldKey(e.key.key) == 'custom_totp')
        .key
        .key;

    test('resolves to the UTF-8-greater spelling regardless of which side '
        'is local — mirrored perspectives agree', () {
      // 'c' (0x63) > 'C' (0x43), so 'custom_totp' is the greater spelling.
      final forward = mergedWith(
        localSpelling: 'Custom_Totp',
        remoteSpelling: 'custom_totp',
      );
      final mirrored = mergedWith(
        localSpelling: 'custom_totp',
        remoteSpelling: 'Custom_Totp',
      );

      expect(spellingOf(forward), 'custom_totp');
      expect(spellingOf(mirrored), 'custom_totp');
    });

    test('a matching spelling is left untouched — nothing to reconcile', () {
      final merged = mergedWith(
        localSpelling: 'Custom_Totp',
        remoteSpelling: 'Custom_Totp',
      );
      expect(spellingOf(merged), 'Custom_Totp');
    });
  });

  // ===========================================================================
  // T401a — the CONFLICTING row's divergent key spelling. Same rule as the
  // identical row, and the one place it was missing: `_takeRemote` used to
  // keep the LOCAL spelling. Mirrored devices resolve the same conflict to the
  // same value from opposite sides — one runs `_takeRemote`, the other takes
  // the `MergeChoice.local` branch — so a local-preferring spelling left the
  // two holding different verbatim keys forever, which is precisely the
  // perspective-dependent class FR-3 forbids.
  // ===========================================================================
  group('T401a conflicting-row key spelling', () {
    KdbxFile mergedWith({
      required String localSpelling,
      required String localValue,
      required String remoteSpelling,
      required String remoteValue,
    }) {
      final pair = _replicaPair(credentials);
      _sharedEntry(
        pair.local,
      ).setString(KdbxKey(localSpelling), PlainValue(localValue));
      _sharedEntry(
        pair.remote,
      ).setString(KdbxKey(remoteSpelling), PlainValue(remoteValue));
      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      final diff = adapter.diffPresence(validated);
      final field = _diffFor(diff, KdbxMergeFieldKind.string, 'custom_totp');
      expect(field.classification, KdbxFieldClassification.fieldConflict);
      // Resolved the way a real caller resolves it: T401a's deterministic
      // tie-break, which is what makes the two perspectives agree on the
      // VALUE and leaves only the spelling to this test.
      final choice =
          compareFieldPresent(
                field.local as KdbxFieldPresent,
                field.remote as KdbxFieldPresent,
              ) >=
              0
          ? MergeChoice.local
          : MergeChoice.remote;
      return adapter.applyMerge(
        pair: validated,
        diff: diff,
        resolution: KdbxMergeResolution(
          fieldChoices: {kdbxFieldRefOf(field): choice},
        ),
      );
    }

    MapEntry<KdbxKey, StringValue?> fieldOf(KdbxFile file) => _sharedEntry(file)
        .stringEntries
        .firstWhere((e) => canonicalFieldKey(e.key.key) == 'custom_totp');

    test('mirrored perspectives persist the SAME verbatim spelling, not each '
        'device its own', () {
      // 'c' (0x63) > 'C' (0x43) → 'custom_totp' is the greater spelling;
      // 'BBB' > 'AAA' → the remote value wins forward, the local one mirrored.
      final forward = mergedWith(
        localSpelling: 'Custom_Totp',
        localValue: 'AAA',
        remoteSpelling: 'custom_totp',
        remoteValue: 'BBB',
      );
      final mirrored = mergedWith(
        localSpelling: 'custom_totp',
        localValue: 'BBB',
        remoteSpelling: 'Custom_Totp',
        remoteValue: 'AAA',
      );

      expect(fieldOf(forward).key.key, fieldOf(mirrored).key.key);
      expect(
        fieldOf(forward).value?.getText(),
        fieldOf(mirrored).value?.getText(),
      );
      // Pinned so the equality above cannot pass vacuously.
      expect(fieldOf(forward).key.key, 'custom_totp');
      expect(fieldOf(forward).value?.getText(), 'BBB');
    });

    test('the spelling order is independent of which side won the value: the '
        'losing side\'s greater spelling still survives', () {
      // Local wins the VALUE ('zzz' > 'aaa') but remote holds the greater
      // SPELLING — the two dimensions are decided separately.
      final merged = mergedWith(
        localSpelling: 'Custom_Totp',
        localValue: 'zzz',
        remoteSpelling: 'custom_totp',
        remoteValue: 'aaa',
      );
      expect(fieldOf(merged).key.key, 'custom_totp');
      expect(fieldOf(merged).value?.getText(), 'zzz');
    });
  });

  // ===========================================================================
  // T401a — FR-3 associativity at 3 and 4 devices (criterion 15j), promoted
  // from the T009 model to the real adapter: the SAME tie-break comparator
  // (`compareFieldPresent`), applied through the REAL diff/apply/serialize
  // pipeline, must still be a join-semilattice — any grouping of the same
  // devices converges to the same value. Pairwise binary max is
  // mathematically associative for any total order; what this proves is that
  // nothing in the KDBX plumbing (wall-clock stamps, key handling, history)
  // sneaks in a dependency on merge ORDER that the abstract model does not
  // have.
  // ===========================================================================
  group('T401a FR-3 associativity, 3 and 4 devices (15j)', () {
    Future<KdbxFile> deviceWith(KdbxUuid rootUuid, String value) async {
      final file = _buildSide(credentials);
      file.body.rootGroup.forceSetUuid(rootUuid);
      _sharedEntry(file)
        ..setString(KdbxKeyCommon.USER_NAME, PlainValue(value))
        ..times.lastModificationTime.set(DateTime.utc(2022));
      return file;
    }

    Future<KdbxFile> copyOf(KdbxFile file) async =>
        KdbxFormat().read(Uint8List.fromList(await file.save()), credentials);

    KdbxMergeResolution byTieBreak(KdbxPresenceDiff diff) {
      final choices = <KdbxFieldRef, MergeChoice>{};
      for (final field in diff.fieldDiffs) {
        if (field.classification != KdbxFieldClassification.fieldConflict) {
          continue;
        }
        final local = field.local as KdbxFieldPresent;
        final remote = field.remote as KdbxFieldPresent;
        choices[kdbxFieldRefOf(field)] = compareFieldPresent(local, remote) >= 0
            ? MergeChoice.local
            : MergeChoice.remote;
      }
      // UserName is a credential-block member (T401c): a conflicting
      // UserName with no Password/URL present anywhere still engages the
      // block, so every engaged entry needs a block choice too, computed the
      // same way (entry time first, then the block image).
      final blockChoices = <String, MergeChoice>{
        for (final entryUuid in engagedCredentialBlockEntryUuids(diff))
          entryUuid: _defaultBlockChoiceOf(diff, entryUuid),
      };
      return KdbxMergeResolution(
        fieldChoices: choices,
        credentialBlockChoices: blockChoices,
      );
    }

    Future<KdbxFile> mergeOf(KdbxFile local, KdbxFile remote) async {
      final validated = adapter.validatePair(local: local, remote: remote);
      final diff = adapter.diffPresence(validated);
      return adapter.applyMerge(
        pair: validated,
        diff: diff,
        resolution: byTieBreak(diff),
      );
    }

    String userNameOf(KdbxFile file) =>
        _sharedEntry(file).getString(KdbxKeyCommon.USER_NAME)!.getText()!;

    test('(A merge B) merge C converges with A merge (B merge C)', () async {
      final rootUuid = KdbxUuid.random();
      final a = await deviceWith(rootUuid, 'alpha');
      final b = await deviceWith(rootUuid, 'zeta');
      final c = await deviceWith(rootUuid, 'mike');

      final abThenC = await mergeOf(
        await mergeOf(await copyOf(a), await copyOf(b)),
        await copyOf(c),
      );
      final aThenBc = await mergeOf(
        await copyOf(a),
        await mergeOf(await copyOf(b), await copyOf(c)),
      );

      expect(userNameOf(abThenC), userNameOf(aThenBc));
      // 'zeta' is the UTF-8-greatest of the three, so both associations must
      // land on it — pinned so the test is not vacuously "equal to itself".
      expect(userNameOf(abThenC), 'zeta');
    });

    test('four devices converge under two different groupings', () async {
      final rootUuid = KdbxUuid.random();
      final a = await deviceWith(rootUuid, 'alpha');
      final b = await deviceWith(rootUuid, 'zeta');
      final c = await deviceWith(rootUuid, 'mike');
      final d = await deviceWith(rootUuid, 'romeo');

      // ((A merge B) merge C) merge D
      final leftAssociated = await mergeOf(
        await mergeOf(
          await mergeOf(await copyOf(a), await copyOf(b)),
          await copyOf(c),
        ),
        await copyOf(d),
      );
      // (A merge B) merge (C merge D)
      final balanced = await mergeOf(
        await mergeOf(await copyOf(a), await copyOf(b)),
        await mergeOf(await copyOf(c), await copyOf(d)),
      );

      expect(userNameOf(leftAssociated), userNameOf(balanced));
      expect(userNameOf(leftAssociated), 'zeta');
    });
  });

  // ===========================================================================
  // T401c — FR-3a's atomic credential block (criteria 15m/15n).
  // ===========================================================================
  group('T401c credential block atomicity (15m)', () {
    ({KdbxFile local, KdbxFile remote}) engagedPair({DateTime? tiedAt}) {
      final pair = _replicaPair(credentials);
      final localEntry = _sharedEntry(pair.local);
      final remoteEntry = _sharedEntry(pair.remote);

      // Chosen so the per-field UTF-8 order elects OPPOSITE sides: 'Z' > 'A'
      // picks LOCAL for username, but 'C' > 'B' picks REMOTE for password.
      localEntry.setString(KdbxKeyCommon.USER_NAME, PlainValue('Z'));
      remoteEntry.setString(KdbxKeyCommon.USER_NAME, PlainValue('A'));
      localEntry.setString(KdbxKeyCommon.PASSWORD, PlainValue('B'));
      remoteEntry.setString(
        KdbxKeyCommon.PASSWORD,
        ProtectedValue.fromString('C'),
      );
      // A SHARED member that does NOT itself conflict (equal value), but
      // whose key spelling diverges — proves the block still takes its
      // spelling from the winning side, not from the general per-field
      // key-spelling order (which would pick 'url', the lowercase spelling,
      // regardless of which side wins the block).
      localEntry.setString(KdbxKey('url'), PlainValue('https://example.test'));
      remoteEntry.setString(KdbxKey('URL'), PlainValue('https://example.test'));

      if (tiedAt != null) {
        localEntry.times.lastModificationTime.set(tiedAt);
        remoteEntry.times.lastModificationTime.set(tiedAt);
      }
      return (local: pair.local, remote: pair.remote);
    }

    test('an entry whose UserName and Password both conflict, chosen so the '
        'per-field UTF-8 order elects OPPOSITE sides, takes BOTH from ONE '
        'side — asserted to fail against a naive per-field comparator', () {
      final built = engagedPair(tiedAt: DateTime.utc(2022));
      final validated = adapter.validatePair(
        local: built.local,
        remote: built.remote,
      );
      final diff = adapter.diffPresence(validated);

      expect(
        engagedCredentialBlockEntryUuids(diff),
        contains(_sharedEntryUuid),
        reason: 'both UserName and Password conflict, so the block engages',
      );

      final blockChoice = _defaultBlockChoiceOf(diff, _sharedEntryUuid);
      // The block image is `B|url-empty|Z` vs `C|URL-empty|A` — wait, url
      // itself is shared (not part of the "absent" case) but EQUAL, so it
      // contributes the SAME bytes to both images and cannot decide the
      // comparison; the first differing byte is password's 'B' vs 'C', so
      // remote's image is greater.
      expect(blockChoice, MergeChoice.remote);

      final merged = adapter.applyMerge(
        pair: validated,
        diff: diff,
        resolution: KdbxMergeResolution(
          credentialBlockChoices: {_sharedEntryUuid: blockChoice},
        ),
      );
      final entry = _sharedEntry(merged);

      // A per-field comparator would have elected LOCAL's username ('Z',
      // since 'Z' > 'A') — the block instead takes BOTH from remote.
      expect(entry.getString(KdbxKeyCommon.USER_NAME)?.getText(), 'A');
      expect(entry.getString(KdbxKeyCommon.PASSWORD)?.getText(), 'C');
      // Protected flag travels with the winning side too.
      expect(
        entry.getString(KdbxKeyCommon.PASSWORD),
        isA<ProtectedValue>(),
        reason: 'remote stored the password protected',
      );
      // The non-conflicting shared member (url) still takes ITS spelling
      // from the winning side — remote's 'URL', not local's lowercase 'url'
      // that the GENERIC key-spelling order (T401a) would otherwise pick.
      expect(
        entry.getString(KdbxKey('URL'))?.getText(),
        'https://example.test',
      );
      expect(
        entry.stringEntries
            .firstWhere((e) => canonicalFieldKey(e.key.key) == 'url')
            .key
            .key,
        'URL',
      );
    });

    test('mirrored perspectives elect the same side (15g extended to the '
        'block)', () {
      final forward = engagedPair(tiedAt: DateTime.utc(2022));
      final forwardValidated = adapter.validatePair(
        local: forward.local,
        remote: forward.remote,
      );
      final forwardDiff = adapter.diffPresence(forwardValidated);
      final forwardChoice = _defaultBlockChoiceOf(
        forwardDiff,
        _sharedEntryUuid,
      );
      final forwardMerged = adapter.applyMerge(
        pair: forwardValidated,
        diff: forwardDiff,
        resolution: KdbxMergeResolution(
          credentialBlockChoices: {_sharedEntryUuid: forwardChoice},
        ),
      );

      final mirrored = engagedPair(tiedAt: DateTime.utc(2022));
      final mirroredValidated = adapter.validatePair(
        // Swapped: what was remote is now local, and vice versa.
        local: mirrored.remote,
        remote: mirrored.local,
      );
      final mirroredDiff = adapter.diffPresence(mirroredValidated);
      final mirroredChoice = _defaultBlockChoiceOf(
        mirroredDiff,
        _sharedEntryUuid,
      );
      final mirroredMerged = adapter.applyMerge(
        pair: mirroredValidated,
        diff: mirroredDiff,
        resolution: KdbxMergeResolution(
          credentialBlockChoices: {_sharedEntryUuid: mirroredChoice},
        ),
      );

      String userNameOf(KdbxFile f) =>
          _sharedEntry(f).getString(KdbxKeyCommon.USER_NAME)!.getText()!;
      String passwordOf(KdbxFile f) =>
          _sharedEntry(f).getString(KdbxKeyCommon.PASSWORD)!.getText()!;

      expect(userNameOf(forwardMerged), userNameOf(mirroredMerged));
      expect(passwordOf(forwardMerged), passwordOf(mirroredMerged));
    });

    test('membership is case-insensitive: USERNAME, userName and Url are '
        'members', () {
      expect(isCredentialBlockKey(canonicalFieldKey('USERNAME')), isTrue);
      expect(isCredentialBlockKey(canonicalFieldKey('userName')), isTrue);
      expect(isCredentialBlockKey(canonicalFieldKey('Url')), isTrue);
    });

    test('membership is closed: Title, Notes, OTP, a custom field and an '
        'attachment are never absorbed', () {
      for (final key in ['Title', 'Notes', 'otp', 'Custom_Anything']) {
        expect(isCredentialBlockKey(canonicalFieldKey(key)), isFalse);
      }
    });

    test('Title and Notes conflicting alongside an engaged block are '
        'resolved independently, never folded into the block', () {
      final built = engagedPair(tiedAt: DateTime.utc(2022));
      _sharedEntry(
        built.local,
      ).setString(KdbxKeyCommon.TITLE, PlainValue('local-title'));
      _sharedEntry(
        built.remote,
      ).setString(KdbxKeyCommon.TITLE, PlainValue('remote-title'));

      final validated = adapter.validatePair(
        local: built.local,
        remote: built.remote,
      );
      final diff = adapter.diffPresence(validated);
      final titleField = diff.fieldDiffs.singleWhere(
        (f) => f.canonicalKey == 'title',
      );

      // The block picks remote; Title is answered LOCAL independently — if
      // Title had been folded into the block this would be unrepresentable
      // (there is no per-field resolution entry for a folded field) and
      // `applyMerge` would ignore this choice instead of honouring it.
      final merged = adapter.applyMerge(
        pair: validated,
        diff: diff,
        resolution: KdbxMergeResolution(
          fieldChoices: {kdbxFieldRefOf(titleField): MergeChoice.local},
          credentialBlockChoices: {_sharedEntryUuid: MergeChoice.remote},
        ),
      );
      final entry = _sharedEntry(merged);
      expect(entry.getString(KdbxKeyCommon.TITLE)?.getText(), 'local-title');
      expect(entry.getString(KdbxKeyCommon.USER_NAME)?.getText(), 'A');
    });
  });

  group('T401c block presence — dormant and one-sided members (15n)', () {
    test('a block fully one-sided stays DORMANT and all three members '
        'survive, untouched', () {
      final pair = _replicaPair(credentials);
      final localEntry = _sharedEntry(pair.local);
      // `_buildSide` seeds UserName on BOTH sides; remove remote's so the
      // block is genuinely one-sided rather than a UserName conflict.
      _sharedEntry(pair.remote).removeString(KdbxKeyCommon.USER_NAME);
      localEntry
        ..setString(KdbxKeyCommon.USER_NAME, PlainValue('only-local-user'))
        ..setString(KdbxKeyCommon.PASSWORD, PlainValue('only-local-password'))
        ..setString(KdbxKeyCommon.URL, PlainValue('https://only-local'));

      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      final diff = adapter.diffPresence(validated);

      expect(engagedCredentialBlockEntryUuids(diff), isEmpty);

      // No credential-block resolution is ever consulted for a dormant
      // block — an empty resolution must still apply cleanly.
      final merged = adapter.applyMerge(
        pair: validated,
        diff: diff,
        resolution: KdbxMergeResolution(),
      );
      final entry = _sharedEntry(merged);
      expect(
        entry.getString(KdbxKeyCommon.USER_NAME)?.getText(),
        'only-local-user',
      );
      expect(
        entry.getString(KdbxKeyCommon.PASSWORD)?.getText(),
        'only-local-password',
      );
      expect(
        entry.getString(KdbxKeyCommon.URL)?.getText(),
        'https://only-local',
      );
    });

    test('a block engaged with ONE one-sided member preserves that member '
        'under the block winner regardless — no shortcut deletes it', () {
      final pair = _replicaPair(credentials);
      final localEntry = _sharedEntry(pair.local);
      final remoteEntry = _sharedEntry(pair.remote);

      localEntry.setString(KdbxKeyCommon.USER_NAME, PlainValue('local-user'));
      remoteEntry.setString(KdbxKeyCommon.USER_NAME, PlainValue('remote-user'));
      localEntry.setString(
        KdbxKeyCommon.PASSWORD,
        PlainValue('local-password'),
      );
      remoteEntry.setString(
        KdbxKeyCommon.PASSWORD,
        PlainValue('remote-password'),
      );
      // URL exists ONLY on local — one-sided, never a conflict.
      localEntry.setString(KdbxKeyCommon.URL, PlainValue('https://local-only'));

      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      final diff = adapter.diffPresence(validated);
      expect(
        engagedCredentialBlockEntryUuids(diff),
        contains(_sharedEntryUuid),
      );

      final merged = adapter.applyMerge(
        pair: validated,
        diff: diff,
        resolution: KdbxMergeResolution(
          credentialBlockChoices: {_sharedEntryUuid: MergeChoice.remote},
        ),
      );
      final entry = _sharedEntry(merged);

      expect(
        entry.getString(KdbxKeyCommon.USER_NAME)?.getText(),
        'remote-user',
      );
      expect(
        entry.getString(KdbxKeyCommon.PASSWORD)?.getText(),
        'remote-password',
      );
      // The one-sided URL survives even though the block winner is remote
      // and remote never held a URL at all — FR-4's no-deletion invariant is
      // stronger than atomicity.
      expect(
        entry.getString(KdbxKeyCommon.URL)?.getText(),
        'https://local-only',
      );
    });

    test('the same holds with the block winner LOCAL and the one-sided member '
        'on the REMOTE side — survival is not an artefact of one winner', () {
      final pair = _replicaPair(credentials);
      final localEntry = _sharedEntry(pair.local);
      final remoteEntry = _sharedEntry(pair.remote);

      localEntry.setString(KdbxKeyCommon.USER_NAME, PlainValue('local-user'));
      remoteEntry.setString(KdbxKeyCommon.USER_NAME, PlainValue('remote-user'));
      localEntry.setString(
        KdbxKeyCommon.PASSWORD,
        PlainValue('local-password'),
      );
      remoteEntry.setString(
        KdbxKeyCommon.PASSWORD,
        PlainValue('remote-password'),
      );
      // URL exists ONLY on remote — the mirror of the case above, and the
      // harder one: the candidate is built from the LOCAL file, so a member
      // the winner never held has to be carried across rather than merely
      // left alone.
      remoteEntry.setString(
        KdbxKeyCommon.URL,
        PlainValue('https://remote-only'),
      );

      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      final diff = adapter.diffPresence(validated);
      expect(
        engagedCredentialBlockEntryUuids(diff),
        contains(_sharedEntryUuid),
      );

      final merged = adapter.applyMerge(
        pair: validated,
        diff: diff,
        resolution: KdbxMergeResolution(
          credentialBlockChoices: {_sharedEntryUuid: MergeChoice.local},
        ),
      );
      final entry = _sharedEntry(merged);

      expect(entry.getString(KdbxKeyCommon.USER_NAME)?.getText(), 'local-user');
      expect(
        entry.getString(KdbxKeyCommon.PASSWORD)?.getText(),
        'local-password',
      );
      expect(
        entry.getString(KdbxKeyCommon.URL)?.getText(),
        'https://remote-only',
      );
    });

    test('an ATTACHMENT named like a block member is never absorbed: block '
        'membership is gated on the field KIND, so it stays per-field and '
        'answerable independently', () {
      final pair = _replicaPair(credentials);
      final localEntry = _sharedEntry(pair.local);
      final remoteEntry = _sharedEntry(pair.remote);

      // Engage the block on the STRINGS.
      localEntry.setString(KdbxKeyCommon.USER_NAME, PlainValue('local-user'));
      remoteEntry.setString(KdbxKeyCommon.USER_NAME, PlainValue('remote-user'));
      // ...and hang attachments off the entry whose NAMES canonicalise to the
      // block's three member keys. Nothing but the field kind distinguishes
      // them from real members.
      for (final name in ['password', 'UserName', 'url']) {
        localEntry.createBinary(
          isProtected: false,
          name: name,
          bytes: Uint8List.fromList([1]),
        );
        remoteEntry.createBinary(
          isProtected: false,
          name: name,
          bytes: Uint8List.fromList([2]),
        );
      }

      final validated = adapter.validatePair(
        local: pair.local,
        remote: pair.remote,
      );
      final diff = adapter.diffPresence(validated);

      expect(
        credentialBlockFieldsOf(
          diff,
          _sharedEntryUuid,
        ).map((f) => f.fieldKind).toSet(),
        {KdbxMergeFieldKind.string},
        reason: 'the block owns strings only',
      );

      // Each attachment is answered per-field, against the block winner, so a
      // block that had absorbed them could not honour these choices at all.
      final attachments = [
        for (final name in ['password', 'UserName', 'url'])
          _diffFor(diff, KdbxMergeFieldKind.attachment, name),
      ];
      final merged = adapter.applyMerge(
        pair: validated,
        diff: diff,
        resolution: KdbxMergeResolution(
          fieldChoices: {
            for (final field in attachments)
              kdbxFieldRefOf(field): MergeChoice.local,
          },
          credentialBlockChoices: {_sharedEntryUuid: MergeChoice.remote},
        ),
      );
      final entry = _sharedEntry(merged);

      expect(
        entry.getString(KdbxKeyCommon.USER_NAME)?.getText(),
        'remote-user',
      );
      for (final name in ['password', 'UserName', 'url']) {
        expect(
          entry.getBinary(KdbxKey(name))?.value,
          orderedEquals([1]),
          reason: 'the attachment kept the side its OWN decision named',
        );
      }
    });
  });
}
