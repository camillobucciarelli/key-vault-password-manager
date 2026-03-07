import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/vault_entry.dart';

abstract class IosAutofillDataSource {
  Future<void> saveSnapshot(List<VaultEntry> entries);
  Future<void> clearSnapshot();
}

class IosAutofillDataSourceImpl implements IosAutofillDataSource {
  static const MethodChannel _channel = MethodChannel(
    'dev.camillobucciarelli.password_manager/ios_autofill',
  );

  @override
  Future<void> saveSnapshot(List<VaultEntry> entries) async {
    if (!_isSupportedPlatform) {
      return;
    }

    final payload = jsonEncode(
      entries
          .map(
            (entry) => {
              'id': entry.id,
              'title': entry.title,
              'username': entry.username,
              'password': entry.password,
              'url': entry.url,
              'notes': entry.notes,
              'customFields': entry.customFields
                  .map((field) => {'key': field.key, 'value': field.value})
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    );

    await _channel.invokeMethod<void>('saveSnapshot', {'entries': payload});
  }

  @override
  Future<void> clearSnapshot() async {
    if (!_isSupportedPlatform) {
      return;
    }

    await _channel.invokeMethod<void>('clearSnapshot');
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS;
  }
}
