/// Custom-field keys that carry additional URLs for an entry.
///
/// The vault's primary `url` is a first-class KDBX field; extra websites are
/// stored as custom strings so every KeePass client round-trips them. The
/// editor writes `KP2A_URL_1..n` (the KeePass2Android / KeePassXC
/// convention); matching also accepts the KeePassHttp `KPH: URL` family and
/// the plain synonyms other clients use.
library;

/// Key prefix the editor writes for additional URLs (`KP2A_URL_1`, ...).
const String kp2aUrlKeyPrefix = 'KP2A_URL_';

final RegExp _kphUrlPattern = RegExp(r'^kph:(url|uri)\d*$');
final RegExp _kp2aUrlPattern = RegExp(r'^kp2aurl\d*$');
final RegExp _keySeparators = RegExp(r'[\s_-]+');

/// Lowercases and strips spaces/underscores/dashes, so `KP2A_URL_1`,
/// `kp2a url 1` and `kp2a-url-1` all compare equal. Idempotent.
String normalizeUrlFieldKey(String value) =>
    value.trim().toLowerCase().replaceAll(_keySeparators, '');

/// True when [key] names a custom field whose value is a URL.
bool isUrlFieldKey(String key) {
  final normalized = normalizeUrlFieldKey(key);
  return normalized == 'url' ||
      normalized == 'uri' ||
      normalized == 'website' ||
      normalized == 'weburl' ||
      normalized == 'loginurl' ||
      _kphUrlPattern.hasMatch(normalized) ||
      _kp2aUrlPattern.hasMatch(normalized);
}
