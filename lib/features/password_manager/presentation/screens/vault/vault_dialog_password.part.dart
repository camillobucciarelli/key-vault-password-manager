part of '../vault_screen.dart';

enum _PasswordStrengthLevel { weak, fair, good, strong }

class _PasswordStrengthAssessment {
  const _PasswordStrengthAssessment({
    required this.level,
    required this.score,
    required this.label,
  });

  final _PasswordStrengthLevel level;
  final double score;
  final String label;
}

class _PasswordGeneratorOptions {
  const _PasswordGeneratorOptions({
    required this.length,
    required this.includeLowercase,
    required this.includeUppercase,
    required this.includeDigits,
    required this.includeSymbols,
  });

  const _PasswordGeneratorOptions.defaults()
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
    if (includeLowercase) {
      count++;
    }
    if (includeUppercase) {
      count++;
    }
    if (includeDigits) {
      count++;
    }
    if (includeSymbols) {
      count++;
    }
    return count;
  }
}

Future<String?> _showPasswordGeneratorDialog(BuildContext context) async {
  var options = const _PasswordGeneratorOptions.defaults();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          final hasEnabledCharset = options.enabledSetsCount > 0;
          final hasValidLength = options.length >= options.enabledSetsCount;
          final canGenerate = hasEnabledCharset && hasValidLength;
          final textTheme = Theme.of(dialogContext).textTheme;

          return AlertDialog(
            title: const Text('Generate secure password'),
            insetPadding: _dialogInsetPadding(dialogContext),
            contentPadding: _dialogContentPadding(dialogContext),
            actionsOverflowDirection: VerticalDirection.down,
            actionsOverflowButtonSpacing: 8,
            content: SizedBox(
              width: _dialogContentWidth(dialogContext, 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Length: ${options.length}'),
                    Slider(
                      value: options.length.toDouble(),
                      min: 8,
                      max: 64,
                      divisions: 56,
                      label: options.length.toString(),
                      onChanged: (value) {
                        setState(() {
                          options = _PasswordGeneratorOptions(
                            length: value.round(),
                            includeLowercase: options.includeLowercase,
                            includeUppercase: options.includeUppercase,
                            includeDigits: options.includeDigits,
                            includeSymbols: options.includeSymbols,
                          );
                        });
                      },
                    ),
                    CheckboxListTile(
                      value: options.includeLowercase,
                      onChanged: (value) {
                        setState(() {
                          options = _PasswordGeneratorOptions(
                            length: options.length,
                            includeLowercase: value ?? false,
                            includeUppercase: options.includeUppercase,
                            includeDigits: options.includeDigits,
                            includeSymbols: options.includeSymbols,
                          );
                        });
                      },
                      title: const Text('Lowercase letters (a-z)'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: options.includeUppercase,
                      onChanged: (value) {
                        setState(() {
                          options = _PasswordGeneratorOptions(
                            length: options.length,
                            includeLowercase: options.includeLowercase,
                            includeUppercase: value ?? false,
                            includeDigits: options.includeDigits,
                            includeSymbols: options.includeSymbols,
                          );
                        });
                      },
                      title: const Text('Uppercase letters (A-Z)'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: options.includeDigits,
                      onChanged: (value) {
                        setState(() {
                          options = _PasswordGeneratorOptions(
                            length: options.length,
                            includeLowercase: options.includeLowercase,
                            includeUppercase: options.includeUppercase,
                            includeDigits: value ?? false,
                            includeSymbols: options.includeSymbols,
                          );
                        });
                      },
                      title: const Text('Numbers (0-9)'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: options.includeSymbols,
                      onChanged: (value) {
                        setState(() {
                          options = _PasswordGeneratorOptions(
                            length: options.length,
                            includeLowercase: options.includeLowercase,
                            includeUppercase: options.includeUppercase,
                            includeDigits: options.includeDigits,
                            includeSymbols: value ?? false,
                          );
                        });
                      },
                      title: const Text('Special characters (!@#...)'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (!hasEnabledCharset)
                      Text(
                        'Select at least one character set.',
                        style: textTheme.bodySmall?.copyWith(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    if (hasEnabledCharset && !hasValidLength)
                      Text(
                        'Length must be at least ${options.enabledSetsCount} to include every selected set.',
                        style: textTheme.bodySmall?.copyWith(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: _adaptiveDialogActions(dialogContext, [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canGenerate
                    ? () {
                        final generatedPassword = _generateSecurePassword(
                          options,
                        );
                        Navigator.of(dialogContext).pop(generatedPassword);
                      }
                    : null,
                child: const Text('Generate'),
              ),
            ]),
          );
        },
      );
    },
  );
}

String _generateSecurePassword(_PasswordGeneratorOptions options) {
  const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const lowercase = 'abcdefghijklmnopqrstuvwxyz';
  const digits = '0123456789';
  const symbols = r'!@#$%^&*()-_=+[]{};:,.<>?';
  final random = math.Random.secure();
  final enabledSets = <String>[];
  if (options.includeLowercase) {
    enabledSets.add(lowercase);
  }
  if (options.includeUppercase) {
    enabledSets.add(uppercase);
  }
  if (options.includeDigits) {
    enabledSets.add(digits);
  }
  if (options.includeSymbols) {
    enabledSets.add(symbols);
  }

  if (enabledSets.isEmpty) {
    throw StateError('At least one character set is required.');
  }
  if (options.length < enabledSets.length) {
    throw StateError('Length is too short for selected character sets.');
  }

  final chars = <String>[];
  for (final set in enabledSets) {
    chars.add(_pickSecureChar(set, random));
  }

  final combined = enabledSets.join();
  for (var i = chars.length; i < options.length; i++) {
    chars.add(_pickSecureChar(combined, random));
  }

  for (var i = chars.length - 1; i > 0; i--) {
    final j = _nextSecureInt(random, i + 1);
    final temp = chars[i];
    chars[i] = chars[j];
    chars[j] = temp;
  }

  return chars.join();
}

String _pickSecureChar(String source, math.Random random) {
  final index = _nextSecureInt(random, source.length);
  return source[index];
}

int _nextSecureInt(math.Random random, int maxExclusive) {
  if (maxExclusive <= 0) {
    throw ArgumentError.value(maxExclusive, 'maxExclusive');
  }

  final limit = 256 - (256 % maxExclusive);
  while (true) {
    final value = random.nextInt(256);
    if (value < limit) {
      return value % maxExclusive;
    }
  }
}

_PasswordStrengthAssessment _evaluatePasswordStrength(String value) {
  if (value.isEmpty) {
    return const _PasswordStrengthAssessment(
      level: _PasswordStrengthLevel.weak,
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
    return const _PasswordStrengthAssessment(
      level: _PasswordStrengthLevel.weak,
      score: 0.1,
      label: 'Weak',
    );
  }

  final entropyBits = value.length * (math.log(poolSize) / math.ln2);
  final score = (entropyBits / 100).clamp(0.0, 1.0).toDouble();

  if (entropyBits < 40) {
    return const _PasswordStrengthAssessment(
      level: _PasswordStrengthLevel.weak,
      score: 0.25,
      label: 'Weak',
    );
  }
  if (entropyBits < 60) {
    return _PasswordStrengthAssessment(
      level: _PasswordStrengthLevel.fair,
      score: score,
      label: 'Fair',
    );
  }
  if (entropyBits < 80) {
    return _PasswordStrengthAssessment(
      level: _PasswordStrengthLevel.good,
      score: score,
      label: 'Good',
    );
  }
  return _PasswordStrengthAssessment(
    level: _PasswordStrengthLevel.strong,
    score: score,
    label: 'Strong',
  );
}
