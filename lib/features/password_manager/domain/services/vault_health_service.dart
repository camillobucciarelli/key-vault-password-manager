import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/duplicate_group.dart';
import '../models/vault_entry.dart';
import '../models/vault_health_report.dart';
import '../utils/password_strength.dart';

/// spec-005 T2: computes the five FR-4 health categories and the overall
/// score from data the app already holds in memory — no re-read from disk,
/// no network.
///
/// Security contract (non-negotiable, spec-005): reuse detection maps only
/// the **sha256 of the password**, never the plaintext. No `Map`/`Set` keyed
/// or valued by a raw password is ever built anywhere in this class.
class VaultHealthService {
  const VaultHealthService();

  static const _oldPasswordAgeThreshold = Duration(days: 365 * 2);

  static const _weights = <HealthCategoryKind, double>{
    HealthCategoryKind.weak: 0.35,
    HealthCategoryKind.reused: 0.25,
    HealthCategoryKind.old: 0.15,
    HealthCategoryKind.duplicates: 0.15,
    HealthCategoryKind.unmatchable: 0.10,
  };

  /// Builds the report for [activeEntries] (recycle-bin entries already
  /// excluded by the caller — see `VaultBloc._computeHealth`).
  ///
  /// [now] is always injected, never read from `DateTime.now()` directly
  /// inside this method, so the "old" category — and therefore the whole
  /// report — is deterministic and testable with a fixed clock.
  VaultHealthReport buildReport({
    required List<VaultEntry> activeEntries,
    required List<DuplicateGroup> duplicateGroups,
    required DateTime now,
  }) {
    final weak = _weakCategory(activeEntries);
    final reused = _reusedCategory(activeEntries);
    final old = _oldCategory(activeEntries, now: now);
    final duplicates = _duplicatesCategory(duplicateGroups);
    final unmatchable = _unmatchableCategory(activeEntries);

    final categories = [weak, reused, old, duplicates, unmatchable];
    final total = activeEntries.length;
    final score = _score(categories, total: total);

    return VaultHealthReport(score: score, categories: categories);
  }

  int _score(List<HealthCategory> categories, {required int total}) {
    if (total == 0) {
      return 100;
    }

    var penalty = 0.0;
    for (final category in categories) {
      final weight = _weights[category.kind]!;
      final clampedCount = category.count > total ? total : category.count;
      penalty += weight * clampedCount / total;
    }

    final raw = 100 * (1 - penalty);
    return raw.round().clamp(0, 100);
  }

  HealthCategory _weakCategory(List<VaultEntry> entries) {
    final ids = <String>[
      for (final entry in entries)
        if (evaluatePasswordStrength(entry.password).level ==
            PasswordStrengthLevel.weak)
          entry.id,
    ];
    return HealthCategory(
      kind: HealthCategoryKind.weak,
      count: ids.length,
      entryIds: ids,
    );
  }

  /// Reused = same password across >= 2 entries. Only the sha256 digest of
  /// each password is ever used as a map key — the plaintext password is
  /// read once (from the already-decrypted in-memory entry) and discarded
  /// immediately after hashing.
  HealthCategory _reusedCategory(List<VaultEntry> entries) {
    final idsByHash = <String, List<String>>{};
    for (final entry in entries) {
      if (entry.password.isEmpty) {
        continue;
      }
      final hash = sha256.convert(utf8.encode(entry.password)).toString();
      idsByHash.putIfAbsent(hash, () => []).add(entry.id);
    }

    final ids = <String>[
      for (final group in idsByHash.values)
        if (group.length > 1) ...group,
    ];
    return HealthCategory(
      kind: HealthCategoryKind.reused,
      count: ids.length,
      entryIds: ids,
    );
  }

  /// Old = `lastPasswordChangedAt` older than the 2-year threshold. Entries
  /// with no recorded change date are excluded (no data to judge, so they
  /// are not flagged) rather than assumed old.
  HealthCategory _oldCategory(
    List<VaultEntry> entries, {
    required DateTime now,
  }) {
    final cutoff = now.subtract(_oldPasswordAgeThreshold);
    final ids = <String>[
      for (final entry in entries)
        if (entry.lastPasswordChangedAt != null &&
            entry.lastPasswordChangedAt!.isBefore(cutoff))
          entry.id,
    ];
    return HealthCategory(
      kind: HealthCategoryKind.old,
      count: ids.length,
      entryIds: ids,
    );
  }

  /// Duplicates = `VaultDuplicateService` groups. Count is the number of
  /// groups (matches the Duplicates destination's own "N groups" header);
  /// entryIds is every entry across every group, for the tap-through.
  HealthCategory _duplicatesCategory(List<DuplicateGroup> groups) {
    final ids = <String>[
      for (final group in groups)
        for (final entry in group.entries) entry.id,
    ];
    return HealthCategory(
      kind: HealthCategoryKind.duplicates,
      count: groups.length,
      entryIds: ids,
    );
  }

  HealthCategory _unmatchableCategory(List<VaultEntry> entries) {
    final ids = <String>[
      for (final entry in entries)
        if (entry.url.trim().isEmpty && entry.username.trim().isEmpty) entry.id,
    ];
    return HealthCategory(
      kind: HealthCategoryKind.unmatchable,
      count: ids.length,
      entryIds: ids,
    );
  }
}
