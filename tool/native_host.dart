import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/services/vault_autofill_matcher.dart';

Future<void> main() async {
  final bytesBuilder = BytesBuilder(copy: false);
  await for (final chunk in stdin) {
    bytesBuilder.add(chunk);
  }

  final payload = bytesBuilder.takeBytes();
  if (payload.isEmpty) {
    return;
  }

  final messages = _decodeNativeMessages(payload);
  for (final message in messages) {
    final response = await _handleMessage(message);
    stdout.add(_encodeNativeMessage(response));
  }
}

Future<Map<String, Object?>> _handleMessage(
  Map<String, Object?> message,
) async {
  final type = message['type'] as String?;
  if (type != 'findCredentials') {
    return {'ok': false, 'error': 'Unsupported message type: $type'};
  }

  final databasePath = (message['databasePath'] as String?)?.trim() ?? '';
  final masterPassword = (message['masterPassword'] as String?)?.trim() ?? '';
  final keyFilePath = (message['keyFilePath'] as String?)?.trim();
  final url = (message['url'] as String?)?.trim() ?? '';
  final requestedLimit = message['limit'];
  final limit = requestedLimit is num ? requestedLimit.toInt().clamp(1, 10) : 5;

  final canUseDirectVault =
      databasePath.isNotEmpty &&
      (masterPassword.isNotEmpty ||
          (keyFilePath != null && keyFilePath.isNotEmpty));

  if (!canUseDirectVault) {
    final bridged = await _findCredentialsViaRunningApp(url: url, limit: limit);
    if (bridged['ok'] == true) {
      return bridged;
    }

    return {
      'ok': false,
      'error':
          'Running app session unavailable. Open KeyVault desktop app or provide databasePath + masterPassword in extension popup.',
      'details': bridged['error'],
    };
  }

  try {
    final service = VaultKdbxService();
    final matcher = VaultAutofillMatcher();

    final allEntries = await service.loadAllEntries(
      databasePath: databasePath,
      password: masterPassword,
      keyFilePath: keyFilePath?.isEmpty == true ? null : keyFilePath,
    );

    final host = _extractHost(url);
    final roughMatches = matcher.findBestMatches(
      entries: allEntries,
      webDomains: host.isEmpty ? const {} : {host},
      limit: limit,
    );
    final matches = _filterMatchesByHost(
      roughMatches,
      host,
    ).take(limit).toList(growable: false);

    final credentials = matches
        .map(
          (entry) => {
            'id': entry.id,
            'title': entry.title,
            'username': entry.username,
            'password': entry.password,
            'url': entry.url,
          },
        )
        .toList(growable: false);

    return {'ok': true, 'credentials': credentials};
  } catch (error) {
    return {'ok': false, 'error': 'Failed to load credentials: $error'};
  }
}

Future<Map<String, Object?>> _findCredentialsViaRunningApp({
  required String url,
  required int limit,
}) async {
  try {
    final config = await _readBridgeConfig();
    if (config == null) {
      return {'ok': false, 'error': 'Bridge config not found.'};
    }

    var response = await _callBridge(config: config, url: url, limit: limit);
    if ((response['httpStatus'] as int?) == HttpStatus.unauthorized) {
      final refreshedConfig = await _readBridgeConfig();
      if (refreshedConfig != null) {
        response = await _callBridge(
          config: refreshedConfig,
          url: url,
          limit: limit,
        );
      }
    }

    final body = response['body'];
    if (body is Map<String, Object?>) {
      return body;
    }

    return {'ok': false, 'error': 'Invalid response from running app.'};
  } catch (error) {
    return {'ok': false, 'error': '$error'};
  }
}

Future<Map<String, Object?>?> _readBridgeConfig() async {
  final bridgeFile = File(_bridgeFilePath());
  if (!await bridgeFile.exists()) {
    return null;
  }

  final decoded = jsonDecode(await bridgeFile.readAsString());
  if (decoded is! Map) {
    return null;
  }

  return decoded.cast<String, Object?>();
}

Future<Map<String, Object?>> _callBridge({
  required Map<String, Object?> config,
  required String url,
  required int limit,
}) async {
  final host = config['host'] as String?;
  final port = config['port'] as num?;
  final token = config['token'] as String?;

  if (host == null || port == null || token == null || token.isEmpty) {
    return {
      'httpStatus': 0,
      'body': {'ok': false, 'error': 'Bridge config missing fields.'},
    };
  }

  final client = HttpClient();
  try {
    final request = await client.post(host, port.toInt(), '/v1/find');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'url': url, 'limit': limit}));

    final response = await request.close();
    final bodyText = await utf8.decoder.bind(response).join();
    final decodedBody = jsonDecode(bodyText);

    if (decodedBody is Map) {
      return {
        'httpStatus': response.statusCode,
        'body': decodedBody.cast<String, Object?>(),
      };
    }

    return {
      'httpStatus': response.statusCode,
      'body': {'ok': false, 'error': 'Bridge body is not JSON map.'},
    };
  } finally {
    client.close();
  }
}

Iterable<VaultEntry> _filterMatchesByHost(
  List<VaultEntry> entries,
  String host,
) {
  if (host.isEmpty) {
    return const [];
  }

  return entries.where((entry) {
    final entryHost = _extractHost(entry.url);
    if (entryHost.isEmpty) {
      return false;
    }
    return _hostsMatch(host, entryHost);
  });
}

bool _hostsMatch(String requestedHost, String credentialHost) {
  if (requestedHost == credentialHost) {
    return true;
  }
  if (requestedHost.endsWith('.$credentialHost')) {
    return true;
  }
  if (credentialHost.endsWith('.$requestedHost')) {
    return true;
  }
  return false;
}

String _bridgeFilePath() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return '$appData\\KeyVaultAutofill\\bridge.json';
    }
  }

  final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
  return '$home/.keyvault_autofill/bridge.json';
}

List<Map<String, Object?>> _decodeNativeMessages(Uint8List payload) {
  final messages = <Map<String, Object?>>[];
  var offset = 0;

  while (offset + 4 <= payload.length) {
    final lengthBytes = payload.sublist(offset, offset + 4);
    final length = ByteData.sublistView(
      Uint8List.fromList(lengthBytes),
    ).getUint32(0, Endian.little);
    offset += 4;

    if (length <= 0 || offset + length > payload.length) {
      break;
    }

    final jsonBytes = payload.sublist(offset, offset + length);
    offset += length;

    final decoded = jsonDecode(utf8.decode(jsonBytes));
    if (decoded is Map) {
      messages.add(decoded.cast<String, Object?>());
    }
  }

  return messages;
}

Uint8List _encodeNativeMessage(Map<String, Object?> message) {
  final jsonString = jsonEncode(message);
  final jsonBytes = utf8.encode(jsonString);
  final header = ByteData(4)..setUint32(0, jsonBytes.length, Endian.little);

  final output = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(jsonBytes);
  return output.toBytes();
}

String _extractHost(String rawUrl) {
  if (rawUrl.isEmpty) {
    return '';
  }

  final uri = Uri.tryParse(rawUrl);
  if (uri == null || uri.host.isEmpty) {
    return '';
  }

  final host = uri.host.toLowerCase();
  if (host.startsWith('www.')) {
    return host.substring(4);
  }
  return host;
}
