import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

enum AppleAutofillV2ServiceIdentifierType {
  domain('domain'),
  url('url'),
  bundleId('bundleId'),
  androidPackage('androidPackage');

  const AppleAutofillV2ServiceIdentifierType(this.channelValue);

  final String channelValue;
}

class AppleAutofillV2ServiceIdentifier extends Equatable {
  const AppleAutofillV2ServiceIdentifier({
    required this.type,
    required this.value,
  });

  const AppleAutofillV2ServiceIdentifier.domain(String value)
    : this(type: AppleAutofillV2ServiceIdentifierType.domain, value: value);

  const AppleAutofillV2ServiceIdentifier.url(String value)
    : this(type: AppleAutofillV2ServiceIdentifierType.url, value: value);

  const AppleAutofillV2ServiceIdentifier.bundleId(String value)
    : this(type: AppleAutofillV2ServiceIdentifierType.bundleId, value: value);

  const AppleAutofillV2ServiceIdentifier.androidPackage(String value)
    : this(
        type: AppleAutofillV2ServiceIdentifierType.androidPackage,
        value: value,
      );

  final AppleAutofillV2ServiceIdentifierType type;
  final String value;

  Map<String, String> toChannelMap() {
    return {'type': type.channelValue, 'value': value};
  }

  @override
  List<Object?> get props => [type, value];
}

class AppleAutofillV2Credential extends Equatable {
  const AppleAutofillV2Credential({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.serviceIdentifiers,
  });

  final String id;
  final String title;
  final String username;
  final String password;
  final String? url;
  final List<AppleAutofillV2ServiceIdentifier> serviceIdentifiers;

  Map<String, Object?> toChannelMap() {
    return {
      'id': id,
      'title': title,
      'username': username,
      'password': password,
      'url': url,
      'serviceIdentifiers': serviceIdentifiers
          .map((identifier) => identifier.toChannelMap())
          .toList(growable: false),
    };
  }

  @override
  List<Object?> get props => [
    id,
    title,
    username,
    RedactedValue(password),
    url,
    serviceIdentifiers,
  ];

  @override
  String toString() {
    return 'AppleAutofillV2Credential('
        'id: $id, '
        'title: $title, '
        'username: $username, '
        'password: <redacted>, '
        'url: $url, '
        'serviceIdentifiers: $serviceIdentifiers)';
  }
}

class AppleAutofillV2PublishResult extends Equatable {
  const AppleAutofillV2PublishResult({
    required this.publishedCount,
    required this.skippedCount,
    required this.identityCount,
    required this.identityStoreSynced,
    this.warnings = const [],
  });

  factory AppleAutofillV2PublishResult.fromMap(Map<dynamic, dynamic>? map) {
    return AppleAutofillV2PublishResult(
      publishedCount: _readInt(map, 'publishedCount'),
      skippedCount: _readInt(map, 'skippedCount'),
      identityCount: _readInt(map, 'identityCount'),
      identityStoreSynced: _readBool(map, 'identityStoreSynced'),
      warnings: _readStringList(map, 'warnings'),
    );
  }

  const AppleAutofillV2PublishResult.unsupported()
    : this(
        publishedCount: 0,
        skippedCount: 0,
        identityCount: 0,
        identityStoreSynced: false,
        warnings: const ['unsupported_platform'],
      );

  final int publishedCount;
  final int skippedCount;
  final int identityCount;
  final bool identityStoreSynced;
  final List<String> warnings;

  @override
  List<Object?> get props => [
    publishedCount,
    skippedCount,
    identityCount,
    identityStoreSynced,
    warnings,
  ];
}

class AppleAutofillV2ClearResult extends Equatable {
  const AppleAutofillV2ClearResult({
    required this.cleared,
    required this.identityStoreCleared,
    required this.keychainKeyCleared,
    this.warnings = const [],
  });

