import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../rust/models.dart';

/// Local-only notifications. There is no notification server and no quota data
/// is sent anywhere other than OpenAI by the Rust HTTP client.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final Map<String, double> _previousUsage = {};
  final Map<String, int> _previousResetAt = {};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
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
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: WindowsInitializationSettings(
        appName: 'Codex Usage Monitor',
        appUserModelId: 'dev.codexusage.monitor',
        guid: '2cb4e4a0-11ce-4638-8a12-91e1b1122574',
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// Called only after the user explicitly enables notifications in Settings.
  Future<void> requestPermission() async {
    await initialize();
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

  Future<void> inspectSnapshot(UsageSnapshot snapshot) async {
    await initialize();
    for (final window in snapshot.windows) {
      final key = '${snapshot.account.identityHash}:${window.id}';
      final previous = _previousUsage[key];
      final previousReset = _previousResetAt[key];
      final current = window.usedPercent;

      if (previous != null) {
        if (previous < 95 && current >= 95) {
          await _show(
            id: key.hashCode,
            title: '${window.title} almost exhausted',
            body: '${current.round()}% of this Codex limit is used.',
          );
        } else if (previous < 80 && current >= 80) {
          await _show(
            id: key.hashCode,
            title: '${window.title} is above 80%',
            body: '${current.round()}% of this Codex limit is used.',
          );
        }
      }
      if (previousReset != null && window.resetAt > previousReset) {
        await _show(
          id: key.hashCode ^ 0x00ff00,
          title: '${window.title} reset',
          body: 'A new Codex quota window is now available.',
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
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'codex_usage',
        'Codex usage',
        channelDescription: 'Quota threshold and reset notifications',
        importance: Importance.defaultImportance,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
    ),
  );
}
