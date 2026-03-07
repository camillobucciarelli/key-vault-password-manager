import 'package:otp/otp.dart';

class TotpData {
  const TotpData({required this.code, required this.remainingSeconds});

  final String code;
  final int remainingSeconds;
}

class TotpUtils {
  static TotpData? fromOtpAuthUri(String? otpUri, DateTime nowUtc) {
    if (otpUri == null || otpUri.trim().isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(otpUri.trim());
    if (uri == null || uri.scheme != 'otpauth' || uri.host != 'totp') {
      return null;
    }

    final secret = uri.queryParameters['secret'];
    if (secret == null || secret.trim().isEmpty) {
      return null;
    }
    final normalizedSecret = secret.replaceAll(' ', '');

    final digits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
    final period = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;
    if (period <= 0) {
      return null;
    }

    final algorithmRaw = (uri.queryParameters['algorithm'] ?? 'SHA1')
        .toUpperCase();
    final algorithm = switch (algorithmRaw) {
      'SHA256' => Algorithm.SHA256,
      'SHA512' => Algorithm.SHA512,
      _ => Algorithm.SHA1,
    };

    final nowMs = nowUtc.millisecondsSinceEpoch;
    final code = OTP.generateTOTPCodeString(
      normalizedSecret,
      nowMs,
      interval: period,
      length: digits,
      algorithm: algorithm,
      isGoogle: true,
    );
    final remaining = period - ((nowMs ~/ 1000) % period);

    return TotpData(code: code, remainingSeconds: remaining);
  }
}
