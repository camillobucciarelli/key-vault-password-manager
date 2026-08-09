import 'package:equatable/equatable.dart';

/// The five health categories computed by `VaultHealthService` (spec-005
/// FR-4). Order here is the display order on the Health destination.
enum HealthCategoryKind { weak, reused, old, duplicates, unmatchable }

/// One row of the health report: how many entries fall into [kind], and
/// which ones (so the Health screen can open a filtered list on tap).
///
/// [entryIds] never contains plaintext passwords or any password-derived
/// value — see `VaultHealthService` for the reuse-detection contract.
class HealthCategory extends Equatable {
  const HealthCategory({
    required this.kind,
    required this.count,
    required this.entryIds,
  });

  final HealthCategoryKind kind;
  final int count;
  final List<String> entryIds;

  @override
  List<Object?> get props => [kind, count, entryIds];
}

/// `VaultHealthReport { score, categories }` (spec-005 T1). Deterministic
/// output of `VaultHealthService.buildReport` — same vault (+ same `now`)
/// always yields the same report, see plan.md "Health score".
class VaultHealthReport extends Equatable {
  const VaultHealthReport({required this.score, required this.categories});

  /// 0-100, see `VaultHealthService` for the exact formula.
  final int score;

  /// Always exactly 5 entries, one per `HealthCategoryKind` value, in enum
  /// declaration order.
  final List<HealthCategory> categories;

  static const empty = VaultHealthReport(
    score: 100,
    categories: [
      HealthCategory(kind: HealthCategoryKind.weak, count: 0, entryIds: []),
      HealthCategory(kind: HealthCategoryKind.reused, count: 0, entryIds: []),
      HealthCategory(kind: HealthCategoryKind.old, count: 0, entryIds: []),
      HealthCategory(
        kind: HealthCategoryKind.duplicates,
        count: 0,
        entryIds: [],
      ),
      HealthCategory(
        kind: HealthCategoryKind.unmatchable,
        count: 0,
        entryIds: [],
      ),
    ],
  );

  HealthCategory category(HealthCategoryKind kind) =>
      categories.firstWhere((category) => category.kind == kind);

  @override
  List<Object?> get props => [score, categories];
}
