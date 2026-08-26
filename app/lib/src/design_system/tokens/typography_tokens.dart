import 'package:flutter/material.dart';

/// AiUsage 的语义 Typography 角色。
///
/// 角色只映射 Material 3 的 TextTheme，不在业务层声明字号。
class AiUsageTypographyTokens {
  const AiUsageTypographyTokens(this._textTheme);

  final TextTheme _textTheme;

  TextStyle get pageTitle => _textTheme.headlineSmall!;
  TextStyle get prominentTitle => _textTheme.headlineMedium!;
  TextStyle get sectionTitle =>
      _textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600);
  TextStyle get cardTitle => _textTheme.titleMedium!;
  TextStyle get itemTitle => _textTheme.titleLarge!;
  TextStyle get primaryMetric => _textTheme.headlineSmall!;
  TextStyle get secondaryMetric => _textTheme.titleLarge!;
  TextStyle get body => _textTheme.bodyMedium!;
  TextStyle get supporting => _textTheme.bodySmall!;
  TextStyle get caption => _textTheme.labelSmall!;
  TextStyle get emphasizedBody =>
      _textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600);
  TextStyle get diagnostic =>
      _textTheme.bodySmall!.copyWith(fontFamily: 'monospace');
}
