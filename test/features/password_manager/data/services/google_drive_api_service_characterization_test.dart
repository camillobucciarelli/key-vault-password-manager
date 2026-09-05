import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:password_manager/features/password_manager/data/services/drive_auth_service.dart';
import 'package:password_manager/features/password_manager/data/services/google_drive_api_service.dart';
import 'package:password_manager/features/password_manager/domain/models/cloud_storage_error.dart';

// spec 010 T003 — pins the Google technical service's inputs and outputs
// (query shape, pagination, field mapping, upload shape, download bytes and
// the single 401 refresh) so the provider adapter can be proven behaviour-
// preserving. No live account: every request is answered by a MockClient.

void main() {
  late _FakeAuth auth;
  late List<http.Request> requests;

  setUp(() {
    auth = _FakeAuth();
    requests = [];
  });

  GoogleDriveApiService service(
    Future<http.Response> Function(http.Request request) handler,
  ) {
    return GoogleDriveApiService(
      driveAuthService: auth,
      httpClient: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
    );
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Map<String, dynamic> file(String id, {String? md5, String? size}) => {
    'id': id,
    'name': '$id.kdbx',
    'modifiedTime': '2026-01-02T03:04:05.000Z',
    'md5Checksum': ?md5,
    'size': ?size,
  };

  group('list', () {
    test('no query: one GET with the base .kdbx query and size field', () async {
      final api = service(
        (_) async => json({
          'files': [file('a')],
        }),
      );

      final files = await api.listKdbxFilesInDrive();

      expect(requests, hasLength(1));
      final uri = requests.single.url;
      expect(uri.path, '/drive/v3/files');
      expect(
        uri.queryParameters['q'],
        "mimeType != 'application/vnd.google-apps.folder' and trashed = false and name contains '.kdbx'",
      );
      expect(
        uri.queryParameters['fields'],
        'nextPageToken,files(id,name,modifiedTime,md5Checksum,size)',
      );
      expect(uri.queryParameters['pageSize'], '1000');
      expect(uri.queryParameters['orderBy'], 'modifiedTime desc');
      expect(files.map((f) => f.id), ['a']);
      expect(() => files.add(files.first), throwsUnsupportedError);
    });

    test('pagination follows nextPageToken until absent', () async {
      final api = service((request) async {
        final token = request.url.queryParameters['pageToken'];
        if (token == null) {
          return json({
            'files': [file('p1')],
            'nextPageToken': 'tok-2',
          });
        }
        expect(token, 'tok-2');
        return json({
          'files': [file('p2')],
        });
      });

      final files = await api.listKdbxFilesInDrive();

      expect(requests, hasLength(2));
      expect(files.map((f) => f.id), ['p1', 'p2']);
    });

    test('query terms are ANDed server-side and escaped', () async {
      final api = service(
        (_) async => json({
          'files': [file('hit')],
        }),
      );

      await api.listKdbxFilesInDrive(query: "  bob's   vault ");

      expect(
        requests.single.url.queryParameters['q'],
        "mimeType != 'application/vnd.google-apps.folder' and trashed = false and name contains '.kdbx' and name contains 'bob\\'s' and name contains 'vault'",
      );
    });

    test(
      'empty server match falls back to base query + client filter',
      () async {
        final api = service((request) async {
          final q = request.url.queryParameters['q']!;
          if (q.contains("name contains 'Work'")) {
            return json({'files': <Object>[]});
          }
          return json({
            'files': [
              {'id': '1', 'name': 'work-vault.kdbx'},
              {'id': '2', 'name': 'home.kdbx'},
            ],
          });
        });

        final files = await api.listKdbxFilesInDrive(query: 'Work');

        expect(requests, hasLength(2));
        expect(files.map((f) => f.id), ['1']);
      },
    );
  });

  group('metadata mapping', () {
    test('maps id, name, local modifiedTime, md5 and size', () async {
      final api = service(
        (_) async => json(file('m', md5: 'abc', size: '4096')),
      );

      final remote = await api.getFileMetadata('m');

      expect(requests.single.url.path, '/drive/v3/files/m');
      expect(
        requests.single.url.queryParameters['fields'],
        'id,name,modifiedTime,md5Checksum,size',
      );
      expect(remote.id, 'm');
      expect(remote.name, 'm.kdbx');
      expect(remote.modifiedTime, DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal());
      expect(remote.contentChecksum, 'abc');
      expect(remote.size, 4096);
    });

    test('missing md5 and size stay null', () async {
      final api = service((_) async => json(file('m')));

      final remote = await api.getFileMetadata('m');

      expect(remote.contentChecksum, isNull);
      expect(remote.size, isNull);
    });
  });

  group('create / update / download', () {
    test('createFile POSTs multipart then refetches metadata', () async {
      final api = service((request) async {
        if (request.method == 'POST') {
          expect(request.url.path, '/upload/drive/v3/files');
          expect(request.url.queryParameters['uploadType'], 'multipart');
          expect(
            request.headers['Content-Type'],
            startsWith('multipart/related; boundary='),
          );
          expect(utf8.decode(request.bodyBytes), contains('"name":"new.kdbx"'));
          return json({'id': 'created'});
        }
        return json(file('created', md5: 'fresh'));
      });

      final remote = await api.createFile(
        fileName: 'new.kdbx',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(requests.map((r) => r.method), ['POST', 'GET']);
      expect(remote.id, 'created');
      expect(remote.contentChecksum, 'fresh');
    });

    test('updateFile PATCHes media then refetches metadata', () async {
      final api = service((request) async {
        if (request.method == 'PATCH') {
          expect(request.url.path, '/upload/drive/v3/files/u');
          expect(request.url.queryParameters['uploadType'], 'media');
          expect(request.headers['Content-Type'], 'application/octet-stream');
          expect(request.bodyBytes, [9, 9]);
          return json({'id': 'u'});
        }
        return json(file('u', md5: 'after'));
      });

      final remote = await api.updateFile(
        fileId: 'u',
        bytes: Uint8List.fromList([9, 9]),
      );

      expect(requests.map((r) => r.method), ['PATCH', 'GET']);
      expect(remote.contentChecksum, 'after');
    });

    test('downloadFile GETs alt=media and returns the body bytes', () async {
      final api = service((_) async => http.Response.bytes([5, 6, 7], 200));

      final bytes = await api.downloadFile('d');

      expect(requests.single.url.path, '/drive/v3/files/d');
      expect(requests.single.url.queryParameters['alt'], 'media');
      expect(bytes, [5, 6, 7]);
    });
  });

  group('auth header and 401 refresh', () {
    test('every request carries the bearer token', () async {
      final api = service((_) async => http.Response.bytes([], 200));

      await api.downloadFile('d');

      expect(requests.single.headers['Authorization'], 'Bearer token-1');
      expect(auth.forceRefreshFlags, [false]);
    });

    test('401 triggers exactly one forced refresh and a retry', () async {
      var calls = 0;
      final api = service((_) async {
        calls += 1;
        return calls == 1
            ? http.Response('', 401)
            : http.Response.bytes([1], 200);
      });

      final bytes = await api.downloadFile('d');

      expect(bytes, [1]);
      expect(auth.forceRefreshFlags, [false, true]);
      expect(requests.map((r) => r.headers['Authorization']), [
        'Bearer token-1',
        'Bearer token-2',
      ]);
    });

    test(
      'a second 401 is not retried again: it surfaces as a failure',
      () async {
        final api = service((_) async => http.Response('', 401));

        await expectLater(
          api.downloadFile('d'),
          throwsA(
            isA<CloudStorageException>().having(
              (e) => e.code,
              'code',
              CloudStorageErrorCode.authorizationRequired,
            ),
          ),
        );
        expect(requests, hasLength(2));
        expect(auth.forceRefreshFlags, [false, true]);
      },
    );
  });

  group('non-2xx (spec 010 T203: typed, body discarded)', () {
    const rows = {
      403: CloudStorageErrorCode.forbidden,
      404: CloudStorageErrorCode.notFound,
      409: CloudStorageErrorCode.conflict,
      429: CloudStorageErrorCode.rateLimited,
      500: CloudStorageErrorCode.serverFailure,
    };
    rows.forEach((status, code) {
      test('$status -> ${code.name}, body never copied', () async {
        final api = service(
          (_) async => http.Response('{"error":"secret-body"}', status),
        );

        await expectLater(
          api.getFileMetadata('x'),
          throwsA(
            isA<CloudStorageException>()
                .having((e) => e.code, 'code', code)
                .having(
                  (e) => e.toString(),
                  'toString',
                  isNot(contains('secret-body')),
                ),
          ),
        );
      });
    });
  });
}

class _FakeAuth implements DriveAuthService {
  final List<bool> forceRefreshFlags = [];

  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) async {
    forceRefreshFlags.add(forceRefresh);
    return 'token-${forceRefreshFlags.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed here');
}
