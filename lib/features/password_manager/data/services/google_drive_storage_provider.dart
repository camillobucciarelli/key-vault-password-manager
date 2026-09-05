import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:loggy/loggy.dart';

import '../../domain/errors/google_authorization_required_exception.dart';
import '../../domain/models/cloud_storage_error.dart';
import '../../domain/models/remote_file.dart';
import '../../domain/models/storage_account_summary.dart';
import '../../domain/repositories/cloud_storage_provider.dart';
import 'drive_auth_service.dart';
import 'google_drive_api_service.dart';

/// spec 010 — the sole `CloudStorageProvider` implementation. Composes the
/// existing data-private Google services and is the trust boundary: every
/// call runs inside [_guard], so nothing but a `CloudStorageException` leaves
/// this class. OAuth, scopes, token refresh and query syntax stay inside
/// `DriveAuthService` / `GoogleDriveApiService`.
class GoogleDriveStorageProvider implements CloudStorageProvider {
  GoogleDriveStorageProvider({
    required DriveAuthService authService,
    required GoogleDriveApiService apiService,
  }) : _auth = authService,
       _api = apiService;

  static const String id = googleDriveProviderId;

  final DriveAuthService _auth;
  final GoogleDriveApiService _api;

  @override
  String get providerId => id;

  @override
  Future<bool> isConnected() => _guard(_auth.isConnected);

  @override
  Future<void> connect() => _guard(_auth.connect);

  @override
  Future<void> disconnect() => _guard(_auth.disconnect);

  @override
  Future<List<RemoteFile>> listKdbxFiles({String? query}) =>
      _guard(() => _api.listKdbxFilesInDrive(query: query));

  @override
  Future<RemoteFile> getFileMetadata(String remoteFileId) =>
      _guard(() => _api.getFileMetadata(remoteFileId));

  @override
  Future<RemoteFile> createFile({
    required String name,
    required Uint8List bytes,
  }) => _guard(() => _api.createFile(fileName: name, bytes: bytes));

  @override
  Future<RemoteFile> updateFile({
    required String remoteFileId,
    required Uint8List bytes,
  }) => _guard(() => _api.updateFile(fileId: remoteFileId, bytes: bytes));

  @override
  Future<Uint8List> downloadFile(String remoteFileId) =>
      _guard(() => _api.downloadFile(remoteFileId));

  @override
  Future<StorageAccountSummary> getConnectedAccount() =>
      _guard(_auth.getConnectedAccountSummary);

  /// spec 010 Google/transport mapping table. Typed failures the Google
  /// services already classified pass through; transport and decoding
  /// failures are classified here; anything else is deterministically
  /// `unknown`. Only the runtime type is logged — never the message, which
  /// may carry a URL, token or response body.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on CloudStorageException {
      rethrow;
    } catch (error) {
      final code = switch (error) {
        GoogleAuthorizationRequiredException() =>
          CloudStorageErrorCode.authorizationRequired,
        TimeoutException() => CloudStorageErrorCode.timeout,
        SocketException() ||
        http.ClientException() => CloudStorageErrorCode.networkUnavailable,
        FormatException() ||
        TypeError() => CloudStorageErrorCode.malformedResponse,
        _ => CloudStorageErrorCode.unknown,
      };
      logWarning(
        'Google Drive call failed: ${error.runtimeType} -> ${code.name}',
      );
      throw CloudStorageException(code);
    }
  }
}
