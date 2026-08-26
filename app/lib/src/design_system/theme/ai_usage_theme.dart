import 'package:flutter/material.dart';

import '../tokens/shape_tokens.dart';
import 'semantic_colors.dart';

class AiUsageTheme {
  const AiUsageTheme._();

  static ThemeData light(ColorScheme? dynamicScheme) =>
      _build(dynamicScheme ?? ColorScheme.fromSeed(seedColor: Colors.indigo));

  static ThemeData dark(ColorScheme? dynamicScheme) => _build(
    dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
  );

  static ThemeData _build(ColorScheme scheme) {
    final warningScheme = ColorScheme.fromSeed(
      seedColor: Colors.orange,
      brightness: scheme.brightness,
    );
    const shapes = AiUsageShapeTokens();
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(shape: shapes.containerShape),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: shapes.controlBorderRadius),
      ),
      extensions: [
        AiUsageSemanticColors(
          warning: warningScheme.primary,
          onWarning: warningScheme.onPrimary,
          warningContainer: warningScheme.primaryContainer,
          onWarningContainer: warningScheme.onPrimaryContainer,
        ),
      ],
    );
  }
}
