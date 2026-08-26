import 'package:flutter/material.dart';

class AiUsageBrandTokens {
  const AiUsageBrandTokens();

  static const Color openAiSurface = Colors.white;
  static const Color deepSeekSurface = Colors.white;
  static const Color mimoOrange = Color(0xFFFF6900);
  static const double logoInsetFactor = .32;

  static EdgeInsets logoPadding(double radius) =>
      EdgeInsets.all(radius * logoInsetFactor);
}
