import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/models/drive_remote_folder.dart';
import '../../domain/models/drive_remote_file.dart';
import 'drive_auth_service.dart';

class GoogleDriveApiService {
  GoogleDriveApiService({
    required DriveAuthService driveAuthService,
    required http.Client httpClient,
  }) : _driveAuthService = driveAuthService,
       _httpClient = httpClient;

  static const _apiBase = 'https://www.googleapis.com/drive/v3';
  static const _uploadBase = 'https://www.googleapis.com/upload/drive/v3';

  final DriveAuthService _driveAuthService;
  final http.Client _httpClient;

  Future<List<DriveRemoteFile>> listKdbxFilesInDrive() async {
    final uri = Uri.parse('$_apiBase/files').replace(
      queryParameters: {
        'spaces': 'drive',
        'q':
            "mimeType != 'application/vnd.google-apps.folder' and trashed = false and name contains '.kdbx'",
        'fields': 'files(id,name,modifiedTime,md5Checksum)',
        'pageSize': '200',
        'orderBy': 'modifiedTime desc',
      },
    );

    final response = await _authedGet(uri);
    _ensureSuccess(response, 'Unable to list Drive files');

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final files = payload['files'];
    if (files is! List) {
      return const [];
    }

    return files
        .whereType<Map<String, dynamic>>()
        .map(_mapRemoteFile)
        .toList(growable: false);
  }

  Future<List<DriveRemoteFolder>> listFoldersInDrive({String? query}) async {
    const baseQuery =
        "mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final normalizedQuery = query?.trim();
    final driveQuery = normalizedQuery == null || normalizedQuery.isEmpty
        ? baseQuery
        : "$baseQuery and name contains '${_escapeDriveQueryLiteral(normalizedQuery)}'";

    final uri = Uri.parse('$_apiBase/files').replace(
      queryParameters: {
        'spaces': 'drive',
        'q': driveQuery,
        'fields': 'files(id,name)',
        'pageSize': '200',
        'orderBy': 'name',
      },
    );

    final response = await _authedGet(uri);
    _ensureSuccess(response, 'Unable to list Drive folders');

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final files = payload['files'];
    if (files is! List) {
      return const [];
    }

    return files
        .whereType<Map<String, dynamic>>()
        .map(
          (map) => DriveRemoteFolder(
            id: map['id'] as String,
            name: map['name'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<DriveRemoteFile> getFileMetadata(String fileId) async {
    final uri = Uri.parse(
      '$_apiBase/files/$fileId',
    ).replace(queryParameters: {'fields': 'id,name,modifiedTime,md5Checksum'});

    final response = await _authedGet(uri);
    _ensureSuccess(response, 'Unable to fetch Drive file metadata');
    return _mapRemoteFile(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<DriveRemoteFile> createFile({
    required String fileName,
    required Uint8List bytes,
    String? parentFolderId,
  }) async {
    final boundary = _generateBoundary();
    final uri = Uri.parse(
      '$_uploadBase/files',
    ).replace(queryParameters: {'uploadType': 'multipart'});

    final metadata = jsonEncode({
      'name': fileName,
      if (parentFolderId != null && parentFolderId.trim().isNotEmpty)
        'parents': [parentFolderId.trim()],
    });
    final body = _buildMultipartBody(
      boundary: boundary,
      metadataJson: metadata,
      bytes: bytes,
    );

    final response = await _authedRequest(
      (headers) => _httpClient.post(
        uri,
        headers: {
          ...headers,
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      ),
    );

    _ensureSuccess(response, 'Unable to create Drive file');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return getFileMetadata(payload['id'] as String);
  }

  Future<DriveRemoteFile> updateFile({
    required String fileId,
    required Uint8List bytes,
  }) async {
    final uri = Uri.parse(
      '$_uploadBase/files/$fileId',
    ).replace(queryParameters: {'uploadType': 'media'});

    final response = await _authedRequest(
      (headers) => _httpClient.patch(
        uri,
        headers: {...headers, 'Content-Type': 'application/octet-stream'},
        body: bytes,
      ),
    );
    _ensureSuccess(response, 'Unable to update Drive file');
    return getFileMetadata(fileId);
  }

  Future<Uint8List> downloadFile(String fileId) async {
    final uri = Uri.parse(
      '$_apiBase/files/$fileId',
    ).replace(queryParameters: {'alt': 'media'});

    final response = await _authedGet(uri);
    _ensureSuccess(response, 'Unable to download Drive file');
    return response.bodyBytes;
  }

  Future<http.Response> _authedGet(Uri uri) {
    return _authedRequest((headers) => _httpClient.get(uri, headers: headers));
  }

  Future<http.Response> _authedRequest(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    final token = await _driveAuthService.getValidAccessToken();
    var response = await request({'Authorization': 'Bearer $token'});

    if (response.statusCode != 401) {
      return response;
    }

    final refreshedToken = await _driveAuthService.getValidAccessToken();
    response = await request({'Authorization': 'Bearer $refreshedToken'});
    return response;
  }

  DriveRemoteFile _mapRemoteFile(Map<String, dynamic> map) {
    return DriveRemoteFile(
      id: map['id'] as String,
      name: map['name'] as String,
      modifiedTime: map['modifiedTime'] == null
          ? null
          : DateTime.tryParse(map['modifiedTime'] as String)?.toLocal(),
      md5Checksum: map['md5Checksum'] as String?,
    );
  }

  void _ensureSuccess(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$message (${response.statusCode}).');
    }
  }

  String _generateBoundary() {
    return 'boundary-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _escapeDriveQueryLiteral(String value) {
    return value.replaceAll('\\', r'\\').replaceAll("'", r"\'");
  }

  Uint8List _buildMultipartBody({
    required String boundary,
    required String metadataJson,
    required Uint8List bytes,
  }) {
    final preamble = StringBuffer()
      ..write('--$boundary\r\n')
      ..write('Content-Type: application/json; charset=UTF-8\r\n\r\n')
      ..write(metadataJson)
      ..write('\r\n')
      ..write('--$boundary\r\n')
      ..write('Content-Type: application/octet-stream\r\n\r\n');

    final closing = '\r\n--$boundary--';
    final preambleBytes = utf8.encode(preamble.toString());
    final closingBytes = utf8.encode(closing);

    return Uint8List.fromList([...preambleBytes, ...bytes, ...closingBytes]);
  }
}
