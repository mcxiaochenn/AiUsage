import 'dart:io';

import 'package:flutter/services.dart';

class SystemSettingsService {
  const SystemSettingsService();

  static const _channel = MethodChannel('dev.chendusk.aiusage/settings');

  Future<void> openApplicationDetails() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openApplicationDetails');
  }

  Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openBatterySettings');
  }
}
