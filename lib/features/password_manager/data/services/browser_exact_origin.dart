/// 009 / SR-2 — exact normalized browser origin, the Dart half of the contract
/// implemented in `desktop/browser_extension/overlay_security.js`.
///
/// This is **not** [DesktopBrowserAutofillMetadataMapper.normalizedOrigin].
/// That one routes through `_cleanHost`, which strips `www.`, `m.` and
/// `mobile.` labels and so makes `https://www.example.com` and
/// `https://example.com` compare equal. That collapse is a useful affordance
/// for ranking *possible* matches and is invalid for authorization: the two
/// names are different hosts, may be served by different parties, and one must
/// never authorize a credential fill on the other.
///
/// Every hostname label is preserved here. Equality is the whole tuple
/// `(scheme, ASCII host, effective port)`.
///
/// Both suites — the Node harness and `browser_exact_origin_test.dart` — assert
/// this behaviour against the same fixture,
/// `desktop/browser_extension/test/fixtures/origin_canonicalization_v1.json`.
library;

import 'dart:io';

import 'desktop_browser_autofill_cache.dart';

/// Service identifier type that may authorize an origin-bound overlay fill.
///
/// Deliberately distinct from the existing `url` type: `url` values are written
/// by [DesktopBrowserAutofillMetadataMapper.normalizedOrigin] and have
/// therefore *already* lost their `www.`/`m.`/`mobile.` label by the time they
/// reach any comparison. An `exactOrigin` value is produced by
/// [browserExactOriginOrNull] and preserves the host as written.
const exactOriginServiceIdentifierType = 'exactOrigin';

/// The only match policy the 009 overlay path accepts, on the native protocol
/// and on the app bridge alike. Echoed in every success response so a caller
/// can prove the strict rule was the one actually applied.
const overlayMatchPolicy = 'exactOrigin';

/// Capability advertised by `hello` when this host implements the 009 Slice A1
/// exact-origin contract.
const overlayExactOriginCapability = 'overlayExactOriginV1';

const _maxRawUrlLength = 4096;
const _maxHostLength = 253;
const _maxOriginLength = 512;

final _schemeRe = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):');
final _authorityRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://([^/?#]*)');
final _dottedQuadRe = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');

/// A host is "IPv4-shaped" when every label is something an IPv4 parser would
/// accept (decimal, octal or hex). `127.1`, `0177.0.0.1`, `0x7f.0.0.1` and the
/// bare dword `2130706433` all qualify; `example.com` does not.
final _ipv4ShapedRe = RegExp(
  r'^(?:0[xX][0-9a-fA-F]+|\d+)(?:\.(?:0[xX][0-9a-fA-F]+|\d+))*\.?$',
);

class BrowserExactOrigin {
  const BrowserExactOrigin({
    required this.scheme,
    required this.asciiHost,
    required this.effectivePort,
    required this.serialized,
  });

  final String scheme;
  final String asciiHost;
  final int effectivePort;
  final String serialized;

  @override
  bool operator ==(Object other) {
    return other is BrowserExactOrigin &&
        other.scheme == scheme &&
        other.asciiHost == asciiHost &&
        other.effectivePort == effectivePort;
  }

  @override
  int get hashCode => Object.hash(scheme, asciiHost, effectivePort);

  @override
  String toString() => serialized;
}

class BrowserExactOriginResult {
  const BrowserExactOriginResult.success(BrowserExactOrigin this.origin)
    : error = null;

  const BrowserExactOriginResult.failure(String this.error) : origin = null;

  final BrowserExactOrigin? origin;
  final String? error;

  bool get ok => origin != null;
}

