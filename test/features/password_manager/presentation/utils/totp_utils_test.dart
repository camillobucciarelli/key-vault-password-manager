// spec-004 T8/T23/AC4: TOTP ring counts 30→0 for a period=30 URI, ticking
// every 1s, and the code rotates exactly on the period boundary (not a
// second early or late).
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/utils/totp_utils.dart';

void main() {
  const uri =
      'otpauth://totp/Sella:CB77219?secret=JBSWY3DPEHPK3PXP&period=30&digits=6';
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  int remainingAt(int seconds) {
    final now = epoch.add(Duration(seconds: seconds));
    return TotpUtils.fromOtpAuthUri(uri, now)!.remainingSeconds;
  }

  String codeAt(int seconds) {
    final now = epoch.add(Duration(seconds: seconds));
    return TotpUtils.fromOtpAuthUri(uri, now)!.code;
  }

  test('ring counts from 30 down to 1 across one full period', () {
    expect(remainingAt(0), 30);
    expect(remainingAt(1), 29);
    expect(remainingAt(15), 15);
    expect(remainingAt(29), 1);
  });

  test('ring resets to 30 exactly at the next period boundary', () {
    expect(remainingAt(29), 1);
    expect(remainingAt(30), 30, reason: 'new period starts at t=30s');
    expect(remainingAt(59), 1);
    expect(remainingAt(60), 30, reason: 'new period starts at t=60s');
  });

  test('the 1s tick maps directly to the remaining-seconds delta', () {
    for (var s = 0; s < 29; s++) {
      expect(remainingAt(s) - remainingAt(s + 1), 1);
    }
  });

  test('the code is stable within a period and rotates on the boundary', () {
    final withinPeriod = codeAt(0);
    expect(codeAt(1), withinPeriod);
    expect(codeAt(29), withinPeriod);

    final nextPeriod = codeAt(30);
    expect(
      nextPeriod == withinPeriod,
      isFalse,
      reason:
          'two independently-generated TOTP codes 30s apart colliding is '
          'astronomically unlikely; treat equality as a rotation bug',
    );
    expect(codeAt(59), nextPeriod);
  });
}
