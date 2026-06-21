import '../models/autofill_models.dart';
import '../models/vault_custom_field.dart';
import '../models/vault_entry.dart';

class VaultAutofillMatcher {
  List<AutofillCandidate> findCandidates({
    required List<VaultEntry> entries,
    required AutofillRequest request,
  }) {
    final policy = request.policy;
    final limit = policy.maxCandidates.clamp(0, 50).toInt();
    if (limit == 0) {
      return const [];
    }

    final targets = request.targets
        .map(_normalizeTarget)
        .whereType<AutofillTarget>()
        .toList(growable: false);

    if (targets.isEmpty && !policy.allowUnscopedSuggestions) {
      return const [];
    }

    final scored = <_ScoredEntry>[];
    for (final entry in entries) {
      final hasUsername = entry.username.trim().isNotEmpty;
      final hasPassword = entry.password.trim().isNotEmpty;
      if (!hasUsername && !hasPassword) {
        continue;
      }

      final match = _scoreEntry(entry, targets: targets);

      if (targets.isNotEmpty && match.score <= 0) {
        continue;
      }

      final rankScore = match.score + (hasUsername && hasPassword ? 20 : 10);

      scored.add(
        _ScoredEntry(
          candidate: AutofillCandidate(
            entryId: entry.id,
            title: entry.title,
            username: entry.username,
            hasPassword: hasPassword,
            webDomain: _domainFromUrl(entry.url),
            matchedTargets: match.targets,
          ),
          updatedAt: entry.updatedAt,
          score: rankScore,
        ),
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }

      final byUpdatedAt = _compareDateDesc(a.updatedAt, b.updatedAt);
      if (byUpdatedAt != 0) {
        return byUpdatedAt;
      }

      final byTitle = a.candidate.title.toLowerCase().compareTo(
        b.candidate.title.toLowerCase(),
      );
      if (byTitle != 0) {
        return byTitle;
      }

      return a.candidate.username.toLowerCase().compareTo(
        b.candidate.username.toLowerCase(),
      );
    });