/// Canonicalize an absolute HTTP(S) URL into a comparable exact origin.
///
/// Error codes mirror the JavaScript helper one-for-one, with one addition:
/// `idna_unsupported`. See the note on IDNA below.
BrowserExactOriginResult canonicalizeBrowserExactOrigin(Object? rawValue) {
  if (rawValue is! String) {
    return const BrowserExactOriginResult.failure('not_a_string');
  }
  final raw = rawValue.trim();
  if (raw.isEmpty) {
    return const BrowserExactOriginResult.failure('empty_value');
  }
  if (raw.length > _maxRawUrlLength) {
    return const BrowserExactOriginResult.failure('oversize_value');
  }

  // Scheme is checked on the raw text so `javascript:`, `data:` and
  // `chrome-extension:` are rejected by name rather than by side effect.
  final schemeMatch = _schemeRe.firstMatch(raw);
  if (schemeMatch == null) {
    return const BrowserExactOriginResult.failure('scheme_forbidden');
  }
  final rawScheme = schemeMatch.group(1)!.toLowerCase();
  if (rawScheme != 'http' && rawScheme != 'https') {
    return const BrowserExactOriginResult.failure('scheme_forbidden');
  }

  // Raw-authority inspection happens BEFORE parsing: `Uri` moves `alice:x@`
  // into a separate field and percent-encodes non-ASCII hosts, erasing the
  // evidence these checks need.
  final authorityMatch = _authorityRe.firstMatch(raw);
  if (authorityMatch == null) {
    return const BrowserExactOriginResult.failure('invalid_url');
  }
  final rawAuthority = authorityMatch.group(1)!;
  if (rawAuthority.isEmpty) {
    return const BrowserExactOriginResult.failure('empty_host');
  }
  if (rawAuthority.contains('@')) {
    return const BrowserExactOriginResult.failure('userinfo_forbidden');
  }
  // IDNA: `Uri` performs no punycode conversion — it percent-encodes the UTF-8
  // bytes instead. Accepting that would produce a canonical form the JS half
  // never produces, so a Unicode host is refused outright and fails closed.
  // See `_dartDivergences` in `browser_exact_origin_test.dart` for the full
  // reasoning; the ASCII/punycode spelling is fully supported.
  if (rawAuthority.codeUnits.any((unit) => unit > 0x7f) ||
      rawAuthority.contains('%')) {
    return const BrowserExactOriginResult.failure('idna_unsupported');
  }

  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return const BrowserExactOriginResult.failure('invalid_url');
  }
  // Defence in depth: the parser's own view of userinfo must also be empty.
  if (uri.userInfo.isNotEmpty) {
    return const BrowserExactOriginResult.failure('userinfo_forbidden');
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return const BrowserExactOriginResult.failure('scheme_forbidden');
  }
  if (uri.host.isEmpty) {
    return const BrowserExactOriginResult.failure('empty_host');
  }

  final isBracketedLiteral = rawAuthority.startsWith('[');
  final String asciiHost;
  if (isBracketedLiteral) {
    final canonicalIpv6 = _canonicalIpv6(uri.host);
    if (canonicalIpv6 == null) {
      return const BrowserExactOriginResult.failure('invalid_url');
    }
    asciiHost = '[$canonicalIpv6]';
  } else {
    final host = _stripTrailingDots(uri.host.toLowerCase());
    if (host.isEmpty) {
      return const BrowserExactOriginResult.failure('empty_host');
    }
    // Non-canonical IPv4. `Uri` does not normalize these at all, so unlike the
    // WHATWG parser there is no rewritten form to compare against: any
    // IPv4-shaped authority that is not already a canonical dotted quad is
    // rejected rather than treated as a DNS name.
    if (_ipv4ShapedRe.hasMatch(host) && !_isCanonicalDottedQuad(host)) {
      return const BrowserExactOriginResult.failure('noncanonical_ipv4');
    }
    if (host.length > _maxHostLength) {
      return const BrowserExactOriginResult.failure('oversize_host');
    }
    asciiHost = host;
  }

  final defaultPort = scheme == 'https' ? 443 : 80;
  // `Uri` already drops a port equal to the scheme default, so `hasPort` is
  // false for `https://example.com:443`.
  final effectivePort = uri.hasPort ? uri.port : defaultPort;
  if (effectivePort < 1 || effectivePort > 65535) {
    return const BrowserExactOriginResult.failure('invalid_port');
  }

  final serialized = effectivePort == defaultPort
      ? '$scheme://$asciiHost'
      : '$scheme://$asciiHost:$effectivePort';
  if (serialized.length > _maxOriginLength) {
    return const BrowserExactOriginResult.failure('oversize_value');
  }

  return BrowserExactOriginResult.success(
    BrowserExactOrigin(
      scheme: scheme,
      asciiHost: asciiHost,
      effectivePort: effectivePort,
      serialized: serialized,
    ),
  );
}

/// The canonical serialized origin, or `null` when the input is unacceptable.
String? browserExactOriginOrNull(Object? rawValue) {
  return canonicalizeBrowserExactOrigin(rawValue).origin?.serialized;
}

/// Exact origin equality over the full `(scheme, host, effective port)` tuple.
///
/// Both sides are canonicalized first, so this is safe to call on raw values.
/// An unacceptable value on either side is never equal to anything.
bool browserExactOriginsEqual(Object? left, Object? right) {
  final a = browserExactOriginOrNull(left);
  final b = browserExactOriginOrNull(right);
  return a != null && a == b;
}

