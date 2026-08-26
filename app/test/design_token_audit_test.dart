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
