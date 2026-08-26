import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_usage/src/design_system/design_system.dart';

void main() {
  test('typography roles map to Material text theme roles', () {
    final theme = ThemeData(useMaterial3: true);
    final typography = AiUsageTypographyTokens(theme.textTheme);
    expect(typography.pageTitle, theme.textTheme.headlineSmall);
    expect(typography.cardTitle, theme.textTheme.titleMedium);
    expect(typography.body, theme.textTheme.bodyMedium);
    expect(typography.caption, theme.textTheme.labelSmall);
    expect(typography.diagnostic.fontFamily, 'monospace');
  });

  test('light, dark and dynamic themes expose semantic colors', () {
    final light = AiUsageTheme.light(null);
    final dark = AiUsageTheme.dark(null);
    final dynamicScheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final dynamic = AiUsageTheme.light(dynamicScheme);
    expect(light.useMaterial3, isTrue);
    expect(dark.brightness, Brightness.dark);
    expect(dynamic.colorScheme.primary, dynamicScheme.primary);
    expect(light.extension<AiUsageSemanticColors>(), isNotNull);
    expect(dark.extension<AiUsageSemanticColors>(), isNotNull);
  });

  testWidgets(
    'shared components remain usable at compact width and large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AiUsageTheme.light(null),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const AiUsageSectionTitle('Section'),
                  const AiUsageEmptyState(
                    title: 'No data',
                    message:
                        'A long explanatory message that should wrap safely.',
                    icon: Icons.info_outline,
                  ),
                  AiUsageResponsiveGrid(
                    children: [
                      for (var index = 0; index < 3; index++)
                        Card(child: Text('Metric $index')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