  factory AppleAutofillV2ClearResult.fromMap(Map<dynamic, dynamic>? map) {
    return AppleAutofillV2ClearResult(
      cleared: _readBool(map, 'cleared'),
      identityStoreCleared: _readBool(map, 'identityStoreCleared'),
      keychainKeyCleared: _readBool(map, 'keychainKeyCleared'),
      warnings: _readStringList(map, 'warnings'),
    );
  }

  const AppleAutofillV2ClearResult.unsupported()
    : this(
        cleared: false,
        identityStoreCleared: false,
        keychainKeyCleared: false,
        warnings: const ['unsupported_platform'],
      );

  final bool cleared;
  final bool identityStoreCleared;
  final bool keychainKeyCleared;
  final List<String> warnings;

  @override
  List<Object?> get props => [
    cleared,
    identityStoreCleared,
    keychainKeyCleared,
    warnings,
  ];
}

class AppleAutofillV2Status extends Equatable {
  const AppleAutofillV2Status({
    required this.supported,
    required this.version,
    required this.appGroupAvailable,
    required this.keychainAccessGroupAvailable,
    required this.metadataCount,
    required this.encryptedCacheAvailable,
    required this.cacheAvailable,
    this.databaseId,
    this.generatedAtEpochMs,
    this.authSessionTtlMs = 0,
    this.lastAuthenticatedAtEpochMs,
  });

  factory AppleAutofillV2Status.fromMap(
    Map<dynamic, dynamic>? map, {
    required bool supported,
  }) {
    return AppleAutofillV2Status(
      supported: supported,
      version: _readInt(map, 'version'),
      appGroupAvailable: _readBool(map, 'appGroupAvailable'),
      keychainAccessGroupAvailable: _readBool(
        map,
        'keychainAccessGroupAvailable',
      ),
      metadataCount: _readInt(map, 'metadataCount'),
      encryptedCacheAvailable: _readBool(map, 'encryptedCacheAvailable'),
      cacheAvailable: _readBool(map, 'cacheAvailable'),
      databaseId: _readString(map, 'databaseId'),
      generatedAtEpochMs: _readIntOrNull(map, 'generatedAtEpochMs'),
      authSessionTtlMs: _readInt(map, 'authSessionTtlMs'),
      lastAuthenticatedAtEpochMs: _readIntOrNull(
        map,
        'lastAuthenticatedAtEpochMs',
      ),
    );
  }

  const AppleAutofillV2Status.unsupported()
    : this(
        supported: false,
        version: 2,
        appGroupAvailable: false,
        keychainAccessGroupAvailable: false,
        metadataCount: 0,
        encryptedCacheAvailable: false,
        cacheAvailable: false,
      );

  final bool supported;
  final int version;
  final bool appGroupAvailable;
  final bool keychainAccessGroupAvailable;
  final int metadataCount;
  final bool encryptedCacheAvailable;
  final bool cacheAvailable;
  final String? databaseId;
  final int? generatedAtEpochMs;

  /// Android only: the reuse window currently stored natively. `0` on Apple.
  final int authSessionTtlMs;

  /// Android only: when a release was last authenticated. Never says which entry.
  final int? lastAuthenticatedAtEpochMs;

  @override
  List<Object?> get props => [
    supported,
    version,
    appGroupAvailable,
    keychainAccessGroupAvailable,
    metadataCount,
    encryptedCacheAvailable,
    cacheAvailable,
    databaseId,
    generatedAtEpochMs,
    authSessionTtlMs,
    lastAuthenticatedAtEpochMs,
  ];
}

class AppleAutofillV2PendingAssociation extends Equatable {
  const AppleAutofillV2PendingAssociation({
    required this.id,
    required this.databaseId,
    required this.entryId,
    required this.serviceIdentifierType,
    required this.serviceIdentifierValue,
    required this.displayService,
    required this.createdAtEpochMs,
    this.platform,
  });

