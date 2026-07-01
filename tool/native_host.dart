import 'dart:io';

import 'native_host_protocol.dart';

Future<void> main() async {
  final reader = NativeMessageStreamReader(stdin);

  while (true) {
    final Map<String, Object?>? request;
    try {
      request = await reader.readMessage();
    } on NativeHostProtocolException catch (error) {
      _logProtocolError(error);
      stdout.add(
        encodeNativeMessage(
          nativeHostErrorResponse(
            type: 'error',
            code: error.code,
            message: error.publicMessage,
          ),
        ),
      );
      await stdout.flush();
      if (!error.canContinue) {
        return;
      }
      continue;
    } catch (_) {
      stderr.writeln('[KeyVault native host] internal_error');
      stdout.add(
        encodeNativeMessage(
          nativeHostErrorResponse(
            type: 'error',
            code: 'internal_error',
            message: 'Native host failed to process the request.',
          ),
        ),
      );
      await stdout.flush();
      return;
    }

    if (request == null) {
      return;
    }

    final response = await handleNativeHostRequest(request);
    stdout.add(encodeNativeMessage(response));
    await stdout.flush();
  }
}

void _logProtocolError(NativeHostProtocolException error) {
  stderr.writeln('[KeyVault native host] protocol_error code=${error.code}');
}
