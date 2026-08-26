import 'package:flutter/material.dart';

class AiUsageShapeTokens {
  const AiUsageShapeTokens();

  BorderRadius get controlBorderRadius => BorderRadius.circular(_controlRadius);

  BorderRadius get containerBorderRadius =>
      BorderRadius.circular(_containerRadius);

  BorderRadius get prominentContainerBorderRadius =>
      BorderRadius.circular(_prominentRadius);

  BorderRadius get selectionBorderRadius =>
      BorderRadius.circular(_selectionRadius);

  ShapeBorder get controlShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_controlRadius),
  );

  ShapeBorder get containerShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_containerRadius),
  );

  ShapeBorder get prominentContainerShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_prominentRadius),
  );

  ShapeBorder get selectionShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_selectionRadius),
  );

  static const double _controlRadius = 12;
  static const double _containerRadius = 16;
  static const double _prominentRadius = 20;
  static const double _selectionRadius = 4;
}
