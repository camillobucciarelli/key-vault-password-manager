import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:loggy/loggy.dart';

import '../../domain/models/vault_entry.dart';
import '../../domain/repositories/autofill_ports.dart';
import '../../domain/services/apple_autofill_v2_payload_mapper.dart';

abstract interface class AppleAutofillV2CoordinatorContract {
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  });

  Future<void> clearCredentials({String? databasePath});
}

class NoopAppleAutofillV2Coordinator
    implements AppleAutofillV2CoordinatorContract {
  const NoopAppleAutofillV2Coordinator();

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {}

  @override
  Future<void> clearCredentials({String? databasePath}) async {}
}

class AppleAutofillV2Coordinator implements AppleAutofillV2CoordinatorContract {
  AppleAutofillV2Coordinator({required this.client, required this.mapper});

  final AppleAutofillV2Client client;
  final AppleAutofillV2PayloadMapper mapper;

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    if (!client.isSupported) {
      return;
    }

    final databaseId = _databaseIdForPath(databasePath);
    if (databaseId == null) {
      await clearCredentials();
      return;
    }

    try {
      await client.publishCredentials(
        databaseId: databaseId,
        credentials: mapper.mapEntries(entries),
      );
    } catch (e, st) {
      logWarning('Apple Autofill v2 publish failed.', e, st);
    }
  }

  @override
  Future<void> clearCredentials({String? databasePath}) async {
    if (!client.isSupported) {
      return;
    }

    try {
      await client.clearCredentials(
        databaseId: databasePath == null
            ? null
            : _databaseIdForPath(databasePath),
      );
    } catch (e, st) {
      logWarning('Apple Autofill v2 clear failed.', e, st);
    }
  }

  String? _databaseIdForPath(String databasePath) {
    final normalized = databasePath.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return 'sha256:${sha256.convert(utf8.encode(normalized))}';
  }
}
