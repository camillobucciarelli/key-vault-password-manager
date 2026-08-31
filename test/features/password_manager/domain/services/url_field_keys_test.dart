import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/services/url_field_keys.dart';

void main() {
  test('isUrlFieldKey accepts every URL key convention', () {
    for (final key in [
      'URL',
      'uri',
      'Website',
      'Web URL',
      'Login URL',
      'KPH: URL',
      'KPH: URL1',
      'KPH: URI2',
      'KP2A_URL',
      'KP2A_URL_1',
      'KP2A_URL_12',
      '$kp2aUrlKeyPrefix 3',
    ]) {
      expect(isUrlFieldKey(key), isTrue, reason: key);
    }
  });

  test('isUrlFieldKey rejects non-URL keys', () {
    for (final key in ['otp', 'domain', 'username', 'URL notes', 'url2', '']) {
      expect(isUrlFieldKey(key), isFalse, reason: key);
    }
  });
}
