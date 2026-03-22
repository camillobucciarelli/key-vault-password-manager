import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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

  Future<List<DriveRemoteFile>> listKdbxFilesInDrive({String? query}) async {
    const baseQuery =
        "mimeType != 'application/vnd.google-apps.folder' and trashed = false and name contains '.kdbx'";
    final normalizedQuery = query?.trim() ?? '';
    if (normalizedQuery.isEmpty) {
      return _fetchKdbxFiles(driveQuery: baseQuery);
    }

    final queryTerms = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);

    final serverQuery = queryTerms.isEmpty
        ? baseQuery
        : '$baseQuery and ${queryTerms.map((term) => "name contains '${_escapeDriveQueryLiteral(term)}'").join(' and ')}';

    final serverResults = await _fetchKdbxFiles(driveQuery: serverQuery);
    if (serverResults.isNotEmpty) {
      return serverResults;
    }

    final fallbackResults = await _fetchKdbxFiles(driveQuery: baseQuery);
    final normalizedLower = normalizedQuery.toLowerCase();
    return fallbackResults
        .where((file) => file.name.toLowerCase().contains(normalizedLower))
        .toList(growable: false);
  }

  Future<List<DriveRemoteFile>> _fetchKdbxFiles({
    required String driveQuery,
  }) async {
    final collected = <DriveRemoteFile>[];
    String? nextPageToken;

    do {
      final queryParameters = <String, String>{
        'spaces': 'drive',
        'q': driveQuery,
        'fields': 'nextPageToken,files(id,name,modifiedTime,md5Checksum)',
        'pageSize': '1000',
        'orderBy': 'modifiedTime desc',
        'supportsAllDrives': 'true',
        'includeItemsFromAllDrives': 'true',
      };
      if (nextPageToken != null) {
        queryParameters['pageToken'] = nextPageToken;
      }

      final uri = Uri.parse(
        '$_apiBase/files',
      ).replace(queryParameters: queryParameters);

      final response = await _authedGet(uri);
      _ensureSuccess(response, 'Unable to list Drive files');

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final files = payload['files'];
      if (files is List) {
        collected.addAll(
          files.whereType<Map<String, dynamic>>().map(_mapRemoteFile),
        );
      }
      nextPageToken = payload['nextPageToken'] as String?;
    } while (nextPageToken != null && nextPageToken.isNotEmpty);

    return List<DriveRemoteFile>.unmodifiable(collected);
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
  }) async {
    final boundary = _generateBoundary();
    final uri = Uri.parse(
      '$_uploadBase/files',
    ).replace(queryParameters: {'uploadType': 'multipart'});

    final metadata = jsonEncode({'name': fileName});
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

    final refreshedToken = await _driveAuthService.getValidAccessToken(
      forceRefresh: true,
    );
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
