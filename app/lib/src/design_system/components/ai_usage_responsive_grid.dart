import 'package:flutter/material.dart';

import '../tokens/layout_tokens.dart';
import '../tokens/spacing_tokens.dart';

class AiUsageResponsiveGrid extends StatelessWidget {
  const AiUsageResponsiveGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= AiUsageLayoutTokens.overviewGridBreakpoint
          ? 3
          : constraints.maxWidth >= AiUsageLayoutTokens.summaryGridBreakpoint
          ? 2
          : 1;
      final gap = const AiUsageSpacingTokens().sectionGap;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
        childAspectRatio: AiUsageLayoutTokens.responsiveGridChildAspectRatio,
        children: children,
      );
    },
  );
}
