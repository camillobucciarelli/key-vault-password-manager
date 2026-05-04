import 'dart:async';

import 'package:flutter/services.dart';

class OtpAuthDeepLinkCoordinator {
  OtpAuthDeepLinkCoordinator({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'dev.camillobucciarelli.kdbxKeyVault/otpauth_deep_link';

  final MethodChannel _channel;
  final _controller = StreamController<OtpAuthDeepLinkEvent>.broadcast();
  final List<OtpAuthDeepLinkEvent> _pending = [];
  bool _vaultAvailable = false;
  bool _initialized = false;

  Stream<OtpAuthDeepLinkEvent> get events => _controller.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'receiveOtpAuthUrl') {
        final url = call.arguments;
        if (url is String) {
          receiveUrl(url);
        }
      }
    });

    final List<dynamic>? pending;
    try {
      pending = await _channel.invokeMethod<List<dynamic>>('takePendingUrls');
    } on MissingPluginException {
      return;
    }
    for (final url in pending ?? const <dynamic>[]) {
      if (url is String) {
        receiveUrl(url);
      }
    }
  }

  void markVaultAvailable() {
    _vaultAvailable = true;
    if (_pending.isEmpty) {
      return;
    }
    final events = List<OtpAuthDeepLinkEvent>.of(_pending);
    _pending.clear();
    for (final event in events) {
      _controller.add(event);
    }
  }

  void markVaultUnavailable() {
    _vaultAvailable = false;
  }

  void receiveUrl(String url) {
    final event = OtpAuthDeepLinkEvent.fromUrl(url);
    if (_vaultAvailable) {
      _controller.add(event);
    } else {
      _pending.add(event);
    }
  }

  int get pendingCount => _pending.length;
}

class OtpAuthDeepLinkEvent {
  const OtpAuthDeepLinkEvent._({this.otpAuth, this.errorMessage});

  factory OtpAuthDeepLinkEvent.fromUrl(String url) {
    final parsed = OtpAuthPayload.tryParse(url);
    if (parsed != null) {
      return OtpAuthDeepLinkEvent._(otpAuth: parsed);
    }

    return const OtpAuthDeepLinkEvent._(
      errorMessage:
          'Only standard otpauth://totp links are supported. HOTP and migration links are not imported yet.',
    );
  }

  final OtpAuthPayload? otpAuth;
  final String? errorMessage;

  bool get isValid => otpAuth != null;
}

class OtpAuthPayload {
  const OtpAuthPayload({
    required this.uri,
    required this.label,
    required this.title,
    required this.username,
    this.issuer,
  });

  final String uri;
  final String label;
  final String title;
  final String username;
  final String? issuer;

  static OtpAuthPayload? tryParse(String url) {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.toLowerCase() != 'otpauth') {
      return null;
    }
    if (uri.host.toLowerCase() != 'totp') {
      return null;
    }
    final secret = uri.queryParameters['secret']?.trim();
    if (secret == null || secret.isEmpty) {
      return null;
    }

    final label = _decodeLabel(uri.path);
    final issuer = uri.queryParameters['issuer']?.trim();
    final labelParts = label.split(':');
    final title = (issuer != null && issuer.isNotEmpty)
        ? issuer
        : (labelParts.length > 1 ? labelParts.first.trim() : label).trim();
    final username = labelParts.length > 1
        ? labelParts.sublist(1).join(':').trim()
        : '';

    return OtpAuthPayload(
      uri: trimmed,
      label: label,
      title: title.isEmpty ? 'OTP account' : title,
      username: username,
      issuer: issuer?.isEmpty == true ? null : issuer,
    );
  }

  static String _decodeLabel(String path) {
    final raw = path.startsWith('/') ? path.substring(1) : path;
    return Uri.decodeComponent(raw.replaceAll('+', '%20')).trim();
  }
}