  factory AppleAutofillV2PendingAssociation.fromMap(Map<dynamic, dynamic> map) {
    final type = _readString(map, 'serviceIdentifierType') ?? '';
    final serviceIdentifierValue = _sanitizePendingServiceIdentifierValue(
      type: type,
      value: _readString(map, 'serviceIdentifierValue') ?? '',
    );
    final displayService = _sanitizePendingDisplayService(
      type: type,
      value: _readString(map, 'displayService') ?? '',
      fallbackValue: serviceIdentifierValue,
    );

    return AppleAutofillV2PendingAssociation(
      id: _readString(map, 'id') ?? '',
      databaseId: _readString(map, 'databaseId') ?? '',
      entryId: _readString(map, 'entryId') ?? '',
      serviceIdentifierType: type.trim(),
      serviceIdentifierValue: serviceIdentifierValue,
      displayService: displayService,
      createdAtEpochMs: _readInt(map, 'createdAtEpochMs'),
      platform: _readString(map, 'platform')?.trim(),
    );
  }

  final String id;
  final String databaseId;
  final String entryId;
  final String serviceIdentifierType;
  final String serviceIdentifierValue;
  final String displayService;
  final int createdAtEpochMs;
  final String? platform;

  @override
  List<Object?> get props => [
    id,
    databaseId,
    entryId,
    serviceIdentifierType,
    RedactedValue(serviceIdentifierValue),
    RedactedValue(displayService),
    createdAtEpochMs,
    platform,
  ];

  @override
  String toString() {
    return 'AppleAutofillV2PendingAssociation('
        'id: $id, '
        'databaseId: $databaseId, '
        'entryId: $entryId, '
        'serviceIdentifierType: $serviceIdentifierType, '
        'serviceIdentifierValue: <redacted>, '
        'displayService: <redacted>, '
        'createdAtEpochMs: $createdAtEpochMs, '
        'platform: $platform)';
  }
}

class AppleAutofillV2ClearPendingAssociationsResult extends Equatable {
  const AppleAutofillV2ClearPendingAssociationsResult({
    required this.clearedCount,
    this.warnings = const [],
  });

  factory AppleAutofillV2ClearPendingAssociationsResult.fromMap(
    Map<dynamic, dynamic>? map,
  ) {
    return AppleAutofillV2ClearPendingAssociationsResult(
      clearedCount: _readInt(map, 'clearedCount'),
      warnings: _readStringList(map, 'warnings'),
    );
  }

  const AppleAutofillV2ClearPendingAssociationsResult.unsupported()
    : this(clearedCount: 0, warnings: const ['unsupported_platform']);

  final int clearedCount;
  final List<String> warnings;

  @override
  List<Object?> get props => [clearedCount, warnings];
}

Object? _read(Map<dynamic, dynamic>? map, String key) =>
    map == null ? null : map[key];

int _readInt(Map<dynamic, dynamic>? map, String key) {
  final value = _read(map, key);
  return value is int ? value : 0;
}

int? _readIntOrNull(Map<dynamic, dynamic>? map, String key) {
  final value = _read(map, key);
  return value is int ? value : null;
}

bool _readBool(Map<dynamic, dynamic>? map, String key) {
  final value = _read(map, key);
  return value is bool ? value : false;
}

String? _readString(Map<dynamic, dynamic>? map, String key) {
  final value = _read(map, key);
  return value is String ? value : null;
}

List<String> _readStringList(Map<dynamic, dynamic>? map, String key) {
  final value = _read(map, key);
  if (value is! List) {
    return const [];
  }
  return value.whereType<String>().toList(growable: false);
}

String _sanitizePendingServiceIdentifierValue({
  required String type,
  required String value,
}) {
  final normalizedType = _normalizePendingType(type);
  final normalized = switch (normalizedType) {
    'domain' => _normalizedPendingHost(value),
    'url' => _normalizedPendingOrigin(value) ?? _normalizedPendingHost(value),
    'bundleid' ||
    'iosbundle' ||
    'iosbundleid' => _normalizedPendingBundleId(value),
    'androidpackage' ||
    'androidpackageid' ||
    'packagename' ||
    'androidappid' ||
    'androidapp' => _normalizedPendingAndroidPackage(value),
    _ => null,
  };
  return normalized ?? '';
}

