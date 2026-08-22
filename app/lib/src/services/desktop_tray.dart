import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app_controller.dart';

class DesktopTrayService with TrayListener, WindowListener {
  DesktopTrayService._();

  static final instance = DesktopTrayService._();

  AppController? _controller;
  bool _allowQuit = false;
  VoidCallback? _controllerListener;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> install(AppController controller) async {
    if (!_isDesktop) return;
    _controller = controller;
    _controllerListener = () => unawaited(_refreshMenu());
    controller.addListener(_controllerListener!);
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1100, 760),
        minimumSize: Size(520, 620),
        center: true,
        title: 'AiUsage',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon(
      Platform.isWindows
          ? 'windows/runner/resources/app_icon.ico'
          : 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png',
    );
    await _refreshMenu();
  }

  Future<void> _refreshMenu() async {
    if (!_isDesktop) return;
    final windows = _controller?.usage?.snapshot?.windows ?? const [];
    final summary = windows
        .take(2)
        .map((window) => '${window.title} ${window.usedPercent.round()}%')
        .toList();
    await trayManager.setToolTip(
      summary.isEmpty ? 'AiUsage' : summary.join(' · '),
    );
    await trayManager.setContextMenu(
      Menu(
        items: [
          ...summary.map((text) => MenuItem(label: text, disabled: true)),
          if (summary.isNotEmpty) MenuItem.separator(),
          MenuItem(key: 'open', label: 'Open'),
          MenuItem(key: 'refresh', label: 'Refresh'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        unawaited(_showWindow());
      case 'refresh':
        unawaited(_controller?.refresh() ?? Future<void>.value());
      case 'quit':
        unawaited(_quit());
    }
  }

  @override
  void onWindowClose() {
    if (_allowQuit) return;
    unawaited(windowManager.hide());
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    _allowQuit = true;
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    exit(0);
  }
}
