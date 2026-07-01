import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/vault_entry.dart';

const desktopBrowserAutofillCacheVersion = 2;
const desktopBrowserAutofillPlatform = 'desktop/browser';
const desktopBrowserAutofillMaxPendingAssociations = 100;

class DesktopBrowserAutofillStoreStatus {
  const DesktopBrowserAutofillStoreStatus({
    required this.directoryPath,
    required this.metadataCount,
    required this.cacheAvailable,
    this.databaseId,
    this.generatedAtEpochMs,
  });

  final String? directoryPath;
  final int metadataCount;
  final bool cacheAvailable;
  final String? databaseId;
  final int? generatedAtEpochMs;
}

class DesktopBrowserAutofillServiceIdentifier {
  const DesktopBrowserAutofillServiceIdentifier({
    required this.type,
    required this.value,
  });

  factory DesktopBrowserAutofillServiceIdentifier.fromJson(
    Map<String, Object?> json,
  ) {
    return DesktopBrowserAutofillServiceIdentifier(
      type: _readString(json, 'type'),
      value: _readString(json, 'value'),
    );
  }

  final String type;
  final String value;

  Map<String, Object?> toJson() => {'type': type, 'value': value};

  @override
  bool operator ==(Object other) {
    return other is DesktopBrowserAutofillServiceIdentifier &&
        other.type == type &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(type, value);
}

class DesktopBrowserAutofillCredentialMetadata {
  const DesktopBrowserAutofillCredentialMetadata({
    required this.id,
    required this.title,
    required this.username,
    required this.displayService,
    required this.serviceIdentifiers,
    required this.updatedAtEpochMs,
  });

  factory DesktopBrowserAutofillCredentialMetadata.fromJson(
    Map<String, Object?> json,
  ) {
    return DesktopBrowserAutofillCredentialMetadata(
      id: _readString(json, 'id'),
      title: _readString(json, 'title'),
      username: _readString(json, 'username'),
      displayService: _readString(json, 'displayService'),
      serviceIdentifiers: _readList(json, 'serviceIdentifiers')
          .whereType<Map>()
          .map(_stringObjectMap)
          .whereType<Map<String, Object?>>()
          .map(DesktopBrowserAutofillServiceIdentifier.fromJson)
          .where((identifier) => identifier.type.isNotEmpty)
          .where((identifier) => identifier.value.isNotEmpty)
          .toList(growable: false),
      updatedAtEpochMs: _readInt(json, 'updatedAtEpochMs'),
    );
  }

  final String id;
  final String title;
  final String username;
  final String displayService;
  final List<DesktopBrowserAutofillServiceIdentifier> serviceIdentifiers;
  final int updatedAtEpochMs;

  String get sortKey => [
    displayService,
    title,
    username,
    id,
  ].map((value) => value.toLowerCase()).join('|');

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'username': username,
    'displayService': displayService,
    'updatedAtEpochMs': updatedAtEpochMs,
    'serviceIdentifiers': serviceIdentifiers
        .map((identifier) => identifier.toJson())
        .toList(growable: false),
  };
}

class DesktopBrowserAutofillMetadataCache {
  const DesktopBrowserAutofillMetadataCache({
    required this.version,
    required this.databaseId,
    required this.generatedAtEpochMs,
    required this.entries,
  });

