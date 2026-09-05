import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';

// spec 010 T103/T104 — table-driven decode matrix for §Backward-compatible
// decode rules 1-6 and the version-2 write-forward shape. The quoted
// `driveFileId` / `driveFileName` keys below are the only place outside the
// decoder those v1 keys may appear (architecture guard allowlist).

const _baseline = <String, dynamic>{
  'databaseId': 'db-1',
  'databasePath': '{documents}/vault.kdbx',
  'lastSyncedLocalChecksum': 'local-sum',
  'lastSyncedRemoteChecksum': 'remote-sum',
  'lastSyncedRemoteModifiedTime': '2026-01-02T03:04:05.000Z',
  'lastSyncAt': '2026-01-03T00:00:00.000Z',
  'autoSyncEnabled': false,
  'lastError': 'previous error',
};

void main() {
  group('decode', () {
    final rows = <String, ({Map<String, dynamic> input, Object expect})>{
      'rule 1: v1 without providerId decodes as google_drive': (
        input: {..._baseline, 'driveFileId': 'id-1', 'driveFileName': 'v.kdbx'},
        expect: ('google_drive', 'id-1', 'v.kdbx'),
      ),
      'rule 1: explicit schemaVersion 1 is treated as v1': (
        input: {
          ..._baseline,
          'schemaVersion': 1,
          'driveFileId': 'id-1',
          'driveFileName': 'v.kdbx',
        },
        expect: ('google_drive', 'id-1', 'v.kdbx'),
      ),
      'rule 2/3: v1 with generic keys reads them': (
        input: {
          ..._baseline,
          'remoteFileId': 'gen-id',
          'remoteFileName': 'gen.kdbx',
        },
        expect: ('google_drive', 'gen-id', 'gen.kdbx'),
      ),
      'rule 5: conflicting generic and legacy values -> generic wins': (
        input: {
          ..._baseline,
          'remoteFileId': 'gen-id',
          'driveFileId': 'legacy-id',
          'remoteFileName': 'gen.kdbx',
          'driveFileName': 'legacy.kdbx',
        },
        expect: ('google_drive', 'gen-id', 'gen.kdbx'),
      ),
      'rule 2/3: empty generic value falls back to legacy alias in v1': (
        input: {
          ..._baseline,
          'remoteFileId': '  ',
          'driveFileId': 'legacy-id',
          'remoteFileName': '',
          'driveFileName': 'legacy.kdbx',
        },
        expect: ('google_drive', 'legacy-id', 'legacy.kdbx'),
      ),
      'v1 with an explicit providerId keeps it': (
        input: {
          ..._baseline,
          'providerId': 'other_cloud',
          'driveFileId': 'id-1',
          'driveFileName': 'v.kdbx',
        },
        expect: ('other_cloud', 'id-1', 'v.kdbx'),
      ),
      'v2 canonical shape': (
        input: {
          ..._baseline,
          'schemaVersion': 2,
          'providerId': 'google_drive',
          'remoteFileId': 'id-2',
          'remoteFileName': 'v2.kdbx',
        },
        expect: ('google_drive', 'id-2', 'v2.kdbx'),
      ),
      'rule 4: v2 unknown provider is retained, not executed here': (
        input: {
          ..._baseline,
          'schemaVersion': 2,
          'providerId': 'unknown_provider',
          'remoteFileId': 'id-2',
          'remoteFileName': 'v2.kdbx',
        },
        expect: ('unknown_provider', 'id-2', 'v2.kdbx'),
      ),
      'rule 4: v2 missing providerId fails closed': (
        input: {
          ..._baseline,
          'schemaVersion': 2,
          'remoteFileId': 'id-2',
          'remoteFileName': 'v2.kdbx',
        },
        expect: const SyncMappingDecodeException(),
      ),
      'rule 4: v2 does not read legacy aliases': (
        input: {
          ..._baseline,
          'schemaVersion': 2,
          'providerId': 'google_drive',
          'driveFileId': 'id-2',
          'driveFileName': 'v2.kdbx',
        },
        expect: const SyncMappingDecodeException(),
      ),
      'rule 6: v1 with no identity at all fails closed': (
        input: {..._baseline},
        expect: const SyncMappingDecodeException(),
      ),
      'rule 6: empty remoteFileName in v2 fails closed': (
        input: {
          ..._baseline,
          'schemaVersion': 2,
          'providerId': 'google_drive',
          'remoteFileId': 'id-2',
          'remoteFileName': '',
        },
        expect: const SyncMappingDecodeException(),
      ),
      'rule 6: non-string identity fails closed': (
        input: {
          ..._baseline,
          'schemaVersion': 2,
          'providerId': 'google_drive',
          'remoteFileId': 42,
          'remoteFileName': 'v2.kdbx',
        },
        expect: const SyncMappingDecodeException(),
      ),
      'rule 6: missing databasePath fails closed': (
        input: {
          'schemaVersion': 2,
          'providerId': 'google_drive',
          'remoteFileId': 'id-2',
          'remoteFileName': 'v2.kdbx',
        },
        expect: const SyncMappingDecodeException(),
      ),
    };

    rows.forEach((name, row) {
      test(name, () {
        final expected = row.expect;
        if (expected is SyncMappingDecodeException) {
          expect(
            () => DatabaseSyncMapping.fromMap(row.input),
            throwsA(isA<SyncMappingDecodeException>()),
          );
          return;
        }
        final (providerId, remoteFileId, remoteFileName) =
            expected as (String, String, String);
        final mapping = DatabaseSyncMapping.fromMap(row.input);
        expect(mapping.providerId, providerId);
        expect(mapping.remoteFileId, remoteFileId);
        expect(mapping.remoteFileName, remoteFileName);
        // rule 7 / acceptance 7: every non-identity value survives.
        expect(mapping.databaseId, 'db-1');
        expect(mapping.databasePath, '{documents}/vault.kdbx');
        expect(mapping.lastSyncedLocalChecksum, 'local-sum');
        expect(mapping.lastSyncedRemoteChecksum, 'remote-sum');
        expect(
          mapping.lastSyncedRemoteModifiedTime,
          DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal(),
        );
        expect(mapping.lastSyncAt, DateTime.utc(2026, 1, 3).toLocal());
        expect(mapping.autoSyncEnabled, isFalse);
        expect(mapping.lastError, 'previous error');
      });
    });

    test('the decode failure reveals nothing from the entry', () {
      const sentinel = 'SENTINEL-ya29.secret-path';
      try {
        DatabaseSyncMapping.fromMap({
          ..._baseline,
          'databasePath': sentinel,
          'schemaVersion': 2,
          'providerId': sentinel,
          'remoteFileId': '',
          'remoteFileName': sentinel,
        });
        fail('expected SyncMappingDecodeException');
      } on SyncMappingDecodeException catch (e) {
        expect(e.toString(), isNot(contains('SENTINEL')));
      }
    });
  });

  group('write-forward', () {
    test('toMap writes v2 keys only, no legacy keys', () {
      final legacy = DatabaseSyncMapping.fromMap({
        ..._baseline,
        'driveFileId': 'id-1',
        'driveFileName': 'v.kdbx',
      });

      final map = legacy.toMap();

      expect(map['schemaVersion'], 2);
      expect(map['providerId'], 'google_drive');
      expect(map['remoteFileId'], 'id-1');
      expect(map['remoteFileName'], 'v.kdbx');
      expect(map.containsKey('driveFileId'), isFalse);
      expect(map.containsKey('driveFileName'), isFalse);
      // Non-identity keys round-trip byte-for-byte.
      for (final key in _baseline.keys) {
        expect(map[key], _baseline[key], reason: key);
      }
    });

    test('v2 JSON round-trips to an equal mapping', () {
      final mapping = DatabaseSyncMapping.fromMap({
        ..._baseline,
        'driveFileId': 'id-1',
        'driveFileName': 'v.kdbx',
      });

      final again = DatabaseSyncMapping.fromJson(mapping.toJson());

      expect(again, mapping);
      expect(jsonDecode(mapping.toJson())['schemaVersion'], 2);
    });
  });

  group('identity', () {
    test(
      'equality includes providerId: same id, different provider differ',
      () {
        const a = DatabaseSyncMapping(
          databasePath: '/v.kdbx',
          providerId: 'google_drive',
          remoteFileId: 'same-id',
          remoteFileName: 'v.kdbx',
        );
        final b = a.copyWith(providerId: 'other_cloud');

        expect(a, isNot(equals(b)));
        expect(b.remoteFileId, a.remoteFileId);
      },
    );
  });
}
