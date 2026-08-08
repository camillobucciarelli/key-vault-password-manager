import 'dart:math' as math;

/// AC3 thresholds (spec-004 FR-1 / PIXEL_SPEC): Weak < 40 bits, Fair < 60,
/// Good < 80, Strong >= 80. Extracted from the old
/// `_evaluatePasswordStrength` (previously private to
/// `vault_dialog_password.part.dart`) so both the entry-detail strength
/// strip and the generator sheet share one implementation — the labels are
/// a copy-preservation contract (spec-004 non-negotiables), not just an
/// internal detail.
enum PasswordStrengthLevel { weak, fair, good, strong }

class PasswordStrengthAssessment {
  const PasswordStrengthAssessment({
    required this.level,
    required this.score,
    required this.label,
  });

  final PasswordStrengthLevel level;
  final double score;
  final String label;
}

PasswordStrengthAssessment evaluatePasswordStrength(String value) {
  if (value.isEmpty) {
    return const PasswordStrengthAssessment(
      level: PasswordStrengthLevel.weak,
      score: 0,
      label: 'Weak',
    );
  }

  final hasLower = value.contains(RegExp('[a-z]'));
  final hasUpper = value.contains(RegExp('[A-Z]'));
  final hasDigit = value.contains(RegExp('[0-9]'));
  final hasSymbol = value.contains(RegExp(r'[^a-zA-Z0-9]'));
  var poolSize = 0;
  if (hasLower) {
    poolSize += 26;
  }
  if (hasUpper) {
    poolSize += 26;
  }
  if (hasDigit) {
    poolSize += 10;
  }
  if (hasSymbol) {
    poolSize += 28;
  }

  if (poolSize <= 0) {
    return const PasswordStrengthAssessment(
      level: PasswordStrengthLevel.weak,
      score: 0.1,
      label: 'Weak',
    );
  }

  final entropyBits = value.length * (math.log(poolSize) / math.ln2);
  final score = (entropyBits / 100).clamp(0.0, 1.0).toDouble();

  if (entropyBits < 40) {
    return const PasswordStrengthAssessment(
      level: PasswordStrengthLevel.weak,
      score: 0.25,
      label: 'Weak',
    );
  }
  if (entropyBits < 60) {
    return PasswordStrengthAssessment(
      level: PasswordStrengthLevel.fair,
      score: score,
      label: 'Fair',
    );
  }
  if (entropyBits < 80) {
    return PasswordStrengthAssessment(
      level: PasswordStrengthLevel.good,
      score: score,
      label: 'Good',
    );
  }
  return PasswordStrengthAssessment(
    level: PasswordStrengthLevel.strong,
    score: score,
    label: 'Strong',
  );
}
