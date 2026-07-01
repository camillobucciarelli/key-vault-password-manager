import 'package:loggy/loggy.dart';

import '../../data/services/desktop_browser_autofill_cache.dart';
import '../../domain/models/apple_autofill_v2_models.dart';
import '../../domain/models/vault_entry.dart';
import 'apple_autofill_v2_coordinator.dart';

class DesktopBrowserAutofillCoordinator
    implements AppleAutofillV2CoordinatorContract {
  DesktopBrowserAutofillCoordinator({
    required this.store,
    required this.mapper,
  });

  final DesktopBrowserAutofillCacheStore store;
  final DesktopBrowserAutofillMetadataMapper mapper;

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    if (store.directory == null) {
      return;
    }
    try {
      await store.writeMetadataCache(
        mapper.mapVault(databasePath: databasePath, entries: entries),
      );
    } catch (e, st) {
      logWarning('Desktop browser Autofill cache publish failed.', e, st);
    }
  }

  @override
  Future<void> clearCredentials({String? databasePath}) async {
    if (store.directory == null) {
      return;
    }
    try {
      await store.clearCredentials();
    } catch (e, st) {
      logWarning('Desktop browser Autofill cache clear failed.', e, st);
    }
  }

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async {
    final databaseId = databasePath == null || databasePath.trim().isEmpty
        ? null
        : DesktopBrowserAutofillMetadataMapper.databaseIdForPath(databasePath);
    if (databaseId == null) {
      return const [];
    }
    if (store.directory == null) {
      return const [];
    }

    try {
      final pending = await store.readPendingAssociations();
      return pending
          .where((association) => association.databaseId == databaseId)
          .map(
            (association) => AppleAutofillV2PendingAssociation(
              id: association.id,
              databaseId: association.databaseId,
              entryId: association.entryId,
              serviceIdentifierType: association.serviceIdentifierType,
              serviceIdentifierValue: association.serviceIdentifierValue,
              displayService: association.displayService,
              createdAtEpochMs: association.createdAtEpochMs,
              platform: association.platform,
            ),
          )
          .toList(growable: false);
    } catch (e, st) {
      logWarning('Desktop browser Autofill pending read failed.', e, st);
      return const [];
    }
  }

  @override
  Future<void> clearPendingAssociations({List<String>? ids}) async {
    if (store.directory == null) {
      return;
    }
    try {
      await store.clearPendingAssociations(ids: ids);
    } catch (e, st) {
      logWarning('Desktop browser Autofill pending clear failed.', e, st);
    }
  }
}

class CompositeAutofillV2Coordinator
    implements AppleAutofillV2CoordinatorContract {
  const CompositeAutofillV2Coordinator(this.coordinators);

  final List<AppleAutofillV2CoordinatorContract> coordinators;

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    for (final coordinator in coordinators) {
      await coordinator.publishVault(
        databasePath: databasePath,
        entries: entries,
      );
    }
  }

  @override
  Future<void> clearCredentials({String? databasePath}) async {
    for (final coordinator in coordinators) {
      await coordinator.clearCredentials(databasePath: databasePath);
    }
  }

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async {
    final result = <AppleAutofillV2PendingAssociation>[];
    final seen = <String>{};
    for (final coordinator in coordinators) {
      final pending = await coordinator.readPendingAssociations(
        databasePath: databasePath,
      );
      for (final association in pending) {
        if (seen.add(association.id)) {
          result.add(association);
        }
      }
    }
    result.sort((a, b) => a.createdAtEpochMs.compareTo(b.createdAtEpochMs));
    return result;
  }

  @override
  Future<void> clearPendingAssociations({List<String>? ids}) async {
    for (final coordinator in coordinators) {
      await coordinator.clearPendingAssociations(ids: ids);
    }
  }
}
