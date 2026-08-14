import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';

// =============================================================================
// spec 008 Gate 0 (T005) — Drive conditional upload spike.
//
// SCOPE AND HONESTY WARNING
// ------------------------
// These tests run against a FAKE in-process HTTP transport. They can prove:
//
//   * the SHAPE of a conditional request is expressible over `http.Client`;
//   * the CLIENT-SIDE outcome classification required by spec FR-10, i.e. that
//     an HTTP rejection and a post-dispatch transport timeout are handled as
//     two different things.
//
// They can NOT prove that Google Drive's servers actually enforce the
// precondition. Server enforcement is a property of Google's infrastructure
// and needs live-network evidence. Gate 0 therefore records the Drive
// concurrency token as `not-run`, which keeps the feature disabled.
// =============================================================================

void main() {
  group('conditional update', () {
    late _FakeDriveServer server;

    setUp(() {
      server = _FakeDriveServer(
        fileId: 'file-1',
        bytes: Uint8List.fromList(const [1, 2, 3]),
      );
    });

    test('server-enforced token is required: an unconditional PATCH '
        'overwrites a remote that moved under us', () async {
      // This is what the CURRENT production `updateFile` does. It is the
      // failure mode spec FR-7/FR-10 exist to remove.
      final staleToken = server.etag;
      server.applyExternalEdit(Uint8List.fromList(const [9, 9, 9]));

      final outcome = await _spikeConditionalUpdate(
        client: server.client,
        fileId: server.fileId,
        bytes: Uint8List.fromList(const [7, 7, 7]),
        ifMatchEtag: null, // no precondition -> unconditional overwrite
      );

      expect(outcome.classification, _UploadOutcome.appliedDefinite);
      expect(
        server.bytes,
        orderedEquals(const [7, 7, 7]),
        reason: 'without a precondition the concurrent edit is silently lost',
      );
      expect(staleToken, isNot(server.etag));
    });

    test('conditional update applies when the token still matches', () async {
      final token = server.etag;
      final version = server.version;

      final outcome = await _spikeConditionalUpdate(
        client: server.client,
        fileId: server.fileId,
        bytes: Uint8List.fromList(const [4, 5, 6]),
        ifMatchEtag: token,
      );

      expect(outcome.classification, _UploadOutcome.appliedDefinite);
      expect(server.bytes, orderedEquals(const [4, 5, 6]));
      // The token is a real concurrency token: it moves on every write.
      expect(server.etag, isNot(token));
      expect(server.version, greaterThan(version));
      // spec FR-10: a definite success must be verifiable by refetching the
      // merged checksum, not by trusting the response.
      expect(
        outcome.remote!.md5Checksum,
        md5.convert(const [4, 5, 6]).toString(),
      );
    });

    test('conditional rejection proves the write was NOT applied', () async {
      final staleToken = server.etag;
      server.applyExternalEdit(Uint8List.fromList(const [9, 9, 9]));
      final remoteAfterExternalEdit = server.etag;

      final outcome = await _spikeConditionalUpdate(
        client: server.client,
        fileId: server.fileId,
        bytes: Uint8List.fromList(const [7, 7, 7]),
        ifMatchEtag: staleToken,
      );

      expect(outcome.classification, _UploadOutcome.rejectedNotApplied);
      expect(outcome.statusCode, HttpStatus.preconditionFailed);
      // Certainty: remote content and token are byte-for-byte untouched.
      expect(server.bytes, orderedEquals(const [9, 9, 9]));
      expect(server.etag, remoteAfterExternalEdit);
      expect(server.writeCount, 1, reason: 'only the external edit landed');
    });

    test('rejection must never be retried against the changed token', () async {
      final staleToken = server.etag;
      server.applyExternalEdit(Uint8List.fromList(const [9, 9, 9]));

      final first = await _spikeConditionalUpdate(
        client: server.client,
        fileId: server.fileId,
        bytes: Uint8List.fromList(const [7, 7, 7]),
        ifMatchEtag: staleToken,
      );
      expect(first.classification, _UploadOutcome.rejectedNotApplied);

      // spec FR-10: refetch and surface a NEW conflict. Blindly re-sending
      // with the freshly observed token would resurrect the clobber bug.
      final blindRetry = await _spikeConditionalUpdate(
        client: server.client,
        fileId: server.fileId,
        bytes: Uint8List.fromList(const [7, 7, 7]),
        ifMatchEtag: server.etag,
      );
      expect(
        blindRetry.classification,
        _UploadOutcome.appliedDefinite,
        reason:
            'documents WHY a blind retry is forbidden: it succeeds and '
            'destroys the concurrent edit the rejection just protected',
      );
      expect(server.bytes, orderedEquals(const [7, 7, 7]));
    });

    // -----------------------------------------------------------------------
    // Ambiguity: the client cannot tell these two apart, and must not guess.
    // -----------------------------------------------------------------------
    test(
      'timeout after dispatch is ambiguous even though it APPLIED',
      () async {
        server.dropConnectionAfterApplying = true;

        final outcome = await _spikeConditionalUpdate(
          client: server.client,
          fileId: server.fileId,
          bytes: Uint8List.fromList(const [4, 5, 6]),
          ifMatchEtag: server.etag,
        );

        expect(outcome.classification, _UploadOutcome.ambiguous);
        expect(outcome.statusCode, isNull);
        // Ground truth the client is NOT allowed to know: it did apply.
        expect(server.bytes, orderedEquals(const [4, 5, 6]));
      },
    );

    test('timeout after dispatch is ambiguous when it did NOT apply', () async {
      server.dropConnectionBeforeApplying = true;

      final outcome = await _spikeConditionalUpdate(
        client: server.client,
        fileId: server.fileId,
        bytes: Uint8List.fromList(const [4, 5, 6]),
        ifMatchEtag: server.etag,
      );

      expect(outcome.classification, _UploadOutcome.ambiguous);
      // Ground truth: it did not apply.
      expect(server.bytes, orderedEquals(const [1, 2, 3]));
    });

    test(
      'the two ambiguous cases are indistinguishable to the client',
      () async {
        final applied = _FakeDriveServer(
          fileId: 'a',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        )..dropConnectionAfterApplying = true;
        final notApplied = _FakeDriveServer(
          fileId: 'a',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        )..dropConnectionBeforeApplying = true;

        final a = await _spikeConditionalUpdate(
          client: applied.client,
          fileId: 'a',
          bytes: Uint8List.fromList(const [4, 5, 6]),
          ifMatchEtag: applied.etag,
        );
        final b = await _spikeConditionalUpdate(
          client: notApplied.client,
          fileId: 'a',
          bytes: Uint8List.fromList(const [4, 5, 6]),
          ifMatchEtag: notApplied.etag,
        );

        expect(a.classification, b.classification);
        expect(a.classification, _UploadOutcome.ambiguous);
        // Therefore recovery MUST triage by refetching remote state (FR-10),
        // and may never mark the mapping synced from the upload result alone.
        expect(applied.bytes, isNot(orderedEquals(notApplied.bytes)));
      },
    );

    test(
      'post-dispatch triage distinguishes applied from not-applied',
      () async {
        // spec FR-10 steps 5/6: after an ambiguous outcome, compare the remote
        // checksum against the merged checksum and the expected old checksum.
        final merged = Uint8List.fromList(const [4, 5, 6]);
        final mergedChecksum = md5.convert(merged).toString();
        final oldChecksum = md5.convert(const [1, 2, 3]).toString();

        final applied = _FakeDriveServer(fileId: 'a', bytes: merged);
        final notApplied = _FakeDriveServer(
          fileId: 'a',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        );
        final thirdState = _FakeDriveServer(
          fileId: 'a',
          bytes: Uint8List.fromList(const [8, 8, 8]),
        );

        expect(
          _triage(applied.checksum, mergedChecksum, oldChecksum),
          _RecoveryBranch.finalizeMapping,
        );
        expect(
          _triage(notApplied.checksum, mergedChecksum, oldChecksum),
          _RecoveryBranch.retryConditionalUpload,
        );
        expect(
          _triage(thirdState.checksum, mergedChecksum, oldChecksum),
          _RecoveryBranch.openNewConflict,
        );
      },
    );

    // -----------------------------------------------------------------------
    // Blocking evidence about the CURRENT production code and model.
    // -----------------------------------------------------------------------
    test('production updateFile currently sends no precondition', () {
      final source = File(
        'lib/features/password_manager/data/services/'
        'google_drive_api_service.dart',
      ).readAsStringSync();

      expect(
        source.contains('If-Match'),
        isFalse,
        reason: 'documents the Gate 0 gap that T401 must close',
      );
      expect(source.contains('ifMatch'), isFalse);
      // The upload is a plain unconditional media PATCH.
      expect(source, contains("'uploadType': 'media'"));

      // Drive is called through a raw `http.Client`, not a generated API
      // client, and the header map is spread at the call site. Sending
      // `If-Match` is therefore a one-line client-side change: nothing in the
      // transport blocks it. What is unproven is whether the SERVER enforces
      // it — that is blocker B1, and only a live-network spike can close it.
      expect(source, contains('_httpClient.patch('));
      expect(source, contains('headers: {...headers,'));
    });

    test('DriveRemoteFile carries no concurrency token', () {
      // The model declares exactly four fields, none of which is a
      // server-enforceable precondition token. Asserted against the source,
      // because `props` is a list of VALUES: `isNot(contains('etag'))` on it
      // would pass even if an `etag` field existed.
      final source = File(
        'lib/features/password_manager/domain/models/drive_remote_file.dart',
      ).readAsStringSync();
      final fields = RegExp(
        r'^\s*final\s+[\w<>?]+\s+(\w+);',
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)).toList();
      expect(fields, <String>['id', 'name', 'modifiedTime', 'md5Checksum']);
      for (final token in const ['etag', 'version', 'headRevisionId']) {
        expect(
          fields,
          isNot(contains(token)),
          reason: '$token would be the only candidate precondition token',
        );
      }

      // `md5Checksum` is content-derived, not a concurrency token: two
      // different remote generations with identical content share it, so it
      // cannot serialize writes on its own.
      const first = DriveRemoteFile(id: 'a', name: 'a.kdbx', md5Checksum: 'x');
      const second = DriveRemoteFile(id: 'a', name: 'a.kdbx', md5Checksum: 'x');
      expect(
        first,
        second,
        reason: 'no field distinguishes two remote generations',
      );
    });
  });
}

