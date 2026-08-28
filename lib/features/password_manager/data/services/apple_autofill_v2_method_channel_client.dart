import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/apple_autofill_v2_models.dart';
import '../../domain/repositories/autofill_ports.dart';

class AppleAutofillV2MethodChannelClient implements AppleAutofillV2Client {
  AppleAutofillV2MethodChannelClient({
    MethodChannel? channel,
    bool? isSupportedOverride,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _isSupportedOverride = isSupportedOverride;

  static const channelName =
      'dev.camillobucciarelli.keyvault/apple_autofill_v2';

  final MethodChannel _channel;
  final bool? _isSupportedOverride;

  @override
  bool get isSupported {
    final override = _isSupportedOverride;
    if (override != null) {
      return override;
    }
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Future<AppleAutofillV2PublishResult> publishCredentials({
    required String databaseId,
    required List<AppleAutofillV2Credential> credentials,
    int authSessionTtlMs = 0,
  }) async {
    if (!isSupported) {
      return const AppleAutofillV2PublishResult.unsupported();
    }

    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('publishCredentials', {
          'databaseId': databaseId,
          'entries': credentials
              .map((credential) => credential.toChannelMap())
              .toList(growable: false),
          'authSessionTtlMs': authSessionTtlMs,
        });
    return AppleAutofillV2PublishResult.fromMap(result);
  }

  @override
  Future<AppleAutofillV2ClearResult> clearCredentials({
    String? databaseId,
  }) async {
    if (!isSupported) {
      return const AppleAutofillV2ClearResult.unsupported();
    }

    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'clearCredentials',
      databaseId == null ? null : {'databaseId': databaseId},
    );
    return AppleAutofillV2ClearResult.fromMap(result);
  }

  @override
  Future<List<AppleAutofillV2PendingAssociation>>
  readPendingAssociations() async {
    if (!isSupported) {
      return const [];
    }

    final result = await _channel.invokeMethod<List<dynamic>>(
      'readPendingAssociations',
    );
    return (result ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(AppleAutofillV2PendingAssociation.fromMap)
        .toList(growable: false);
  }

  @override
  Future<AppleAutofillV2ClearPendingAssociationsResult>
  clearPendingAssociations({List<String>? ids}) async {
    if (!isSupported) {
      return const AppleAutofillV2ClearPendingAssociationsResult.unsupported();
    }

    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'clearPendingAssociations',
      ids == null ? null : {'ids': ids},
    );
    return AppleAutofillV2ClearPendingAssociationsResult.fromMap(result);
  }

  @override
  Future<AppleAutofillV2Status> getStatus() async {
    if (!isSupported) {
      return const AppleAutofillV2Status.unsupported();
    }

    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getStatus',
    );
    return AppleAutofillV2Status.fromMap(result, supported: true);
  }
}
