import 'dart:io';

class DesignTokenViolation {
  const DesignTokenViolation({
    required this.path,
    required this.line,
    required this.rule,
    required this.suggestion,
  });

  final String path;
  final int line;
  final String rule;
  final String suggestion;

  @override
  String toString() => '$path:$line [$rule] $suggestion';
}

const _controlledExceptionRules = <String>{
  'spacing.literal',
  'shape.literal',
  'visual-number.literal',
  'responsive.literal',
  'visual-constant.literal',
};

class _ControlledException {
  _ControlledException({
    required this.directiveLine,
    required this.targetLine,
    required this.rule,
    required this.reason,
  });

  final int directiveLine;
  final int targetLine;
  final String rule;
  final String reason;
  bool used = false;
}

class _ControlledExceptionSet {
  _ControlledExceptionSet(this.byTargetLine, this.violations);

  final Map<int, Map<String, _ControlledException>> byTargetLine;
  final List<DesignTokenViolation> violations;

  Iterable<_ControlledException> get all =>
      byTargetLine.values.expand((rules) => rules.values);
}

_ControlledExceptionSet _parseControlledExceptions(
  String source,
  String relativePath,
) {
  final byTargetLine = <int, Map<String, _ControlledException>>{};
  final violations = <DesignTokenViolation>[];
  final lines = source.split('\n');
  final directivePattern = RegExp(
    r'^\s*//\s*design-token-audit:\s*allow\s+([a-z][a-z0-9.-]*)\s+--\s+(\S.*)\s*$',
  );
  final directivePrefix = RegExp(r'^\s*//\s*design-token-audit:');

  for (var index = 0; index < lines.length; index++) {
    final sourceLine = lines[index];
    if (!directivePrefix.hasMatch(sourceLine)) continue;

    final directiveLine = index + 1;
    final match = directivePattern.firstMatch(sourceLine);
    if (match == null) {
      violations.add(
        DesignTokenViolation(
          path: relativePath,
          line: directiveLine,
          rule: 'exception.invalid',
          suggestion:
              '使用“// design-token-audit: allow <rule> -- <局部原因>”，并紧邻违规代码上一行。',
        ),
      );
      continue;
    }

    final rule = match.group(1)!;
    if (!_controlledExceptionRules.contains(rule)) {
      violations.add(
        DesignTokenViolation(
          path: relativePath,
          line: directiveLine,
          rule: 'exception.disallowed',
          suggestion: 'Typography 和颜色规则不允许例外；请使用现有语义 Token 或先扩展 Design System。',
        ),
      );
      continue;
    }

    final targetLine = directiveLine + 1;
    if (targetLine > lines.length || lines[targetLine - 1].trim().isEmpty) {
      violations.add(
        DesignTokenViolation(
          path: relativePath,
          line: directiveLine,
          rule: 'exception.invalid',
          suggestion: '受控例外必须紧邻需要豁免的代码上一行，中间不能有空行。',
        ),
      );
      continue;
    }

    final exception = _ControlledException(
      directiveLine: directiveLine,
      targetLine: targetLine,
      rule: rule,
      reason: match.group(2)!.trim(),
    );
    final rules = byTargetLine.putIfAbsent(targetLine, () => {});
    if (rules.containsKey(rule)) {
      violations.add(
        DesignTokenViolation(
          path: relativePath,
          line: directiveLine,
          rule: 'exception.invalid',
          suggestion: '同一代码行和规则只能声明一个受控例外。',
        ),
      );
      continue;
    }
    rules[rule] = exception;
  }

  return _ControlledExceptionSet(byTargetLine, violations);
}

/// Removes comments and string contents while retaining line breaks and
/// character positions. This keeps the audit focused on Dart syntax instead
/// of examples embedded in comments or user-facing strings.
String stripCommentsAndStrings(String source) {
  final output = StringBuffer();
  var index = 0;
  var blockComment = false;
  var lineComment = false;
  String? quote;
  var raw = false;

  while (index < source.length) {
    final current = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';

    if (blockComment) {
      if (current == '*' && next == '/') {
        output.write('  ');
        index += 2;
        blockComment = false;
      } else {
        output.write(current == '\n' ? '\n' : ' ');
        index++;
      }
      continue;
    }
    if (lineComment) {
      if (current == '\n') {
        output.write('\n');
        lineComment = false;
      } else {
        output.write(' ');
      }
      index++;
      continue;
    }
    if (quote != null) {
      if (!raw && current == '\\') {
        output.write('  ');
        index += index + 1 < source.length ? 2 : 1;
        continue;
      }
      if (current == quote) {
        final isTriple =
            index + 2 < source.length &&
            source[index + 1] == quote &&
            source[index + 2] == quote;
        if (isTriple) {
          output.write('   ');
          index += 3;
        } else {
          output.write(' ');
          index++;
        }
        quote = null;
        raw = false;
      } else {
        output.write(current == '\n' ? '\n' : ' ');
        index++;
      }
      continue;
    }

    if (current == '/' && next == '/') {
      output.write('  ');
      index += 2;
      lineComment = true;
      continue;
    }
    if (current == '/' && next == '*') {
      output.write('  ');
      index += 2;
      blockComment = true;
      continue;
    }
    if (current == 'r' && next == "'") {
      output.write('  ');
      index += 2;
      quote = "'";
      raw = true;
      continue;
    }
    if (current == 'r' && next == '"') {
      output.write('  ');
      index += 2;
      quote = '"';
      raw = true;
      continue;
    }
    if (current == "'" || current == '"') {
      output.write(' ');
      index++;
      quote = current;
      raw = false;
      continue;
    }
    output.write(current);
    index++;
  }
  return output.toString();
}