// =============================================================================
// spec 008 Gate 0 spike support (test-only).
// =============================================================================

enum _UploadOutcome {
  /// Server answered 2xx. The write is known to have been applied.
  appliedDefinite,

  /// Server answered with a precondition failure. The write is known NOT to
  /// have been applied.
  rejectedNotApplied,

  /// The request was dispatched but no response arrived. The write may or may
  /// not have been applied; the client must not guess.
  ambiguous,
}

class _UploadResult {
  const _UploadResult({
    required this.classification,
    this.statusCode,
    this.remote,
  });

  final _UploadOutcome classification;
  final int? statusCode;
  final DriveRemoteFile? remote;
}

enum _RecoveryBranch {
  finalizeMapping,
  retryConditionalUpload,
  openNewConflict,
}

/// spec FR-10 remote triage after an ambiguous transport outcome.
_RecoveryBranch _triage(
  String remoteChecksum,
  String mergedChecksum,
  String expectedOldChecksum,
) {
  if (remoteChecksum == mergedChecksum) {
    return _RecoveryBranch.finalizeMapping;
  }
  if (remoteChecksum == expectedOldChecksum) {
    return _RecoveryBranch.retryConditionalUpload;
  }
  return _RecoveryBranch.openNewConflict;
}

/// The conditional-upload shape a future `GoogleDriveApiService.updateFile`
/// would use. Test-only; nothing here is imported by `lib/`.
Future<_UploadResult> _spikeConditionalUpdate({
  required http.Client client,
  required String fileId,
  required Uint8List bytes,
  required String? ifMatchEtag,
}) async {
  final uri = Uri.parse(
    'https://www.googleapis.com/upload/drive/v3/files/$fileId',
  ).replace(queryParameters: {'uploadType': 'media'});

  final http.Response response;
  try {
    response = await client.patch(
      uri,
      headers: {
        'Authorization': 'Bearer fake-test-token',
        'Content-Type': 'application/octet-stream',
        'If-Match': ?ifMatchEtag,
      },
      body: bytes,
    );
  } on http.ClientException {
    // Request was dispatched; no usable response came back.
    return const _UploadResult(classification: _UploadOutcome.ambiguous);
  } on TimeoutException {
    return const _UploadResult(classification: _UploadOutcome.ambiguous);
  }

  if (response.statusCode == HttpStatus.preconditionFailed) {
    return _UploadResult(
      classification: _UploadOutcome.rejectedNotApplied,
      statusCode: response.statusCode,
    );
  }
  if (response.statusCode >= 200 && response.statusCode < 300) {
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return _UploadResult(
      classification: _UploadOutcome.appliedDefinite,
      statusCode: response.statusCode,
      remote: DriveRemoteFile(
        id: payload['id'] as String,
        name: payload['name'] as String,
        md5Checksum: payload['md5Checksum'] as String?,
      ),
    );
  }
  // Any other status is neither a proven rejection nor a proven success.
  return _UploadResult(
    classification: _UploadOutcome.ambiguous,
    statusCode: response.statusCode,
  );
}