String _sanitizePendingDisplayService({
  required String type,
  required String value,
  required String fallbackValue,
}) {
  final normalizedType = _normalizePendingType(type);
  if (normalizedType == 'domain' || normalizedType == 'url') {
    final host = _normalizedPendingHost(value);
    if (host != null && host.isNotEmpty) {
      return host;
    }
  }

  final normalized = _sanitizePendingServiceIdentifierValue(
    type: type,
    value: value,
  );
  return normalized.isNotEmpty ? normalized : fallbackValue;
}

String _normalizePendingType(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
}

String? _normalizedPendingOrigin(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty || _isNativePendingValue(value)) {
    return null;
  }
  final uri = Uri.tryParse(_pendingValueWithDefaultScheme(value));
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  final host = _cleanPendingHost(uri.host);
  if (host == null) {
    return null;
  }
  return Uri(
    scheme: scheme,
    host: host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}

String? _normalizedPendingHost(String rawValue) {
  var value = rawValue.trim();
  if (value.isEmpty || _isNativePendingValue(value)) {
    return null;
  }

  if (value.contains('://')) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    return _cleanPendingHost(uri.host);
  }

  if (value.startsWith('//')) {
    value = value.substring(2);
  }
  if (value.contains('@')) {
    return null;
  }
  final delimiterIndex = _firstPendingDelimiterIndex(value);
  if (delimiterIndex >= 0) {
    value = value.substring(0, delimiterIndex);
  }
  final uri = Uri.tryParse('https://$value');
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  return _cleanPendingHost(uri.host);
}

String? _cleanPendingHost(String? rawHost) {
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
  if (host.isEmpty || host.length > 253 || host.contains(RegExp(r'[\s/@:]'))) {
    return null;
  }
  return host;
}

String? _normalizedPendingBundleId(String rawValue) {
  var value = rawValue.trim().toLowerCase();
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('iosbundleid:')) {
    value = value
        .substring('iosbundleid:'.length)
        .replaceAll(RegExp(r'^/+'), '');
  }
  final delimiterIndex = _firstPendingDelimiterIndex(value);
  if (delimiterIndex >= 0) {
    value = value.substring(0, delimiterIndex);
  }
  value = value.replaceAll(RegExp(r'^/+|/+$'), '');
  if (value.isEmpty || value.length > 255) {
    return null;
  }
  if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(value)) {
    return null;
  }
  return value;
}

String? _normalizedPendingAndroidPackage(String rawValue) {
  var value = rawValue.trim().toLowerCase();
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('androidapp:')) {
    value = value
        .substring('androidapp:'.length)
        .replaceAll(RegExp(r'^/+'), '');
  }
  final delimiterIndex = _firstPendingDelimiterIndex(value);
  if (delimiterIndex >= 0) {
    value = value.substring(0, delimiterIndex);
  }
  value = value.replaceAll(RegExp(r'^/+|/+$'), '');
  if (value.isEmpty || value.length > 255) {
    return null;
  }
  if (!RegExp(r'^[a-z0-9._]+$').hasMatch(value)) {
    return null;
  }
  return value;
}

String _pendingValueWithDefaultScheme(String value) {
  if (value.contains('://')) {
    return value;
  }
  if (value.startsWith('//')) {
    return 'https:$value';
  }
  return 'https://$value';
}

bool _isNativePendingValue(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('iosbundleid:') ||
      normalized.startsWith('androidapp:');
}

int _firstPendingDelimiterIndex(String value) {
  var result = -1;
  for (final delimiter in const ['/', '?', '#']) {
    final index = value.indexOf(delimiter);
    if (index >= 0 && (result == -1 || index < result)) {
      result = index;
    }
  }
  return result;
}