  factory DesktopBrowserAutofillMetadataCache.fromJson(
    Map<String, Object?> json,
  ) {
    return DesktopBrowserAutofillMetadataCache(
      version: _readInt(json, 'version'),
      databaseId: _readString(json, 'databaseId'),
      generatedAtEpochMs: _readInt(json, 'generatedAtEpochMs'),
      entries: _readList(json, 'entries')
          .whereType<Map>()
          .map(_stringObjectMap)
          .whereType<Map<String, Object?>>()
          .map(DesktopBrowserAutofillCredentialMetadata.fromJson)
          .where((entry) => entry.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  final int version;
  final String databaseId;
  final int generatedAtEpochMs;
  final List<DesktopBrowserAutofillCredentialMetadata> entries;

  Map<String, Object?> toJson() => {
    'version': version,
    'databaseId': databaseId,
    'generatedAtEpochMs': generatedAtEpochMs,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
  };
}

class DesktopBrowserAutofillPendingAssociation {
  const DesktopBrowserAutofillPendingAssociation({
    required this.id,
    required this.databaseId,
    required this.entryId,
    required this.serviceIdentifierType,
    required this.serviceIdentifierValue,
    required this.displayService,
    required this.createdAtEpochMs,
    this.platform = desktopBrowserAutofillPlatform,
  });

  factory DesktopBrowserAutofillPendingAssociation.fromJson(
    Map<String, Object?> json,
  ) {
    final type = _readString(json, 'serviceIdentifierType');
    final value = _sanitizePendingAssociationTargetValue(
      type: type,
      value: _readString(json, 'serviceIdentifierValue'),
    );
    return DesktopBrowserAutofillPendingAssociation(
      id: _readString(json, 'id'),
      databaseId: _readString(json, 'databaseId'),
      entryId: _readString(json, 'entryId'),
      serviceIdentifierType: _canonicalPendingAssociationTargetType(type) ?? '',
      serviceIdentifierValue: value,
      displayService: _sanitizePendingAssociationDisplayService(
        type: type,
        value: _readString(json, 'displayService'),
        fallbackValue: value,
      ),
      createdAtEpochMs: _readInt(json, 'createdAtEpochMs'),
      platform: _readString(json, 'platform').isEmpty
          ? desktopBrowserAutofillPlatform
          : _readString(json, 'platform'),
    );
  }

  final String id;
  final String databaseId;
  final String entryId;
  final String serviceIdentifierType;
  final String serviceIdentifierValue;
  final String displayService;
  final int createdAtEpochMs;
  final String platform;

  Map<String, Object?> toJson() {
    final type = _canonicalPendingAssociationTargetType(serviceIdentifierType);
    final value = _sanitizePendingAssociationTargetValue(
      type: serviceIdentifierType,
      value: serviceIdentifierValue,
    );
    final display = _sanitizePendingAssociationDisplayService(
      type: serviceIdentifierType,
      value: displayService,
      fallbackValue: value,
    );
    return {
      'id': id,
      'databaseId': databaseId,
      'entryId': entryId,
      'serviceIdentifierType': type ?? serviceIdentifierType,
      'serviceIdentifierValue': value,
      'displayService': display,
      'createdAtEpochMs': createdAtEpochMs,
      'platform': platform,
    };
  }
}

class DesktopBrowserAutofillAssociationTarget {
  const DesktopBrowserAutofillAssociationTarget({
    required this.type,
    required this.value,
    required this.displayService,
  });

  final String type;
  final String value;
  final String displayService;

  Map<String, Object?> toJson() => {
    'type': type,
    'value': value,
    'displayService': displayService,
  };
}

class DesktopBrowserAutofillCacheStore {
  DesktopBrowserAutofillCacheStore({Directory? directory})
    : _directory = directory;

  final Directory? _directory;

  static bool get isPlatformSupported {
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  Directory? get directory {
    if (!isPlatformSupported) {
      return null;
    }
    return _directory ?? defaultDirectory();
  }

  File? get metadataFile {
    final dir = directory;
    return dir == null ? null : File(p.join(dir.path, 'metadata.json'));
  }

  File? get pendingAssociationsFile {
    final dir = directory;
    return dir == null
        ? null
        : File(p.join(dir.path, 'pending_associations.json'));
  }

  static Directory? defaultDirectory({Map<String, String>? environment}) {
    if (!isPlatformSupported) {
      return null;
    }
    final env = environment ?? Platform.environment;
    if (Platform.isWindows) {
      final base = _firstNonEmpty([
        env['LOCALAPPDATA'],
        env['APPDATA'],
        env['USERPROFILE'],
      ]);
      return base == null
          ? null
          : Directory(p.join(base, 'KeyVault', 'AutofillBrowserV2'));
    }

    final home = _firstNonEmpty([env['HOME'], env['USERPROFILE']]);
    return home == null
        ? null
        : Directory(p.join(home, '.keyvault_autofill', 'browser_v2'));
  }

  Future<DesktopBrowserAutofillStoreStatus> status() async {
    final cache = await readMetadataCache();
    return DesktopBrowserAutofillStoreStatus(
      directoryPath: directory?.path,
      metadataCount: cache?.entries.length ?? 0,
      cacheAvailable: cache != null,
      databaseId: cache?.databaseId,
      generatedAtEpochMs: cache?.generatedAtEpochMs,
    );
  }

  Future<void> writeMetadataCache(
    DesktopBrowserAutofillMetadataCache cache,
  ) async {
    final file = metadataFile;
    if (file == null) {
      return;
    }
    await _writeJsonFile(file, cache.toJson());
  }

  Future<DesktopBrowserAutofillMetadataCache?> readMetadataCache() async {
    final file = metadataFile;
    if (file == null || !await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      final map = _stringObjectMap(decoded);
      if (map == null) {
        return null;
      }
      final cache = DesktopBrowserAutofillMetadataCache.fromJson(map);
      if (cache.version != desktopBrowserAutofillCacheVersion ||
          cache.databaseId.isEmpty) {
        return null;
      }
      return cache;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCredentials() async {
    await _deleteFile(metadataFile);
    await _deleteFile(pendingAssociationsFile);
  }

  Future<List<DesktopBrowserAutofillPendingAssociation>>
  readPendingAssociations() async {
    final file = pendingAssociationsFile;
    if (file == null || !await file.exists()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map(_stringObjectMap)
          .whereType<Map<String, Object?>>()
          .map(DesktopBrowserAutofillPendingAssociation.fromJson)
          .where((association) => association.id.isNotEmpty)
          .where((association) => association.databaseId.isNotEmpty)
          .where((association) => association.entryId.isNotEmpty)
          .where((association) => association.serviceIdentifierValue.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<int> clearPendingAssociations({List<String>? ids}) async {
    final file = pendingAssociationsFile;
    if (file == null || !await file.exists()) {
      return 0;
    }
    if (ids == null) {
      final count = (await readPendingAssociations()).length;
      await _deleteFile(file);
      return count;
    }

    final idsToClear = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (idsToClear.isEmpty) {
      return 0;
    }

    final associations = await readPendingAssociations();
    final remaining = associations
        .where((association) => !idsToClear.contains(association.id))
        .toList(growable: false);
    final cleared = associations.length - remaining.length;
    if (cleared == 0) {
      return 0;
    }
    if (remaining.isEmpty) {
      await _deleteFile(file);
    } else {
      await _writeJsonFile(
        file,
        remaining.map((association) => association.toJson()).toList(),
      );
    }
    return cleared;
  }

  Future<DesktopBrowserAutofillPendingAssociation?> savePendingAssociation({
    required String entryId,
    required DesktopBrowserAutofillAssociationTarget target,
    int? createdAtEpochMs,
    String? id,
  }) async {
    final cache = await readMetadataCache();
    if (cache == null) {
      return null;
    }
    final normalizedEntryId = entryId.trim();
    final normalizedTarget = _normalizedPendingAssociationTarget(target);
    final entryExists = cache.entries.any(
      (entry) => entry.id == normalizedEntryId,
    );
    if (!entryExists || normalizedEntryId.isEmpty || normalizedTarget == null) {
      return null;
    }

    final pending = DesktopBrowserAutofillPendingAssociation(
      id: id ?? _newPendingId(),
      databaseId: cache.databaseId,
      entryId: normalizedEntryId,
      serviceIdentifierType: normalizedTarget.type,
      serviceIdentifierValue: normalizedTarget.value,
      displayService: normalizedTarget.displayService.isEmpty
          ? normalizedTarget.value
          : normalizedTarget.displayService,
      createdAtEpochMs:
          createdAtEpochMs ?? DateTime.now().millisecondsSinceEpoch,
    );

    final file = pendingAssociationsFile;
    if (file == null) {
      return null;
    }
    final associations =
        (await readPendingAssociations())
            .where(
              (association) =>
                  association.databaseId != pending.databaseId ||
                  association.entryId != pending.entryId ||
                  association.serviceIdentifierType !=
                      pending.serviceIdentifierType ||
                  association.serviceIdentifierValue !=
                      pending.serviceIdentifierValue,
            )
            .toList(growable: true)
          ..add(pending);
    final capped =
        associations.length > desktopBrowserAutofillMaxPendingAssociations
        ? associations.sublist(
            associations.length - desktopBrowserAutofillMaxPendingAssociations,
          )
        : associations;
    await _writeJsonFile(
      file,
      capped.map((association) => association.toJson()).toList(growable: false),
    );
    return pending;
  }

  Future<void> _writeJsonFile(File file, Object? jsonValue) async {
    final parent = file.parent;
    await parent.create(recursive: true);
    await _chmodOwnerOnly(parent.path, isDirectory: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(jsonValue), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
    await _chmodOwnerOnly(file.path, isDirectory: false);
  }

  Future<void> _deleteFile(File? file) async {
    if (file == null) {
      return;
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _chmodOwnerOnly(String path, {required bool isDirectory}) async {
    if (Platform.isWindows) {
      return;
    }
    try {
      await Process.run('chmod', [isDirectory ? '700' : '600', path]);
    } catch (_) {}
  }
}

class DesktopBrowserAutofillMetadataMapper {
  const DesktopBrowserAutofillMetadataMapper();

  DesktopBrowserAutofillMetadataCache mapVault({
    required String databasePath,
    required List<VaultEntry> entries,
    int? generatedAtEpochMs,
  }) {
    final generatedAt =
        generatedAtEpochMs ?? DateTime.now().millisecondsSinceEpoch;
    return DesktopBrowserAutofillMetadataCache(
      version: desktopBrowserAutofillCacheVersion,
      databaseId: databaseIdForPath(databasePath),
      generatedAtEpochMs: generatedAt,
      entries: entries
          .map((entry) => mapEntry(entry, updatedAtEpochMs: generatedAt))
          .whereType<DesktopBrowserAutofillCredentialMetadata>()
          .toList(growable: false),
    );
  }

  DesktopBrowserAutofillCredentialMetadata? mapEntry(
    VaultEntry entry, {
    required int updatedAtEpochMs,
  }) {
    final id = entry.id.trim();
    if (id.isEmpty || entry.password.isEmpty) {
      return null;
    }
    final identifiers = _serviceIdentifiersForEntry(entry);
    final displayService = displayServiceFromIdentifiers(identifiers);
    return DesktopBrowserAutofillCredentialMetadata(
      id: id,
      title: _trimForMetadata(
        entry.title,
        fallback: displayService.isEmpty ? 'Untitled' : displayService,
      ),
      username: _trimForMetadata(entry.username),
      displayService: displayService,
      serviceIdentifiers: identifiers,
      updatedAtEpochMs:
          entry.updatedAt?.millisecondsSinceEpoch ?? updatedAtEpochMs,
    );
  }

  static String databaseIdForPath(String databasePath) {
    return 'sha256:${sha256.convert(utf8.encode(databasePath.trim()))}';
  }

  static String? normalizedHost(String? rawValue) {
    final value = rawValue?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    if (_isNativeAppValue(value)) {
      return null;
    }
    final uri = Uri.tryParse(_valueWithDefaultScheme(value));
    final rawHost = (uri != null && uri.host.isNotEmpty)
        ? uri.host
        : value.split('/').first.split(':').first;
    return _cleanHost(rawHost);
  }

  static String? normalizedOrigin(String? rawValue) {
    final value = rawValue?.trim() ?? '';
    if (value.isEmpty || _isNativeAppValue(value)) {
      return null;
    }
    final uri = Uri.tryParse(_valueWithDefaultScheme(value));
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    final host = _cleanHost(uri.host);
    if (host == null) {
      return null;
    }
    return Uri(
      scheme: scheme,
      host: host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  static DesktopBrowserAutofillAssociationTarget? targetFromUrl(
    String? rawUrl,
  ) {
    final host = normalizedHost(rawUrl);
    if (host == null) {
      return null;
    }
    return DesktopBrowserAutofillAssociationTarget(
      type: 'domain',
      value: host,
      displayService: host,
    );
  }

  static String displayServiceFromIdentifiers(
    List<DesktopBrowserAutofillServiceIdentifier> identifiers,
  ) {
    final domain = identifiers
        .where((identifier) => identifier.type == 'domain')
        .map((identifier) => identifier.value)
        .firstOrNull;
    if (domain != null && domain.isNotEmpty) {
      return domain;
    }
    final url = identifiers
        .where((identifier) => identifier.type == 'url')
        .map((identifier) => normalizedHost(identifier.value))
        .whereType<String>()
        .firstOrNull;
    return url ?? '';
  }

  List<DesktopBrowserAutofillServiceIdentifier> _serviceIdentifiersForEntry(
    VaultEntry entry,
  ) {
    final identifiers = <DesktopBrowserAutofillServiceIdentifier>[];
    final seen = <DesktopBrowserAutofillServiceIdentifier>{};

    void add(DesktopBrowserAutofillServiceIdentifier? identifier) {
      if (identifier == null || identifier.value.trim().isEmpty) {
        return;
      }
      if (seen.add(identifier)) {
        identifiers.add(identifier);
      }
    }

    final origin = normalizedOrigin(entry.url);
    final host = normalizedHost(entry.url);
    if (origin != null) {
      add(DesktopBrowserAutofillServiceIdentifier(type: 'url', value: origin));
    }
    if (host != null) {
      add(DesktopBrowserAutofillServiceIdentifier(type: 'domain', value: host));
    }

    for (final field in entry.customFields) {
      final key = _normalizeFieldKey(field.key);
      if (_isDomainField(key)) {
        for (final value in _splitCustomFieldValues(field.value)) {
          final domain = normalizedHost(value);
          if (domain != null) {
            add(
              DesktopBrowserAutofillServiceIdentifier(
                type: 'domain',
                value: domain,
              ),
            );
          }
        }
        continue;
      }
      if (_isUrlField(key)) {
        for (final value in _splitCustomFieldValues(field.value)) {
          final urlOrigin = normalizedOrigin(value);
          final urlHost = normalizedHost(value);
          if (urlOrigin != null) {
            add(
              DesktopBrowserAutofillServiceIdentifier(
                type: 'url',
                value: urlOrigin,
              ),
            );
          }
          if (urlHost != null) {
            add(
              DesktopBrowserAutofillServiceIdentifier(
                type: 'domain',
                value: urlHost,
              ),
            );
          }
        }
      }
    }
    return identifiers;
  }

  String _trimForMetadata(String value, {String fallback = ''}) {
    final trimmed = value.trim();
    final effective = trimmed.isEmpty ? fallback : trimmed;
    return effective.length <= 512 ? effective : effective.substring(0, 512);
  }

  static bool _isDomainField(String key) {
    return key == 'domain' ||
        key == 'domains' ||
        key == 'webdomain' ||
        key == 'hostname' ||
        key == 'host' ||
        key == 'kph:domain' ||
        key == 'kph:webdomain' ||
        RegExp(r'^kph:domain\d+$').hasMatch(key) ||
        RegExp(r'^kph:webdomain\d+$').hasMatch(key);
  }

  static bool _isUrlField(String key) {
    return key == 'url' ||
        key == 'uri' ||
        key == 'website' ||
        key == 'weburl' ||
        key == 'loginurl' ||
        key == 'kph:url' ||
        key == 'kph:uri' ||
        RegExp(r'^kph:url\d+$').hasMatch(key) ||
        RegExp(r'^kph:uri\d+$').hasMatch(key);
  }

  static String _normalizeFieldKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  }

  static Iterable<String> _splitCustomFieldValues(String value) sync* {
    for (final token in value.split(RegExp(r'[,;\s]+'))) {
      final trimmed = token.trim();
      if (trimmed.isNotEmpty) {
        yield trimmed;
      }
    }
  }

  static String _valueWithDefaultScheme(String value) {
    if (value.contains('://')) {
      return value;
    }
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    return 'https://$value';
  }

  static String? _cleanHost(String? rawHost) {
    var host = rawHost?.trim().toLowerCase() ?? '';
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    for (final prefix in const ['www.', 'm.', 'mobile.']) {
      if (host.startsWith(prefix)) {
        host = host.substring(prefix.length);
        break;
      }
    }
    if (host.isEmpty ||
        host.length > 253 ||
        host.contains(RegExp(r'[\s/@:]'))) {
      return null;
    }
    return host;
  }

  static bool _isNativeAppValue(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('androidapp:') ||
        normalized.startsWith('iosbundleid:');
  }
}

DesktopBrowserAutofillAssociationTarget? _normalizedPendingAssociationTarget(
  DesktopBrowserAutofillAssociationTarget target,
) {
  final type = _canonicalPendingAssociationTargetType(target.type);
  if (type == null) {
    return null;
  }

  final value = switch (type) {
    'domain' => DesktopBrowserAutofillMetadataMapper.normalizedHost(
      target.value,
    ),
    'url' => DesktopBrowserAutofillMetadataMapper.normalizedOrigin(
      target.value,
    ),
    _ => null,
  };
  if (value == null || value.isEmpty) {
    return null;
  }

  final displayService = switch (type) {
    'domain' => DesktopBrowserAutofillMetadataMapper.normalizedHost(
      target.displayService,
    ),
    'url' => DesktopBrowserAutofillMetadataMapper.normalizedHost(
      target.displayService,
    ),
    _ => null,
  };

  return DesktopBrowserAutofillAssociationTarget(
    type: type,
    value: value,
    displayService:
        displayService ??
        DesktopBrowserAutofillMetadataMapper.normalizedHost(value) ??
        value,
  );
}

String? _canonicalPendingAssociationTargetType(String type) {
  final normalized = type.trim().toLowerCase().replaceAll(
    RegExp(r'[\s_-]+'),
    '',
  );
  return switch (normalized) {
    'domain' => 'domain',
    'url' => 'url',
    _ => null,
  };
}

String _sanitizePendingAssociationTargetValue({
  required String type,
  required String value,
}) {
  final targetType = _canonicalPendingAssociationTargetType(type);
  if (targetType == null) {
    return '';
  }
  return switch (targetType) {
        'domain' => DesktopBrowserAutofillMetadataMapper.normalizedHost(value),
        'url' => DesktopBrowserAutofillMetadataMapper.normalizedOrigin(value),
        _ => null,
      } ??
      '';
}

String _sanitizePendingAssociationDisplayService({
  required String type,
  required String value,
  required String fallbackValue,
}) {
  final targetType = _canonicalPendingAssociationTargetType(type);
  final normalized = targetType == null
      ? null
      : DesktopBrowserAutofillMetadataMapper.normalizedHost(value);
  return normalized ?? fallbackValue;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String _newPendingId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final suffix = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'desktop-${DateTime.now().microsecondsSinceEpoch}-$suffix';
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value.trim() : '';
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is int ? value : 0;
}

List<Object?> _readList(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is List ? value.cast<Object?>() : const [];
}

Map<String, Object?>? _stringObjectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      return null;
    }
    result[key] = entry.value as Object?;
  }
  return result;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
