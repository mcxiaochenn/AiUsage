import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../rust/models.dart';
import 'secure_account_vault.dart';

/// Local-only notifications. There is no notification server and no quota data
/// is sent anywhere other than OpenAI by the Rust HTTP client.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final Map<String, double> _previousUsage = {};
  final Map<String, int> _previousResetAt = {};
  bool _initialized = false;

  Future<void> initialize(LocalePreference locale) async {
    if (_initialized) return;
    final settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      linux: LinuxInitializationSettings(
        defaultActionName: _isChinese(locale) ? '打开' : 'Open',
      ),
      windows: WindowsInitializationSettings(
        appName: 'AiUsage',
        appUserModelId: 'dev.chendusk.aiusage',
        guid: 'b47bd236-f19d-4bf3-9f1c-ec523fe3210c',
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// Called only after the user explicitly enables notifications in Settings.
  Future<void> requestPermission({required LocalePreference locale}) async {
    await initialize(locale);
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    }
    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    }
  }

  Future<void> inspectSnapshot(
    UsageSnapshot snapshot, {
    required LocalePreference locale,
  }) async {
    await initialize(locale);
    final chinese =
        locale == LocalePreference.simplifiedChinese ||
        (locale == LocalePreference.system &&
            PlatformDispatcher.instance.locale.languageCode == 'zh');
    for (final window in snapshot.windows) {
      final key = '${snapshot.account.identityHash}:${window.id}';
      final previous = _previousUsage[key];
      final previousReset = _previousResetAt[key];
      final current = window.usedPercent;

      if (previous != null) {
        if (previous < 95 && current >= 95) {
          await _show(
            id: key.hashCode,
            title: chinese
                ? '${window.title} 即将用尽'
                : '${window.title} almost exhausted',
            body: chinese
                ? '该 Codex 额度已使用 ${current.round()}%。'
                : '${current.round()}% of this Codex limit is used.',
            locale: locale,
          );
        } else if (previous < 80 && current >= 80) {
          await _show(
            id: key.hashCode,
            title: chinese
                ? '${window.title} 已超过 80%'
                : '${window.title} is above 80%',
            body: chinese
                ? '该 Codex 额度已使用 ${current.round()}%。'
                : '${current.round()}% of this Codex limit is used.',
            locale: locale,
          );
        }
      }
      if (previousReset != null && window.resetAt > previousReset) {
        await _show(
          id: key.hashCode ^ 0x00ff00,
          title: chinese ? '${window.title} 已重置' : '${window.title} reset',
          body: chinese
              ? '新的 Codex 额度周期现已可用。'
              : 'A new Codex quota window is now available.',
          locale: locale,
        );
      }

      _previousUsage[key] = current;
      _previousResetAt[key] = window.resetAt;
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required LocalePreference locale,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'aiusage_usage',
        _isChinese(locale) ? 'Codex 用量' : 'Codex usage',
        channelDescription: _isChinese(locale)
            ? '额度阈值与重置通知'
            : 'Quota threshold and reset notifications',
        importance: Importance.defaultImportance,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
      linux: const LinuxNotificationDetails(),
    ),
  );

  bool _isChinese(LocalePreference locale) =>
      locale == LocalePreference.simplifiedChinese ||
      (locale == LocalePreference.system &&
          PlatformDispatcher.instance.locale.languageCode == 'zh');
}
