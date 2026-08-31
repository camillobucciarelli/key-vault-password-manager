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

final RegExp _urlScheme = RegExp(r'^(https?|ftp)://');

/// Normalizes a URL for equality checks: lowercases, strips scheme, `www.`,
/// trailing slash, query and fragment. `https://www.GitHub.com/login?x#y`,
/// `github.com/login` and `http://github.com/login/` all compare equal.
String normalizeUrlForCompare(String url) {
  var result = url.trim().toLowerCase();
  result = result.replaceFirst(_urlScheme, '');
  result = result.replaceFirst(RegExp(r'^www\.'), '');
  final queryIdx = result.indexOf('?');
  if (queryIdx >= 0) result = result.substring(0, queryIdx);
  final fragmentIdx = result.indexOf('#');
  if (fragmentIdx >= 0) result = result.substring(0, fragmentIdx);
  if (result.endsWith('/')) result = result.substring(0, result.length - 1);
  return result;
}
