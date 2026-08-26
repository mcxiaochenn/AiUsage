import 'dart:io';

import 'design_token_audit.dart' as audit;

void main() {
  final exitCode = audit.runAudit();
  if (exitCode != 0) exit(exitCode);
}
