import 'package:flutter/material.dart';

/// 页面和组件共享的语义间距。
class AiUsageSpacingTokens {
  const AiUsageSpacingTokens();

  static const double _xs = 4;
  static const double _sm = 8;
  static const double _md = 12;
  static const double _lg = 16;
  static const double _xxl = 24;
  static const double _xxxl = 32;

  EdgeInsets get pageInsets => const EdgeInsets.all(_lg);
  EdgeInsets get cardInsets => const EdgeInsets.all(_lg);
  EdgeInsets get featuredCardInsets => const EdgeInsets.all(_xxl);
  EdgeInsets get stateInsets => const EdgeInsets.all(_lg);
  EdgeInsets get emptyStateInsets => const EdgeInsets.all(_xxl);

  double get tightGap => _xs;
  double get contentGap => _sm;
  double get controlGap => _md;
  double get sectionGap => _lg;
  double get majorSectionGap => _xxl;
  double get inlineGap => _sm;
  double get inlineWideGap => _md;
  double get actionGap => _md;
  double get formFieldGap => _lg;
  double get wrapGap => _sm;

  double get pageSectionGap => _xxxl;
}
