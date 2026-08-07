import 'dart:math' as math;

class PasswordGeneratorOptions {
  const PasswordGeneratorOptions({
    required this.length,
    required this.includeLowercase,
    required this.includeUppercase,
    required this.includeDigits,
    required this.includeSymbols,
  });

  const PasswordGeneratorOptions.defaults()
      : length = 16,
        includeLowercase = true,
        includeUppercase = true,
        includeDigits = true,
        includeSymbols = true;

  final int length;
  final bool includeLowercase;
  final bool includeUppercase;
  final bool includeDigits;
  final bool includeSymbols;

  int get enabledSetsCount {
    var count = 0;
    if (includeLowercase) count++;
    if (includeUppercase) count++;
    if (includeDigits) count++;
    if (includeSymbols) count++;
    return count;
  }
}

class PasswordGeneratorService {
  PasswordGeneratorService({math.Random? random})
    : _random = random ?? math.Random.secure();

  static const _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const _digits = '0123456789';
  static const _symbols = r'!@#$%^&*()-_=+[]{};:,.<>?';

  final math.Random _random;

  String generate(PasswordGeneratorOptions options) {
    final enabledSets = <String>[];
    if (options.includeLowercase) enabledSets.add(_lowercase);
    if (options.includeUppercase) enabledSets.add(_uppercase);
    if (options.includeDigits) enabledSets.add(_digits);
    if (options.includeSymbols) enabledSets.add(_symbols);

    if (enabledSets.isEmpty) {
      throw StateError('At least one character set is required.');
    }
    if (options.length < enabledSets.length) {
      throw StateError('Length is too short for selected character sets.');
    }

    final random = _random;
    final chars = <String>[];

    for (final set in enabledSets) {
      chars.add(_pickChar(set, random));
    }

    final combined = enabledSets.join();
    for (var i = chars.length; i < options.length; i++) {
      chars.add(_pickChar(combined, random));
    }

    for (var i = chars.length - 1; i > 0; i--) {
      final j = _secureInt(random, i + 1);
      final temp = chars[i];
      chars[i] = chars[j];
      chars[j] = temp;
    }

    return chars.join();
  }

  String _pickChar(String source, math.Random random) {
    return source[_secureInt(random, source.length)];
  }

  int _secureInt(math.Random random, int maxExclusive) {
    if (maxExclusive <= 0) {
      throw ArgumentError.value(maxExclusive, 'maxExclusive');
    }
    final limit = 256 - (256 % maxExclusive);
    while (true) {
      final value = random.nextInt(256);
      if (value < limit) return value % maxExclusive;
    }
  }
}
