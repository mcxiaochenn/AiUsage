import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/rust/frb_generated.dart';
import 'src/services/desktop_tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final controller = AppController();
  await controller.bootstrap();
  await DesktopTrayService.instance.install(controller);
  runApp(CodexUsageMonitorApp(controller: controller));
}
