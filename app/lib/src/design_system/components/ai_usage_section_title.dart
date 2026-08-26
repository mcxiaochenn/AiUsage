import 'package:flutter/material.dart';

import '../context_extensions.dart';

class AiUsageSectionTitle extends StatelessWidget {
  const AiUsageSectionTitle(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: context.aiSpacing.contentGap),
    child: Text(
      text,
      style: context.aiTypography.sectionTitle.copyWith(color: color),
    ),
  );
}
