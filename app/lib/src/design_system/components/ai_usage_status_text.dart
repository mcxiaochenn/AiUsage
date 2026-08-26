import 'package:flutter/material.dart';

import '../context_extensions.dart';

enum AiUsageStatusTone { neutral, warning, error }

class AiUsageStatusText extends StatelessWidget {
  const AiUsageStatusText({
    super.key,
    required this.text,
    this.tone = AiUsageStatusTone.neutral,
    this.emphasized = false,
  });

  final String text;
  final AiUsageStatusTone tone;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AiUsageStatusTone.neutral => context.aiColors.onSurfaceVariant,
      AiUsageStatusTone.warning => context.aiSemanticColors.warning,
      AiUsageStatusTone.error => context.aiColors.error,
    };
    final base = emphasized
        ? context.aiTypography.emphasizedBody
        : context.aiTypography.supporting;
    return Text(text, style: base.copyWith(color: color));
  }
}
