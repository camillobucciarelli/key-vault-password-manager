import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:password_manager/features/password_manager/data/services/drive_auth_service.dart';
import 'package:password_manager/features/password_manager/data/services/google_drive_api_service.dart';
import 'package:password_manager/features/password_manager/data/services/google_drive_storage_provider.dart';
import 'package:password_manager/features/password_manager/domain/errors/google_authorization_required_exception.dart';
import 'package:password_manager/features/password_manager/domain/models/cloud_storage_error.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_account_summary.dart';
import 'package:password_manager/features/password_manager/domain/repositories/cloud_storage_provider.dart';

// spec 010 T202/T203 — the Google adapter: neutral model mapping, behaviour
// pass-through, and one adversarial test per error-table row. Every raw
// failure carries [_sentinel] somewhere (body, URL, message) and the test
// asserts it never reaches safeCode / safeMessage / toString.

const _sentinel = 'SENTINEL-ya29.a0AfH6SMB-secret-token';

void main() {
  late _FakeAuth auth;
  late List<http.Request> requests;

  setUp(() {
    auth = _FakeAuth();
    requests = [];
  });

  CloudStorageProvider provider(
    FutureOr<http.Response> Function(http.Request request) handler,
  ) {
    return GoogleDriveStorageProvider(
      authService: auth,
      apiService: GoogleDriveApiService(
        driveAuthService: auth,
        httpClient: MockClient((request) async {
          requests.add(request);
          return handler(request);
        }),
      ),
    );
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<CloudStorageException> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } on CloudStorageException catch (e) {
      return e;
    } catch (e) {
      fail('escaped the adapter as ${e.runtimeType}: $e');
    }
    fail('expected a CloudStorageException');
  }

  void expectSanitized(CloudStorageException e, CloudStorageErrorCode code) {
    expect(e.code, code);
    for (final text in [e.safeCode, e.safeMessage, e.toString()]) {
      expect(text, isNot(contains('SENTINEL')));
      expect(text, isNot(contains('ya29')));
      expect(text, isNot(contains('http')));
    }
  }

  group('identity and models', () {
    test('providerId is the stable persisted constant', () {
      expect(provider((_) => json({})).providerId, 'google_drive');
      expect(GoogleDriveStorageProvider.id, 'google_drive');
    });

    test(
      'metadata maps to a RemoteFile stamped with the provider id',
      () async {
        final p = provider(
          (_) => json({
            'id': 'f1',
            'name': 'vault.kdbx',
            'modifiedTime': '2026-01-02T03:04:05.000Z',
            'md5Checksum': 'abc',
            'size': '12',
          }),
        );

        final file = await p.getFileMetadata('f1');

        expect(file.providerId, 'google_drive');
        expect(file.id, 'f1');
        expect(file.name, 'vault.kdbx');
        expect(file.modifiedTime, DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal());
        expect(file.contentChecksum, 'abc');
        expect(file.size, 12);
      },
    );

    test('missing checksum stays null (orchestrator falls back)', () async {
      final p = provider((_) => json({'id': 'f1', 'name': 'v.kdbx'}));
      expect((await p.getFileMetadata('f1')).contentChecksum, isNull);
    });

    test('list is an immutable snapshot of provider-stamped files', () async {
      final p = provider(
        (_) => json({
          'files': [
            {'id': 'a', 'name': 'a.kdbx'},
            {'id': 'b', 'name': 'b.kdbx'},
          ],
        }),
      );

      final files = await p.listKdbxFiles(query: 'x');

      expect(files.map((f) => f.id), ['a', 'b']);
      expect(files.every((f) => f.providerId == 'google_drive'), isTrue);
      expect(() => files.clear(), throwsUnsupportedError);
      expect(requests.single.url.queryParameters['q'], contains("'x'"));
    });

    test(
      'create/update return fresh metadata; download returns bytes',
      () async {
        final p = provider((request) {
          if (request.method == 'GET' &&
              request.url.queryParameters['alt'] == 'media') {
            return http.Response.bytes([7, 7], 200);
          }
          if (request.method == 'GET') {
            return json({'id': 'n', 'name': 'n.kdbx', 'md5Checksum': 'fresh'});
          }
          return json({'id': 'n'});
        });

        final created = await p.createFile(name: 'n.kdbx', bytes: Uint8List(1));
        final updated = await p.updateFile(
          remoteFileId: 'n',
          bytes: Uint8List(1),
        );
        final bytes = await p.downloadFile('n');

        expect(created.contentChecksum, 'fresh');
        expect(updated.contentChecksum, 'fresh');
        expect(bytes, [7, 7]);
        expect(requests.map((r) => r.method), [
          'POST',
          'GET',
          'PATCH',
          'GET',
          'GET',
        ]);
      },
    );

    test('account summary maps label and email; fallback preserved', () async {
      final p = provider((_) => json({}));
      auth.account = DriveAccountSummary.fallback;
      var account = await p.getConnectedAccount();
      expect(account.displayLabel, 'Google Drive account');
      expect(account.email, isNull);

      auth.account = const DriveAccountSummary(
        displayLabel: 'a@b.c',
        email: 'a@b.c',
      );
      account = await p.getConnectedAccount();
      expect(account.email, 'a@b.c');
    });

    test(
      'connect/disconnect/isConnected delegate to the auth service',
      () async {
        final p = provider((_) => json({}));
        await p.connect();
        expect(auth.connectCalls, 1);
        expect(await p.isConnected(), isTrue);
        await p.disconnect();
        expect(await p.isConnected(), isFalse);
      },
    );
  });

  group('HTTP status table', () {
    final rows = <int, CloudStorageErrorCode>{
      404: CloudStorageErrorCode.notFound,
      409: CloudStorageErrorCode.conflict,
      412: CloudStorageErrorCode.conflict,
      429: CloudStorageErrorCode.rateLimited,
      408: CloudStorageErrorCode.timeout,
      500: CloudStorageErrorCode.serverFailure,
      503: CloudStorageErrorCode.serverFailure,
      599: CloudStorageErrorCode.serverFailure,
      418: CloudStorageErrorCode.unknown,
      302: CloudStorageErrorCode.unknown,
    };
    rows.forEach((status, code) {
      test('$status -> ${code.name}', () async {
        final p = provider(
          (_) => http.Response('{"error":{"message":"$_sentinel"}}', status),
        );
        expectSanitized(await failure(() => p.getFileMetadata('x')), code);
      });
    });

    test('403 plain -> forbidden', () async {
      final p = provider(
        (_) => http.Response(
          '{"error":{"errors":[{"reason":"insufficientPermissions","message":"$_sentinel"}]}}',
          403,
        ),
      );
      expectSanitized(
        await failure(() => p.downloadFile('x')),
        CloudStorageErrorCode.forbidden,
      );
    });

    for (final reason in [
      'rateLimitExceeded',
      'userRateLimitExceeded',
      'dailyLimitExceeded',
      'quotaExceeded',
    ]) {
      test('403 $reason -> rateLimited', () async {
        final p = provider(
          (_) => http.Response(
            '{"error":{"errors":[{"reason":"$reason","message":"$_sentinel"}]}}',
            403,
          ),
        );
        expectSanitized(
          await failure(() => p.downloadFile('x')),
          CloudStorageErrorCode.rateLimited,
        );
      });
    }

    test('403 with details[].reason quota -> rateLimited', () async {
      final p = provider(
        (_) => http.Response(
          '{"error":{"details":[{"reason":"quotaExceeded"}]}}',
          403,
        ),
      );
      expectSanitized(
        await failure(() => p.downloadFile('x')),
        CloudStorageErrorCode.rateLimited,
      );
    });

    test('403 with an unparsable body -> forbidden', () async {
      final p = provider((_) => http.Response('<html>$_sentinel</html>', 403));
      expectSanitized(
        await failure(() => p.downloadFile('x')),
        CloudStorageErrorCode.forbidden,
      );
    });

    test('401 after the single refresh -> authorizationRequired', () async {
      final p = provider((_) => http.Response(_sentinel, 401));
      final e = await failure(() => p.downloadFile('x'));
      expectSanitized(e, CloudStorageErrorCode.authorizationRequired);
      expect(auth.forceRefreshFlags, [false, true]);
      expect(requests, hasLength(2));
    });

    test('401 then 200 -> success after exactly one refresh', () async {
      var calls = 0;
      final p = provider((_) {
        calls += 1;
        return calls == 1
            ? http.Response('', 401)
            : http.Response.bytes([1], 200);
      });
      expect(await p.downloadFile('x'), [1]);
      expect(auth.forceRefreshFlags, [false, true]);
    });
  });

  group('transport and decoding', () {
    test('TimeoutException -> timeout', () async {
      final p = provider((_) => throw TimeoutException(_sentinel));
      expectSanitized(
        await failure(() => p.downloadFile('x')),
        CloudStorageErrorCode.timeout,
      );
    });

    test('SocketException -> networkUnavailable', () async {
      final p = provider((_) => throw SocketException(_sentinel));
      expectSanitized(
        await failure(() => p.downloadFile('x')),
        CloudStorageErrorCode.networkUnavailable,
      );
    });

    test('http.ClientException -> networkUnavailable', () async {
      final p = provider((r) => throw http.ClientException(_sentinel, r.url));
      expectSanitized(
        await failure(() => p.downloadFile('x')),
        CloudStorageErrorCode.networkUnavailable,
      );
    });

    test('invalid JSON -> malformedResponse', () async {
      final p = provider((_) => http.Response('not json $_sentinel', 200));
      expectSanitized(
        await failure(() => p.getFileMetadata('x')),
        CloudStorageErrorCode.malformedResponse,
      );
    });

    test('missing required field -> malformedResponse', () async {
      final p = provider((_) => json({'name': _sentinel}));
      expectSanitized(
        await failure(() => p.getFileMetadata('x')),
        CloudStorageErrorCode.malformedResponse,
      );
    });

    test('wrong field type -> malformedResponse', () async {
      final p = provider((_) => json({'id': 1, 'name': _sentinel}));
      expectSanitized(
        await failure(() => p.getFileMetadata('x')),
        CloudStorageErrorCode.malformedResponse,
      );
    });

    test('any other exception -> unknown, never rethrown raw', () async {
      final p = provider((_) => throw StateError(_sentinel));
      expectSanitized(
        await failure(() => p.downloadFile('x')),
        CloudStorageErrorCode.unknown,
      );
    });
  });

  group('auth service failures', () {
    test('typed CloudStorageException passes through unchanged', () async {
      auth.connectError = const CloudStorageException(
        CloudStorageErrorCode.cancelled,
      );
      final p = provider((_) => json({}));
      expectSanitized(
        await failure(p.connect),
        CloudStorageErrorCode.cancelled,
      );
    });

    test(
      'GoogleAuthorizationRequiredException -> authorizationRequired',
      () async {
        auth.tokenError = const GoogleAuthorizationRequiredException();
        final p = provider((_) => json({}));
        expectSanitized(
          await failure(() => p.downloadFile('x')),
          CloudStorageErrorCode.authorizationRequired,
        );
        expect(requests, isEmpty, reason: 'no request without a token');
      },
    );

    test(
      'raw sign-in failure with a token in the message -> unknown',
      () async {
        auth.connectError = Exception('raw $_sentinel');
        final p = provider((_) => json({}));
        expectSanitized(
          await failure(p.connect),
          CloudStorageErrorCode.unknown,
        );
      },
    );

    test(
      'adapter never throws GoogleSignIn/HTTP types (exhaustive sweep)',
      () async {
        final raws = <Object>[
          Exception(_sentinel),
          StateError(_sentinel),
          ArgumentError(_sentinel),
          FormatException(_sentinel),
          TimeoutException(_sentinel),
          SocketException(_sentinel),
          http.ClientException(_sentinel),
          const GoogleAuthorizationRequiredException(),
          const CloudStorageException(CloudStorageErrorCode.forbidden),
        ];
        for (final raw in raws) {
          auth.connectError = raw;
          final p = provider((_) => json({}));
          final e = await failure(p.connect);
          expect(
            e,
            isA<CloudStorageException>(),
            reason: raw.runtimeType.toString(),
          );
          expect(e.toString(), isNot(contains('SENTINEL')));
        }
      },
    );
  });
}

class _FakeAuth implements DriveAuthService {
  final List<bool> forceRefreshFlags = [];
  int connectCalls = 0;
  bool connected = false;
  Object? connectError;
  Object? tokenError;
  DriveAccountSummary account = DriveAccountSummary.fallback;

  @override
  Future<void> connect() async {
    connectCalls += 1;
    if (connectError != null) throw connectError!;
    connected = true;
  }

  @override
  Future<void> disconnect() async => connected = false;

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<DriveAccountSummary> getConnectedAccountSummary() async => account;

  @override
  Future<String> getValidAccessToken({bool forceRefresh = false}) async {
    if (tokenError != null) throw tokenError!;
    forceRefreshFlags.add(forceRefresh);
    return 'token-${forceRefreshFlags.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed here');
}
