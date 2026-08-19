import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/master_password_session.dart';

void main() {
  group('MasterPasswordSession', () {
    test('starts empty (absent secret is null, not "")', () {
      final session = MasterPasswordSession();
      expect(session.value, isNull);
      expect(session.hasValue, isFalse);
    });

    test('set then value returns the secret', () {
      final session = MasterPasswordSession()..set('correct horse');
      expect(session.value, 'correct horse');
      expect(session.hasValue, isTrue);
    });

    test('clear drops the secret back to null', () {
      final session = MasterPasswordSession()..set('secret');
      session.clear();
      expect(session.value, isNull);
      expect(session.hasValue, isFalse);
    });

    test('empty string is a real value, distinct from absent', () {
      final session = MasterPasswordSession()..set('');
      expect(session.value, '');
      expect(session.hasValue, isTrue);
    });

    test('toString never leaks the secret (AC-8)', () {
      final session = MasterPasswordSession()..set('super-secret-value');
      expect(session.toString(), isNot(contains('super-secret-value')));
      expect(session.toString(), contains('hasValue: true'));
    });
  });
}
