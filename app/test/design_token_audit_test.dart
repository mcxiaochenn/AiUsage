import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/design_token_audit.dart';

void main() {
  test('detects forbidden visual declarations', () {
    const source = '''
      // TextStyle(fontSize: 18) in a comment is not code.
      final label = 'Colors.orange and EdgeInsets.all(16)';
      Widget build(context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('x', style: const TextStyle(fontSize: 16)),
      );
    ''';
    final violations = auditSource(source, 'lib/src/example.dart');
    expect(violations.map((item) => item.rule), contains('spacing.literal'));
    expect(violations.map((item) => item.rule), contains('typography.literal'));
    expect(
      violations.map((item) => item.rule),
      isNot(contains('color.literal')),
    );
  });

  test('allows token and theme definitions', () {
    const source = 'const double cardGap = 16;';
    expect(
      auditSource(source, 'lib/src/design_system/tokens/sample.dart'),
      isEmpty,
    );
    expect(
      auditSource(source, 'lib/src/design_system/theme/sample.dart'),
      isEmpty,
    );
  });

  final controlledExceptionCases = <String, String>{
    'spacing.literal': 'padding: const EdgeInsets.only(top: 3),',
    'shape.literal':
        'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),',
    'visual-number.literal': 'width: 13,',
    'responsive.literal': 'final compact = constraints.maxWidth < 511;',
    'visual-constant.literal': 'const double localGap = 7;',
  };
  for (final entry in controlledExceptionCases.entries) {
    test('allows a documented ${entry.key} exception', () {
      final source =
          '''
        // design-token-audit: allow ${entry.key} -- One-off local geometry.
        ${entry.value}
      ''';
      expect(auditSource(source, 'lib/src/example.dart'), isEmpty);
    });
  }

  test('does not allow typography or color exceptions', () {
    const source = '''
      // design-token-audit: allow typography.literal -- One-off heading.
      style: const TextStyle(fontSize: 17),
      // design-token-audit: allow color.literal -- One-off tint.
      color: Colors.orange.withValues(alpha: 0.5),
    ''';
    final violations = auditSource(source, 'lib/src/example.dart');
    expect(
      violations.map((item) => item.rule),
      containsAll(<String>[
        'exception.disallowed',
        'typography.literal',
        'color.literal',
      ]),
    );
  });

  test('rejects malformed and unused exceptions', () {
    const malformed = '''
      // design-token-audit: allow spacing.literal
      padding: const EdgeInsets.only(top: 3),
    ''';
    expect(
      auditSource(malformed, 'lib/src/example.dart').map((item) => item.rule),
      contains('exception.invalid'),
    );

    const unused = '''
      // design-token-audit: allow spacing.literal -- No spacing literal follows.
      child: const Placeholder(),
    ''';
    expect(
      auditSource(unused, 'lib/src/example.dart').map((item) => item.rule),
      contains('exception.unused'),
    );
  });

  test('ignores exception markers inside strings', () {
    const source = '''
      final help = 'design-token-audit: allow spacing.literal -- example';
    ''';
    expect(auditSource(source, 'lib/src/example.dart'), isEmpty);
  });

  test('still audits shared design system components', () {
    const source = 'padding: const EdgeInsets.all(16);';
    expect(
      auditSource(
        source,
        'lib/src/design_system/components/example.dart',
      ).map((item) => item.rule),
      contains('spacing.literal'),
    );
  });

  test('does not flag business durations or counters', () {
    const source = '''
      final timeout = Duration(seconds: 2);
      final retries = 3;
      final ratio = tokens / peak;
    ''';
    expect(auditSource(source, 'lib/src/service.dart'), isEmpty);
  });

  test('finds new production UI files recursively', () {
    final root = Directory.systemTemp.createTempSync('aiusage-token-audit-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/lib/src/new_feature').createSync(recursive: true);
    File(
      '${root.path}/lib/src/new_feature/page.dart',
    ).writeAsStringSync('const double widgetWidth = 10;');
    expect(auditDirectory(root), isNotEmpty);
  });
}
