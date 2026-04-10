import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/services/password_generator_service.dart';

void main() {
  group('PasswordGeneratorService', () {
    final service = PasswordGeneratorService();

    test('generates password of requested length', () {
      final pw = service.generate(const PasswordGeneratorOptions(
        length: 20,
        includeLowercase: true,
        includeUppercase: true,
        includeDigits: true,
        includeSymbols: true,
      ));
      expect(pw.length, 20);
    });

    test('default options produce a 16-char password', () {
      final pw = service.generate(const PasswordGeneratorOptions.defaults());
      expect(pw.length, 16);
    });

    test('only includes chars from selected sets', () {
      final pw = service.generate(const PasswordGeneratorOptions(
        length: 40,
        includeLowercase: false,
        includeUppercase: false,
        includeDigits: true,
        includeSymbols: false,
      ));
      for (final char in pw.split('')) {
        expect('0123456789'.contains(char), isTrue,
            reason: 'unexpected char: $char');
      }
    });

    test('always includes at least one char from each enabled set', () {
      for (var i = 0; i < 50; i++) {
        final pw = service.generate(const PasswordGeneratorOptions(
          length: 8,
          includeLowercase: true,
          includeUppercase: true,
          includeDigits: true,
          includeSymbols: true,
        ));
        expect(pw.contains(RegExp('[a-z]')), isTrue);
        expect(pw.contains(RegExp('[A-Z]')), isTrue);
        expect(pw.contains(RegExp('[0-9]')), isTrue);
        expect(pw.contains(RegExp(r'[!@#$%^&*()\-_=+\[\]{};:,.<>?]')), isTrue);
      }
    });

    test('throws when no character sets selected', () {
      expect(
        () => service.generate(const PasswordGeneratorOptions(
          length: 8,
          includeLowercase: false,
          includeUppercase: false,
          includeDigits: false,
          includeSymbols: false,
        )),
        throwsStateError,
      );
    });

    test('throws when length shorter than enabled set count', () {
      expect(
        () => service.generate(const PasswordGeneratorOptions(
          length: 3,
          includeLowercase: true,
          includeUppercase: true,
          includeDigits: true,
          includeSymbols: true,
        )),
        throwsStateError,
      );
    });
  });
}
