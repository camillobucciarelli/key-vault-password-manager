part of '../vault_screen.dart';

// FR-4 / T4: Health destination (screen 9). Score circle 64 (Caprasimo 22);
// five `KvListRow`-style category rows, each with a Caprasimo 18 count
// before the chevron. Tapping "Duplicates" opens the Duplicates screen
// (T10); the other four categories are informational rows today — no
// filtered-list destination exists yet for weak/reused/old/unmatchable
// (out of scope for this spec, see final report).

class _VaultHealthDestination extends StatelessWidget {
  const _VaultHealthDestination();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return BlocBuilder<VaultBloc, VaultState>(
      // Compare score + per-category counts only, not `healthReport` itself
      // — its `HealthCategory.entryIds` lists make `Equatable.==` O(entries)
      // per comparison, and this buildWhen runs on every VaultState change
      // in the whole app (every search keystroke, every tick). Same
      // lightweight-comparison rule as `VaultState.props` — see its
      // comment. The row builder below only renders score + count per
      // category, never entryIds, so this can't miss a visible change.
      buildWhen: (previous, current) =>
          previous.healthReport.score != current.healthReport.score ||
          !_sameCategoryCounts(
            previous.healthReport.categories,
            current.healthReport.categories,
          ) ||
          previous.allEntries.length != current.allEntries.length ||
          previous.databasePath != current.databasePath,
      builder: (context, state) {
        final report = state.healthReport;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health',
                style: AppTextStyles.screenTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              Text(
                '${state.allEntries.length} records in '
                '${path.basename(state.databasePath)}',
                style: AppTextStyles.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 18),
              _ScoreCard(report: report),
              const SizedBox(height: 10),
              for (final kind in HealthCategoryKind.values) ...[
                _HealthCategoryRow(
                  category: report.category(kind),
                  onTap: kind == HealthCategoryKind.duplicates
                      ? () => _showDuplicatesDialog(context)
                      : null,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

bool _sameCategoryCounts(
  List<HealthCategory> previous,
  List<HealthCategory> current,
) {
  if (previous.length != current.length) {
    return false;
  }
  for (var i = 0; i < previous.length; i++) {
    if (previous[i].kind != current[i].kind ||
        previous[i].count != current[i].count) {
      return false;
    }
  }
  return true;
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final VaultHealthReport report;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final needsAttention = report.categories
        .where((c) => c.kind != HealthCategoryKind.duplicates)
        .fold<int>(0, (sum, c) => sum + c.count);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card + 2),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.positiveTint,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${report.score}',
              style: AppTextStyles.numericLarge.copyWith(
                fontFamily: AppTextStyles.headingFamily,
                fontWeight: FontWeight.w400,
                color: colors.positiveText,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statusLabel(report.score),
                  style: AppTextStyles.panelTitleLarge.copyWith(
                    fontSize: 18,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  needsAttention == 0
                      ? 'No records need attention'
                      : needsAttention == 1
                      ? '1 record needs attention'
                      : '$needsAttention records need attention',
                  style: AppTextStyles.secondary.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(int score) {
    if (score >= 90) return 'Looking great';
    if (score >= 70) return 'Mostly healthy';
    if (score >= 40) return 'Needs attention';
    return 'At risk';
  }
}

class _HealthCategoryInfo {
  const _HealthCategoryInfo({
    required this.title,
    required this.subtitle,
    required this.glyph,
    required this.variant,
  });

  final String title;
  final String subtitle;
  final AppGlyph glyph;
  final KvTagVariant variant;
}

const _healthCategoryInfo = <HealthCategoryKind, _HealthCategoryInfo>{
  HealthCategoryKind.weak: _HealthCategoryInfo(
    title: 'Weak passwords',
    subtitle: 'Under 40 bits of entropy',
    glyph: AppGlyph.warning,
    variant: KvTagVariant.attention,
  ),
  HealthCategoryKind.reused: _HealthCategoryInfo(
    title: 'Reused passwords',
    subtitle: 'Same password in 2+ records',
    glyph: AppGlyph.copy,
    variant: KvTagVariant.attention,
  ),
  HealthCategoryKind.old: _HealthCategoryInfo(
    title: 'Old passwords',
    subtitle: 'Not changed in over 2 years',
    glyph: AppGlyph.clock,
    variant: KvTagVariant.neutral,
  ),
  HealthCategoryKind.duplicates: _HealthCategoryInfo(
    title: 'Duplicates',
    subtitle: 'Same site and username',
    glyph: AppGlyph.duplicates,
    variant: KvTagVariant.positive,
  ),
  HealthCategoryKind.unmatchable: _HealthCategoryInfo(
    title: 'Missing URL or username',
    subtitle: "Autofill can't match these",
    glyph: AppGlyph.searchOff,
    variant: KvTagVariant.positive,
  ),
};

class _HealthCategoryRow extends StatelessWidget {
  const _HealthCategoryRow({required this.category, this.onTap});

  final HealthCategory category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final info = _healthCategoryInfo[category.kind]!;
    final (background, foreground) = switch (info.variant) {
      KvTagVariant.attention => (colors.attentionTint, colors.attentionText),
      KvTagVariant.positive => (colors.positiveTint, colors.positiveText),
      _ => (colors.surfaceNested, colors.textSecondary),
    };

    return KvListRow(
      title: info.title,
      subtitle: info.subtitle,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.iconSquare),
        ),
        alignment: Alignment.center,
        child: KvIcon(glyph: info.glyph, size: 19, color: foreground),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${category.count}',
            style: AppTextStyles.panelTitleLarge.copyWith(
              fontSize: 18,
              color: colors.textPrimary,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            KvIcon(
              glyph: AppGlyph.chevronRight,
              size: 17,
              color: colors.textTertiary,
            ),
          ],
        ],
      ),
    );
  }
}