/// Whether [origin] may receive the secrets of an entry exposing
/// [serviceIdentifiers], under the **overlay** policy.
///
/// This is deliberately stricter than
/// [DesktopBrowserAutofillMetadataMapper.isRevealAuthorizedOrigin], which is
/// the popup policy introduced by the reveal-authorization fix. The two rules
/// differ on purpose and the difference must stay explicit:
///
/// | | popup (`isRevealAuthorizedOrigin`) | overlay (this) |
/// | --- | --- | --- |
/// | `exactOrigin` identifier, same origin | n/a | authorize |
/// | `url` identifier, same origin | authorize | refuse |
/// | `url` identifier, `http` stored / `https` page | authorize (upgrade) | refuse |
/// | `domain` identifier, `https` page | authorize | refuse |
/// | `domain` identifier, non-WebPKI host over `http` | authorize | refuse |
///
/// The overlay runs *inside the page*, so its exposure is larger and its
/// authorization surface is correspondingly smaller: an origin-bound fill needs
/// an origin the user actually wrote. A domain-only entry stays visible as
/// possible metadata (SR-2) but can never reveal.
///
/// This does not strand the LAN cohort the popup's `http` allowance exists for:
/// an entry stored with a full URL such as `http://192.168.1.10:8443` carries an
/// `exactOrigin` identifier and is authorized through the exact branch.
bool isExactOriginAuthorized({
  required List<DesktopBrowserAutofillServiceIdentifier> serviceIdentifiers,
  required String origin,
}) {
  final target = browserExactOriginOrNull(origin);
  if (target == null) {
    return false;
  }
  for (final identifier in serviceIdentifiers) {
    if (identifier.type != exactOriginServiceIdentifierType) {
      continue;
    }
    if (browserExactOriginOrNull(identifier.value) == target) {
      return true;
    }
  }
  return false;
}

String _stripTrailingDots(String host) {
  var out = host;
  while (out.endsWith('.')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

bool _isCanonicalDottedQuad(String host) {
  if (!_dottedQuadRe.hasMatch(host)) {
    return false;
  }
  for (final label in host.split('.')) {
    if (label.length > 1 && label.startsWith('0')) {
      return false;
    }
    final value = int.tryParse(label);
    if (value == null || value > 255) {
      return false;
    }
  }
  return true;
}

/// RFC 5952 serialization of an IPv6 literal.
///
/// `Uri` neither validates nor compresses IPv6 literals, so the address is
/// parsed into its 16 bytes by [InternetAddress] (which does handle `::`
/// expansion and embedded IPv4) and re-serialized from those bytes. Working
/// from the bytes means every spelling of one address — expanded, compressed,
/// upper-case — collapses to exactly one string.
///
/// One deliberate simplification: an IPv4-mapped address is emitted in pure
/// hextet form (`::ffff:7f00:1`) rather than RFC 5952's dotted tail. Both sides
/// of the contract canonicalize through this function, and the WHATWG URL
/// serializer the JS half uses makes the same choice, so equality is preserved.
String? _canonicalIpv6(String rawHost) {
  final address = InternetAddress.tryParse(rawHost);
  if (address == null || address.type != InternetAddressType.IPv6) {
    return null;
  }
  final bytes = address.rawAddress;
  if (bytes.length != 16) {
    return null;
  }
  final groups = <int>[
    for (var i = 0; i < 16; i += 2) (bytes[i] << 8) | bytes[i + 1],
  ];

  var bestStart = -1;
  var bestLength = 0;
  var runStart = -1;
  for (var i = 0; i <= groups.length; i += 1) {
    final isZero = i < groups.length && groups[i] == 0;
    if (isZero) {
      if (runStart < 0) {
        runStart = i;
      }
      continue;
    }
    if (runStart >= 0) {
      final length = i - runStart;
      // RFC 5952: only a run of two or more groups may be compressed, and the
      // longest run wins (leftmost on a tie).
      if (length > 1 && length > bestLength) {
        bestStart = runStart;
        bestLength = length;
      }
      runStart = -1;
    }
  }

  // The compressed run becomes an empty token, so joining with ':' yields the
  // doubled colon everywhere except at the string edges, which are patched up
  // below.
  final parts = <String>[];
  var index = 0;
  while (index < groups.length) {
    if (index == bestStart) {
      parts.add('');
      index += bestLength;
      continue;
    }
    parts.add(groups[index].toRadixString(16));
    index += 1;
  }
  if (parts.length == 1 && parts.single.isEmpty) {
    return '::';
  }
  var out = parts.join(':');
  if (parts.first.isEmpty) {
    out = ':$out';
  }
  if (parts.last.isEmpty) {
    out = '$out:';
  }
  return out;
}
