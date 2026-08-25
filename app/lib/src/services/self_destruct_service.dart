import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

class SelfDestructService {
  const SelfDestructService();

  static const crashMessage = '来自app作者辰渊尘的消息，不是还真有人会点这个按钮并检查崩溃日志啊（恼）';
  static const _lockFileName = 'aiusage-self-destruct.lock';
  static const _channel = MethodChannel('dev.chendusk.aiusage/self_destruct');

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static Future<bool> isArmed() async {
    if (!supported) return false;
    final support = await getApplicationSupportDirectory();
    return File(
      '${support.path}${Platform.pathSeparator}$_lockFileName',
    ).exists();
  }

  static Future<void> crashIfArmed() async {
    if (!await isArmed()) return;
    await _crash(crashMessage);
  }

  Future<void> execute({required Future<void> Function() purgeData}) async {
    if (!supported) {
      throw UnsupportedError(
        'Self-destruct is available only on Android and iOS.',
      );
    }

    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    final cache = await getApplicationCacheDirectory();
    final temporary = await getTemporaryDirectory();

    await purgeData();
    await CookieManager.instance().deleteAllCookies();
    await WebStorageManager.instance().deleteAllData();

    final clearedPaths = <String>{};
    for (final directory in [cache, temporary, documents, support]) {
      final path = directory.absolute.path;
      if (clearedPaths.add(path)) await _clearDirectory(directory);
    }

    await support.create(recursive: true);
    final lock = File('${support.path}${Platform.pathSeparator}$_lockFileName');
    final pending = File('${lock.path}.pending');
    await pending.writeAsString(
      jsonEncode({'version': 1, 'message': crashMessage}),
      flush: true,
    );
    await pending.rename(lock.path);
    await _crash(crashMessage);
  }

  static Future<void> _clearDirectory(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      await entity.delete(recursive: true);
    }
  }

  static Future<void> _crash(String message) async {
    await _channel.invokeMethod<void>('crash', {'message': message});
    await Future<void>.delayed(const Duration(days: 36500));
  }
}