    return scored.take(limit).map((result) => result.candidate).toList();
  }

  _MatchScore _scoreEntry(
    VaultEntry entry, {
    required List<AutofillTarget> targets,
  }) {
    var score = 0;
    final matchedTargets = <AutofillTarget>[];

    for (final target in targets) {
      switch (target.kind) {
        case AutofillTargetKind.androidPackage:
        case AutofillTargetKind.appleBundleId:
          final entryIds = _extractAppIdentifiers(entry, target.kind);
          if (entryIds.contains(target.value)) {
            score += 140;
            matchedTargets.add(target);
          }
          break;
        case AutofillTargetKind.webDomain:
          final entryDomain = _domainFromUrl(entry.url);
          final domainScore = _scoreDomainMatch(
            credentialDomain: entryDomain,
            requestDomain: target.value,
          );
          if (domainScore > 0) {
            score += domainScore;
            matchedTargets.add(target);
            if (_titleMentionsDomain(entry.title, target.value)) {
              score += 5;
            }
          }
          break;
      }
    }

    return _MatchScore(score: score, targets: matchedTargets);
  }

  Set<String> _extractAppIdentifiers(
    VaultEntry entry,
    AutofillTargetKind targetKind,
  ) {
    final values = <String>{};

    final trimmedUrl = entry.url.trim();
    if (trimmedUrl.isNotEmpty) {
      final uri = Uri.tryParse(trimmedUrl);
      if (uri != null) {
        final isAndroidTarget = targetKind == AutofillTargetKind.androidPackage;
        final isAppleTarget = targetKind == AutofillTargetKind.appleBundleId;
        if ((isAndroidTarget && uri.scheme == 'androidapp') ||
            (isAppleTarget && uri.scheme == 'iosbundleid')) {
          final id = _normalizeAppIdentifier(
            uri.host.isNotEmpty ? uri.host : uri.path,
          );
          if (id.isNotEmpty) {
            values.add(id);
          }
        }
      }
    }

    for (final field in entry.customFields) {
      if (!_fieldMatchesTarget(field, targetKind)) {
        continue;
      }

      final splitValues = field.value
          .split(RegExp(r'[,;\s]+'))
          .map(_normalizeAppIdentifier)
          .where((v) => v.isNotEmpty);
      values.addAll(splitValues);
    }

    return values;
  }

  bool _fieldMatchesTarget(
    VaultCustomField field,
    AutofillTargetKind targetKind,
  ) {
    final key = _normalizeFieldKey(field.key);
    return switch (targetKind) {
      AutofillTargetKind.androidPackage =>
        key == 'androidpackage' ||
            key == 'packagename' ||
            key == 'kph:androidpackage',
      AutofillTargetKind.appleBundleId =>
        key == 'iosbundle' ||
            key == 'iosbundleid' ||
            key == 'bundleid' ||
            key == 'kph:iosbundle',
      AutofillTargetKind.webDomain => false,
    };
  }

  AutofillTarget? _normalizeTarget(AutofillTarget target) {
    switch (target.kind) {
      case AutofillTargetKind.androidPackage:
        final value = _normalizeAppIdentifier(target.value);
        return value.isEmpty ? null : AutofillTarget.androidPackage(value);
      case AutofillTargetKind.appleBundleId:
        final value = _normalizeAppIdentifier(target.value);
        return value.isEmpty ? null : AutofillTarget.appleBundleId(value);
      case AutofillTargetKind.webDomain:
        final value = _domainFromRawTarget(target.value);
        return value.isEmpty ? null : AutofillTarget.webDomain(value);
    }
  }

  int _scoreDomainMatch({
    required String credentialDomain,
    required String requestDomain,
  }) {
    if (credentialDomain.isEmpty || requestDomain.isEmpty) {
      return 0;
    }

    if (credentialDomain == requestDomain) {
      return 140;
    }

    // TODO(autofill-v2): integrate the Public Suffix List before supporting
    // broader same-site heuristics. Until then, only exact domains and explicit
    // dot-boundary parent/subdomain relationships are considered safe.
    if (credentialDomain.endsWith('.$requestDomain')) {
      return 115;
    }
    if (requestDomain.endsWith('.$credentialDomain')) {
      return 105;
    }

    return 0;
  }

  bool _titleMentionsDomain(String title, String domain) {
    final normalizedTitle = _normalize(title);
    if (normalizedTitle.isEmpty) {
      return false;
    }
    return normalizedTitle.contains(domain);
  }

  String _domainFromUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final hasScheme = trimmed.contains('://');
    final uri = Uri.tryParse(hasScheme ? trimmed : 'https://$trimmed');
    if (uri == null || uri.host.isEmpty) {
      return '';
    }
    if (hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      return '';
    }
    return _normalizeDomain(uri.host);
  }

  String _domainFromRawTarget(String rawTarget) {
    final trimmed = rawTarget.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final uri = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed',
    );
    if (uri != null && uri.host.isNotEmpty) {
      return _normalizeDomain(uri.host);
    }
    return _normalizeDomain(trimmed);
  }

  String _normalizeDomain(String value) {
    var normalized = _normalize(value);
    if (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
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

  String _normalizeAppIdentifier(String value) {
    return _normalize(value).replaceAll(RegExp(r'^/+|/+$'), '');
  }

  String _normalizeFieldKey(String value) {
    return _normalize(value).replaceAll(RegExp(r'[\s_-]+'), '');
  }
}

class _ScoredEntry {
  const _ScoredEntry({
    required this.candidate,
    required this.updatedAt,
    required this.score,
  });

  final AutofillCandidate candidate;
  final DateTime? updatedAt;
  final int score;
}

class _MatchScore {
  const _MatchScore({required this.score, required this.targets});

  final int score;
  final List<AutofillTarget> targets;
}