/// Minimal in-process stand-in for a Drive-like file endpoint that enforces
/// `If-Match`. It models the behaviour the real service MUST be verified to
/// have; it is not evidence that the real service has it.
class _FakeDriveServer {
  _FakeDriveServer({required this.fileId, required Uint8List bytes})
    : _bytes = bytes;

  final String fileId;
  Uint8List _bytes;
  int version = 1;
  int writeCount = 0;

  bool dropConnectionBeforeApplying = false;
  bool dropConnectionAfterApplying = false;

  Uint8List get bytes => _bytes;
  String get checksum => md5.convert(_bytes).toString();
  String get etag => '"v$version-$checksum"';

  void applyExternalEdit(Uint8List newBytes) {
    _bytes = newBytes;
    version++;
    writeCount++;
  }

  http.Client get client => MockClient((request) async {
    if (request.method != 'PATCH') {
      return http.Response('unsupported', HttpStatus.methodNotAllowed);
    }

    final ifMatch = request.headers['If-Match'];
    if (ifMatch != null && ifMatch != etag) {
      // Server-enforced rejection: nothing is mutated.
      return http.Response('', HttpStatus.preconditionFailed);
    }

    if (dropConnectionBeforeApplying) {
      throw http.ClientException(
        'connection closed before response',
        request.url,
      );
    }

    _bytes = Uint8List.fromList(request.bodyBytes);
    version++;
    writeCount++;

    if (dropConnectionAfterApplying) {
      throw http.ClientException(
        'connection closed after response',
        request.url,
      );
    }

    return http.Response(
      jsonEncode({'id': fileId, 'name': 'vault.kdbx', 'md5Checksum': checksum}),
      HttpStatus.ok,
      headers: {'etag': etag},
    );
  });
}
