import 'package:flutter/material.dart';

class AiUsageDataVisualizationTokens {
  const AiUsageDataVisualizationTokens();

  static const double chartCellExtent = 15;
  static const double chartCellGap = 3;
  static const double chartColumnExtent = 18;
  static const double monthLabelExtent = 20;
  static const double chartLegendExtent = 12;
  static const double chartDetailExtent = 42;
  static const double chartCellRadius = 3;
  static const double chartSelectionRadius = 4;
  static const double chartDetailRadius = 10;
  static const double chartSelectionStroke = 2;
  static const double chartHoverStroke = 1;
  static const Color transparent = Colors.transparent;

  static Color selectionBorderColor(
    ColorScheme scheme, {
    required bool selected,
  }) {
    if (selected) return scheme.primary;
    return Color.lerp(scheme.primary, scheme.surface, .35) ?? scheme.primary;
  }

  static BoxDecoration selectionDecoration(
    ColorScheme scheme, {
    required bool selected,
  }) => BoxDecoration(
    border: Border.all(
      color: selectionBorderColor(scheme, selected: selected),
      width: selected ? chartSelectionStroke : chartHoverStroke,
    ),
    borderRadius: BorderRadius.circular(chartSelectionRadius),
  );

  static BoxDecoration detailDecoration(ColorScheme scheme) => BoxDecoration(
    color: scheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(chartDetailRadius),
  );

  static BoxDecoration cellDecoration(ColorScheme scheme, int? level) =>
      BoxDecoration(
        color: level == null ? transparent : levelColor(scheme, level),
        borderRadius: BorderRadius.circular(chartCellRadius),
      );

  static BoxDecoration legendDecoration(ColorScheme scheme, int level) =>
      BoxDecoration(
        color: levelColor(scheme, level),
        borderRadius: BorderRadius.circular(chartCellRadius),
      );

  static Color levelColor(ColorScheme scheme, int level) {
    final base = scheme.primary;
    if (level <= 0) return scheme.surfaceContainerHighest;
    return Color.lerp(scheme.surfaceContainerHighest, base, level / 4) ?? base;
  }
}
