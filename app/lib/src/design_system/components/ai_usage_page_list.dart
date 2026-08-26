import 'package:flutter/material.dart';

import '../context_extensions.dart';
import '../tokens/layout_tokens.dart';

class AiUsagePageList extends StatelessWidget {
  const AiUsagePageList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: context.aiSpacing.pageInsets,
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AiUsageLayoutTokens.readingMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}
