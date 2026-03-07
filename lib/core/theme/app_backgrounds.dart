import 'package:flutter/material.dart';

class AppBackgrounds {
  AppBackgrounds._();

  static LinearGradient gradient(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colorScheme.primary.withValues(alpha: 0.1),
        colorScheme.secondary.withValues(alpha: 0.06),
        colorScheme.surface,
      ],
      stops: const [0.0, 0.45, 1.0],
    );
  }
}