List<DesignTokenViolation> auditSource(String source, String relativePath) {
  final sanitized = stripCommentsAndStrings(source);
  final violations = <DesignTokenViolation>[];
  final allowed =
      relativePath.startsWith('lib/src/design_system/tokens/') ||
      relativePath.startsWith('lib/src/design_system/theme/') ||
      relativePath == 'lib/src/design_system/context_extensions.dart';
  if (allowed) return violations;

  final exceptions = _parseControlledExceptions(source, relativePath);
  violations.addAll(exceptions.violations);

  void find(String rule, String suggestion, RegExp pattern) {
    for (final match in pattern.allMatches(sanitized)) {
      final line =
          '\n'.allMatches(sanitized.substring(0, match.start)).length + 1;
      final exception = exceptions.byTargetLine[line]?[rule];
      if (exception != null) {
        exception.used = true;
        continue;
      }
      violations.add(
        DesignTokenViolation(
          path: relativePath,
          line: line,
          rule: rule,
          suggestion: suggestion,
        ),
      );
    }
  }

  find(
    'typography.literal',
    '使用 context.aiTypography 的语义 Typography Token。',
    RegExp(r'\bfontSize\s*:|\bfontFamily\s*:|\bFontWeight\.|\bTextStyle\s*\('),
  );
  find(
    'typography.material-direct',
    '不要直接访问 textTheme，改用 context.aiTypography。',
    RegExp(r'\.textTheme\b'),
  );
  find(
    'color.literal',
    '使用 context.aiColors、context.aiSemanticColors 或已登记 Token。',
    RegExp(
      r'\bColors\.|\bColor\s*\(|\bColor\.lerp\s*\(|\bwithOpacity\s*\(|\bwithAlpha\s*\(|\bwithValues\s*\(',
    ),
  );
  find(
    'spacing.literal',
    '优先使用 context.aiSpacing；确属一次性局部结构值时可声明带理由的受控例外。',
    RegExp(
      r'\bEdgeInsets(?:Directional)?\.(?:all|only|symmetric|fromLTRB|fromSTEB)\s*\([^)]*\d',
    ),
  );
  find(
    'shape.literal',
    '优先使用 context.aiShapes；确属一次性局部结构值时可声明带理由的受控例外。',
    RegExp(
      r'\b(?:BorderRadius|Radius)\.circular\s*\([^)]*\d|\bBorder\.all\s*\(',
    ),
  );
  find(
    'visual-number.literal',
    '优先使用 Layout/Component/Data Visualization Token；局部实现值可声明受控例外。',
    RegExp(
      r'\b(?:width|height|minHeight|maxHeight|maxWidth|minWidth|radius|strokeWidth|elevation)\s*:\s*(?:const\s+)?(?:\d+(?:\.\d+)?|\.\d+)',
    ),
  );
  find(
    'responsive.literal',
    '优先使用 AiUsageLayoutTokens；特殊局部布局阈值可声明带理由的受控例外。',
    RegExp(
      r'(?:MediaQuery\.sizeOf|constraints\.maxWidth|constraints\.maxHeight)[^\n]*(?:<|>)=?\s*\d+',
    ),
  );
  find(
    'visual-constant.literal',
    '可复用视觉常量应进入 Token；一次性局部常量可声明带理由的受控例外。',
    RegExp(
      r'\b(?:const|final)\s+(?:double|int)\s+\w*(?:size|width|height|extent|radius|padding|gap|spacing|inset|stroke|breakpoint)\w*\s*=\s*\d',
      caseSensitive: false,
    ),
  );

  for (final exception in exceptions.all.where((item) => !item.used)) {
    violations.add(
      DesignTokenViolation(
        path: relativePath,
        line: exception.directiveLine,
        rule: 'exception.unused',
        suggestion:
            '受控例外未匹配 ${exception.rule}；请删除过期注释或将其紧邻实际违规行。原因：${exception.reason}',
      ),
    );
  }
  return violations;
}

List<DesignTokenViolation> auditDirectory(Directory root) {
  final violations = <DesignTokenViolation>[];
  final lib = Directory('${root.path}${Platform.pathSeparator}lib');
  if (!lib.existsSync()) return violations;
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalized = entity.path.replaceAll('\\', '/');
    final relative = normalized.substring(normalized.indexOf('/lib/') + 1);
    if (relative.startsWith('lib/l10n/') ||
        relative.startsWith('lib/src/rust/')) {
      continue;
    }
    violations.addAll(auditSource(entity.readAsStringSync(), relative));
  }
  return violations;
}

int runAudit({Directory? root, bool printResult = true}) {
  final violations = auditDirectory(root ?? Directory.current);
  if (printResult) {
    for (final violation in violations) {
      stdout.writeln(violation);
    }
    stdout.writeln('Design Token audit: ${violations.length} violation(s).');
  }
  return violations.isEmpty ? 0 : 1;
}

void main() => exit(runAudit());
