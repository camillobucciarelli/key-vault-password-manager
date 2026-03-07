import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
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
    final matches = matcher.findBestMatches(
      entries: allEntries,
      webDomains: host.isEmpty ? const {} : {host},
      limit: limit,
    );

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
    final bridgeFile = File(_bridgeFilePath());
    if (!await bridgeFile.exists()) {
      return {'ok': false, 'error': 'Bridge config not found.'};
    }

    final decoded = jsonDecode(await bridgeFile.readAsString());
    if (decoded is! Map) {
      return {'ok': false, 'error': 'Invalid bridge config.'};
    }

    final config = decoded.cast<String, Object?>();
    final host = config['host'] as String?;
    final port = config['port'] as num?;
    final token = config['token'] as String?;

    if (host == null || port == null || token == null || token.isEmpty) {
      return {'ok': false, 'error': 'Bridge config missing fields.'};
    }

    final client = HttpClient();
    try {
      final request = await client.post(host, port.toInt(), '/v1/find');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'url': url, 'limit': limit}));

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final parsed = jsonDecode(body);
      if (parsed is Map) {
        return parsed.cast<String, Object?>();
      }

      return {'ok': false, 'error': 'Invalid response from running app.'};
    } finally {
      client.close();
    }
  } catch (error) {
    return {'ok': false, 'error': '$error'};
  }
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
