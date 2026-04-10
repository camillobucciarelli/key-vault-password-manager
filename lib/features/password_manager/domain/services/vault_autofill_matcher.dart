import '../models/vault_entry.dart';

class VaultAutofillMatcher {
  List<VaultEntry> findBestMatches({
    required List<VaultEntry> entries,
    Set<String> packageNames = const {},
    Set<String> webDomains = const {},
    int limit = 10,
  }) {
    final normalizedPackages = packageNames
        .map((name) => _normalize(name))
        .where((name) => name.isNotEmpty)
        .toSet();
    final normalizedDomains = webDomains
        .map((domain) => _normalizeDomain(domain))
        .where((domain) => domain.isNotEmpty)
        .toSet();

    final scopedSearch =
        normalizedPackages.isNotEmpty || normalizedDomains.isNotEmpty;

    final scored = <_ScoredEntry>[];
    for (final entry in entries) {
      if (entry.username.trim().isEmpty && entry.password.trim().isEmpty) {
        continue;
      }

      final score = _scoreEntry(
        entry,
        packageNames: normalizedPackages,
        webDomains: normalizedDomains,
      );

      if (scopedSearch && score <= 0) {
        continue;
      }

      scored.add(_ScoredEntry(entry: entry, score: score));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }

      final byUpdatedAt = _compareDateDesc(
        a.entry.updatedAt,
        b.entry.updatedAt,
      );
      if (byUpdatedAt != 0) {
        return byUpdatedAt;
      }

      final byTitle = a.entry.title.toLowerCase().compareTo(
        b.entry.title.toLowerCase(),
      );
      if (byTitle != 0) {
        return byTitle;
      }

      return a.entry.username.toLowerCase().compareTo(
        b.entry.username.toLowerCase(),
      );
    });

    return scored.take(limit).map((result) => result.entry).toList();
  }

  int _scoreEntry(
    VaultEntry entry, {
    required Set<String> packageNames,
    required Set<String> webDomains,
  }) {
    var score = 0;

    if (packageNames.isNotEmpty) {
      final entryPackages = _extractPackageIdentifiers(entry);
      for (final expected in packageNames) {
        if (entryPackages.contains(expected)) {
          score += 140;
          continue;
        }
        if (entryPackages.any(
          (candidate) => _identifiersRelated(candidate, expected),
        )) {
          score += 100;
          continue;
        }
        if (entryPackages.any((candidate) => candidate.contains(expected))) {
          score += 70;
        }
      }
    }

    if (webDomains.isNotEmpty) {
      final entryDomain = _domainFromUrl(entry.url);
      if (entryDomain.isNotEmpty) {
        for (final expected in webDomains) {
          if (entryDomain == expected) {
            score += 140;
            continue;
          }
          if (entryDomain.endsWith('.$expected') ||
              expected.endsWith('.$entryDomain')) {
            score += 110;
            continue;
          }
          if (_registrableDomain(entryDomain).isNotEmpty &&
              _registrableDomain(entryDomain) == _registrableDomain(expected)) {
            score += 80;
          }
        }
      }

      final normalizedTitle = _normalize(entry.title);
      for (final expected in webDomains) {
        if (normalizedTitle.contains(expected)) {
          score += 35;
        }
      }
    }

    final hasUsername = entry.username.trim().isNotEmpty;
    final hasPassword = entry.password.trim().isNotEmpty;
    if (hasUsername && hasPassword) {
      score += 20;
    } else {
      score += 10;
    }

    return score;
  }

  Set<String> _extractPackageIdentifiers(VaultEntry entry) {
    final values = <String>{};

    // 1. URL schemes: androidapp:// and iosbundleid://
    final trimmedUrl = entry.url.trim();
    if (trimmedUrl.isNotEmpty) {
      final uri = Uri.tryParse(trimmedUrl);
      if (uri != null) {
        if (uri.scheme == 'androidapp' || uri.scheme == 'iosbundleid') {
          final id = _normalize(uri.host.isNotEmpty ? uri.host : uri.path);
          if (id.isNotEmpty) values.add(id);
        }
      }
    }

    // 2. Custom fields: KPH: androidPackage, KPH: iosBundle, and legacy keys
    for (final field in entry.customFields) {
      final normalizedKey = _normalize(field.key);
      final isKphAndroid = normalizedKey == 'kph: androidpackage';
      final isKphIos = normalizedKey == 'kph: iosbundle';
      final isLegacy =
          normalizedKey.contains('package') ||
          normalizedKey.contains('bundle') ||
          normalizedKey.contains('androidapp') ||
          normalizedKey.contains('iosapp');

      if (!isKphAndroid && !isKphIos && !isLegacy) continue;

      final splitValues = field.value
          .split(RegExp(r'[,;\s]+'))
          .map(_normalize)
          .where((v) => v.isNotEmpty);
      values.addAll(splitValues);
    }

    // 3. URL host fallback: bare single-label hosts (e.g. "myapp") as identifier
    final domain = _domainFromUrl(entry.url);
    if (domain.isNotEmpty && !domain.contains('.')) {
      values.add(domain);
    }

    return values;
  }

  String _domainFromUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null) {
      return '';
    }
    return _normalizeDomain(uri.host);
  }

  String _normalizeDomain(String value) {
    var normalized = _normalize(value);
    if (normalized.startsWith('www.')) {
      normalized = normalized.substring(4);
    }
    if (normalized.startsWith('m.')) {
      normalized = normalized.substring(2);
    }
    if (normalized.startsWith('mobile.')) {
      normalized = normalized.substring(7);
    }
    return normalized;
  }

  bool _identifiersRelated(String left, String right) {
    if (left == right) {
      return true;
    }
    return left.endsWith('.$right') || right.endsWith('.$left');
  }

  String _registrableDomain(String domain) {
    final parts = domain.split('.').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) {
      return domain;
    }
    return '${parts[parts.length - 2]}.${parts.last}';
  }

  int _compareDateDesc(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }
}

class _ScoredEntry {
  const _ScoredEntry({required this.entry, required this.score});

  final VaultEntry entry;
  final int score;
}
