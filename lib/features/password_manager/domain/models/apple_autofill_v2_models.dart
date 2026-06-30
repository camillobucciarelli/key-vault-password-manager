import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

enum AppleAutofillV2ServiceIdentifierType {
  domain('domain'),
  url('url'),
  bundleId('bundleId');

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
    return AppleAutofillV2PendingAssociation(
      id: _readString(map, 'id') ?? '',
      databaseId: _readString(map, 'databaseId') ?? '',
      entryId: _readString(map, 'entryId') ?? '',
      serviceIdentifierType: _readString(map, 'serviceIdentifierType') ?? '',
      serviceIdentifierValue: _readString(map, 'serviceIdentifierValue') ?? '',
      displayService: _readString(map, 'displayService') ?? '',
      createdAtEpochMs: _readInt(map, 'createdAtEpochMs'),
      platform: _readString(map, 'platform'),
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
    serviceIdentifierValue,
    displayService,
    createdAtEpochMs,
    platform,
  ];
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
