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

  /// The native side's "this capture is gone" answer — expected, not an error.
  static const _captureMissingCode = 'android_autofill_capture_missing';

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

  /// Save capture is an Android-only path: the Apple credential provider has no
  /// equivalent of `onSaveRequest`.
  bool get _supportsCapture =>
      isSupported &&
      (_isSupportedOverride == null
          ? defaultTargetPlatform == TargetPlatform.android
          : true);

  @override
  Future<String?> takePendingCaptureToken() async {
    if (!_supportsCapture) {
      return null;
    }
    return _channel.invokeMethod<String>('takePendingCaptureToken');
  }

  @override
  Future<AndroidAutofillCapture?> readPendingCapture(String token) async {
    if (!_supportsCapture) {
      throw UnsupportedError(
        'Autofill save capture is not supported on this platform.',
      );
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'readPendingCapture',
        {'token': token},
      );
      return result == null ? null : AndroidAutofillCapture.fromMap(result);
    } on PlatformException catch (error) {
      if (error.code == _captureMissingCode) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<AppleAutofillV2ClearPendingAssociationsResult> resolvePendingCapture({
    required String token,
    required AndroidAutofillCaptureOutcome outcome,
  }) async {
    if (!_supportsCapture) {
      throw UnsupportedError(
        'Autofill save capture is not supported on this platform.',
      );
    }

    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'resolvePendingCapture',
      {'token': token, 'outcome': outcome.channelValue},
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
