import 'package:flutter/material.dart';

import '../context_extensions.dart';
import '../tokens/component_size_tokens.dart';

class AiUsageEmptyState extends StatelessWidget {
  const AiUsageEmptyState({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.action,
  });

  final String message;
  final String? title;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: context.aiSpacing.emptyStateInsets,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AiUsageComponentSizeTokens.emphasizedAvatar),
            SizedBox(height: context.aiSpacing.contentGap),
          ],
          if (title != null)
            Text(title!, style: context.aiTypography.itemTitle),
          if (title != null) SizedBox(height: context.aiSpacing.tightGap),
          Text(
            message,
            style: context.aiTypography.body,
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            SizedBox(height: context.aiSpacing.sectionGap),
            action!,
          ],
        ],
      ),
    ),
  );
}
