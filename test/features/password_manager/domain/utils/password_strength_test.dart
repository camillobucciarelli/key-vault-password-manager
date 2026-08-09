// spec-004 T4/T23/AC3: strength thresholds map to Weak/Fair/Good/Strong at
// 40/60/80 bits of entropy. Digit-only strings (pool size 10, log2(10) ≈
// 3.321928 bits/char) give exact, easy-to-reason-about entropy without
// hand-tuning boundary floats.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/utils/password_strength.dart';

void main() {
  test('empty password is Weak', () {
    final result = evaluatePasswordStrength('');
    expect(result.level, PasswordStrengthLevel.weak);
    expect(result.label, 'Weak');
  });

  test('12 digits (~39.9 bits) is Weak — just under the 40-bit line', () {
    final result = evaluatePasswordStrength('1' * 12);
    expect(result.level, PasswordStrengthLevel.weak);
    expect(result.label, 'Weak');
  });

  test('13 digits (~43.2 bits) is Fair — just over the 40-bit line', () {
    final result = evaluatePasswordStrength('1' * 13);
    expect(result.level, PasswordStrengthLevel.fair);
    expect(result.label, 'Fair');
  });

  test('19 digits (~63.1 bits) is Good — between the 60/80-bit lines', () {
    final result = evaluatePasswordStrength('1' * 19);
    expect(result.level, PasswordStrengthLevel.good);
    expect(result.label, 'Good');
  });

  test('25 digits (~83.0 bits) is Strong — over the 80-bit line', () {
    final result = evaluatePasswordStrength('1' * 25);
    expect(result.level, PasswordStrengthLevel.strong);
    expect(result.label, 'Strong');
  });
}
