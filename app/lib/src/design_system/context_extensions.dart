import 'package:flutter/material.dart';

import 'theme/semantic_colors.dart';
import 'tokens/spacing_tokens.dart';
import 'tokens/shape_tokens.dart';
import 'tokens/typography_tokens.dart';

extension AiUsageContextExtensions on BuildContext {
  ThemeData get aiTheme => Theme.of(this);
  ColorScheme get aiColors => aiTheme.colorScheme;
  AiUsageTypographyTokens get aiTypography =>
      AiUsageTypographyTokens(aiTheme.textTheme);
  AiUsageSemanticColors get aiSemanticColors =>
      aiTheme.extension<AiUsageSemanticColors>()!;
  AiUsageSpacingTokens get aiSpacing => const AiUsageSpacingTokens();
  AiUsageShapeTokens get aiShapes => const AiUsageShapeTokens();
}
