import '../models/apple_autofill_v2_models.dart';
import '../models/vault_entry.dart';

class AppleAutofillV2PayloadMapper {
  const AppleAutofillV2PayloadMapper();

  List<AppleAutofillV2Credential> mapEntries(List<VaultEntry> entries) {
    return entries
        .map(mapEntry)
        .whereType<AppleAutofillV2Credential>()
        .toList(growable: false);
  }

  AppleAutofillV2Credential? mapEntry(VaultEntry entry) {
    final id = entry.id.trim();
    if (id.isEmpty || entry.password.isEmpty) {
      return null;
    }

    final normalizedUrl = _normalizedWebOrigin(entry.url);
    return AppleAutofillV2Credential(
      id: id,
      title: entry.title.trim(),
      username: entry.username.trim(),
      password: entry.password,
      url: normalizedUrl,
      serviceIdentifiers: _serviceIdentifiersForEntry(entry, normalizedUrl),
    );
  }

  List<AppleAutofillV2ServiceIdentifier> _serviceIdentifiersForEntry(
    VaultEntry entry,
    String? normalizedUrl,
  ) {
    final identifiers = <AppleAutofillV2ServiceIdentifier>[];
    final seen = <String>{};

    void add(AppleAutofillV2ServiceIdentifier? identifier) {
      if (identifier == null || identifier.value.trim().isEmpty) {
        return;
      }
      final key = '${identifier.type.channelValue}:${identifier.value}';
      if (seen.add(key)) {
        identifiers.add(identifier);
      }
    }

    if (normalizedUrl != null) {
      add(AppleAutofillV2ServiceIdentifier.url(normalizedUrl));
      add(
        _normalizedHostFromWebValue(
          normalizedUrl,
        ).map(AppleAutofillV2ServiceIdentifier.domain),
      );
    }

    add(
      _bundleIdFromIosBundleUrl(
        entry.url,
      ).map(AppleAutofillV2ServiceIdentifier.bundleId),
    );

    for (final field in entry.customFields) {
      final key = _normalizeFieldKey(field.key);
      if (_isAppleBundleField(key)) {
        for (final value in _splitCustomFieldValues(field.value)) {
          add(
            _normalizedBundleId(
              value,
            ).map(AppleAutofillV2ServiceIdentifier.bundleId),
          );
        }
        continue;
      }

      if (_isDomainField(key)) {
        for (final value in _splitCustomFieldValues(field.value)) {
          add(
            _normalizedHostFromWebValue(
              value,
            ).map(AppleAutofillV2ServiceIdentifier.domain),
          );
        }
        continue;
      }

      if (_isUrlField(key)) {
        for (final value in _splitCustomFieldValues(field.value)) {
          if (_isIosBundleValue(value)) {
            add(
              _normalizedBundleId(
                value,
              ).map(AppleAutofillV2ServiceIdentifier.bundleId),
            );
            continue;
          }
          final origin = _normalizedWebOrigin(value);
          add(origin.map(AppleAutofillV2ServiceIdentifier.url));
          add(
            origin
                .flatMap(_normalizedHostFromWebValue)
                .map(AppleAutofillV2ServiceIdentifier.domain),
          );
        }
      }
    }

    return identifiers;
  }

  bool _isAppleBundleField(String key) {
    return key == 'iosbundle' ||
        key == 'iosbundleid' ||
        key == 'bundleid' ||
        key == 'applebundleid' ||
        key == 'kph:iosbundle' ||
        key == 'kph:iosbundleid' ||
        key == 'kph:bundleid';
  }

  bool _isDomainField(String key) {
    return key == 'domain' ||
        key == 'domains' ||
        key == 'webdomain' ||
        key == 'hostname' ||
        key == 'host' ||
        key == 'kph:domain' ||
        key == 'kph:webdomain';
  }

  bool _isUrlField(String key) {
    return key == 'url' ||
        key == 'uri' ||
        key == 'website' ||
        key == 'weburl' ||
        key == 'loginurl' ||
        key == 'kph:url' ||
        key == 'kph:uri';
  }

  String _normalizeFieldKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  }

  Iterable<String> _splitCustomFieldValues(String value) sync* {
    for (final token in value.split(RegExp(r'[,;\s]+'))) {
      final trimmed = token.trim();
      if (trimmed.isNotEmpty) {
        yield trimmed;
      }
    }
  }

  String? _normalizedWebOrigin(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty || _isIosBundleValue(trimmed)) {
      return null;
    }

    final candidate = _valueWithDefaultScheme(trimmed);
    final uri = Uri.tryParse(candidate);
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

  String _valueWithDefaultScheme(String value) {
    if (value.contains('://')) {
      return value;
    }
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    return 'https://$value';
  }

  String? _normalizedHostFromWebValue(String rawValue) {
    final origin = _normalizedWebOrigin(rawValue);
    if (origin == null) {
      return null;
    }
    return _cleanHost(Uri.tryParse(origin)?.host);
  }

  String? _cleanHost(String? rawHost) {
    final trimmedHost = rawHost?.trim().toLowerCase();
    if (trimmedHost == null || trimmedHost.isEmpty) {
      return null;
    }
    var host = trimmedHost;
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
    if (host.isEmpty || host.length > 253 || host.contains(RegExp(r'\s'))) {
      return null;
    }
    return host;
  }

  bool _isIosBundleValue(String value) {
    return value.trim().toLowerCase().startsWith('iosbundleid:');
  }

  String? _bundleIdFromIosBundleUrl(String rawValue) {
    if (!_isIosBundleValue(rawValue)) {
      return null;
    }
    return _normalizedBundleId(rawValue);
  }

  String? _normalizedBundleId(String rawValue) {
    var value = rawValue.trim().toLowerCase();
    if (value.isEmpty) {
      return null;
    }

    if (value.startsWith('iosbundleid:')) {
      final withoutScheme = value.substring('iosbundleid:'.length);
      value = withoutScheme.replaceAll(RegExp(r'^/+'), '');
      final slashIndex = value.indexOf('/');
      if (slashIndex >= 0) {
        value = value.substring(0, slashIndex);
      }
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
}

extension _NullableMap<T extends Object> on T? {
  R? map<R>(R Function(T value) mapper) {
    final value = this;
    return value == null ? null : mapper(value);
  }

  R? flatMap<R>(R? Function(T value) mapper) {
    final value = this;
    return value == null ? null : mapper(value);
  }
}
