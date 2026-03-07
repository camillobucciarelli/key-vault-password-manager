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
          score += 120;
          continue;
        }
        if (entryPackages.any((candidate) => candidate.contains(expected))) {
          score += 80;
        }
      }
    }

    if (webDomains.isNotEmpty) {
      final entryDomain = _domainFromUrl(entry.url);
      if (entryDomain.isNotEmpty) {
        for (final expected in webDomains) {
          if (entryDomain == expected) {
            score += 110;
            continue;
          }
          if (entryDomain.endsWith('.$expected') ||
              expected.endsWith('.$entryDomain')) {
            score += 90;
          }
        }
      }

      final normalizedTitle = _normalize(entry.title);
      for (final expected in webDomains) {
        if (normalizedTitle.contains(expected)) {
          score += 30;
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
    for (final field in entry.customFields) {
      final normalizedKey = _normalize(field.key);
      final looksLikePackageField =
          normalizedKey.contains('package') ||
          normalizedKey.contains('bundle') ||
          normalizedKey.contains('androidapp') ||
          normalizedKey.contains('iosapp');
      if (!looksLikePackageField) {
        continue;
      }

      final splitValues = field.value
          .split(RegExp(r'[,;\s]+'))
          .map((value) => _normalize(value))
          .where((value) => value.isNotEmpty);
      values.addAll(splitValues);
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
    return normalized;
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
