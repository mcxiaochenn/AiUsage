import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../rust/api/application.dart' as core;
import '../rust/frb_generated.dart';
import 'secure_account_vault.dart';

const _backgroundTaskName = 'codex_usage_refresh';
// Also listed in iOS BGTaskSchedulerPermittedIdentifiers.
const _backgroundUniqueName = 'dev.codexusage.monitor.refresh';

/// Entrypoint used by Android WorkManager and iOS BGTaskScheduler.
///
/// Scheduling is intentionally best effort: Android applies its periodic-work
/// floor and iOS decides when a task may run. Foreground/resume refreshes are
/// always available and are the app's primary freshness mechanism.
@pragma('vm:entry-point')
void backgroundRefreshDispatcher() {
  Workmanager().executeTask((_, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await RustLib.init();
      final supportDirectory = await getApplicationSupportDirectory();
      final databasePath =
          '${supportDirectory.path}${Platform.pathSeparator}codex_usage_monitor.sqlite3';
      await core.initializeCore(databasePath: databasePath);

      final vault = SecureAccountVault();
      for (final account in await vault.loadAccounts()) {
        final credential = account.credential;
        if (credential == null) continue;
        final result = await core.refreshUsage(credential: credential);
        if (result.updatedCredential != null) {
          await vault.updateCredential(
            account.identityHash,
            result.updatedCredential!,
          );
        }
        if (result.snapshot != null) {
          await vault.updateAccount(result.snapshot!.account);
        }
      }
      return true;
    } catch (_) {
      // WorkManager will apply its own bounded rescheduling policy. Never spin
      // here: a failed background refresh must not drain a mobile battery.
      return false;
    }
  });
}

class BackgroundRefreshScheduler {
  const BackgroundRefreshScheduler();

  Future<void> configure(int refreshMinutes) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await Workmanager().initialize(backgroundRefreshDispatcher);
    await Workmanager().cancelByUniqueName(_backgroundUniqueName);
    if (refreshMinutes == 0) return;

    // Android periodic WorkManager requests cannot be more frequent than 15
    // minutes. The app still honours 5 minutes while it is in foreground.
    final effectiveMinutes = refreshMinutes < 15 ? 15 : refreshMinutes;
    await Workmanager().registerPeriodicTask(
      _backgroundUniqueName,
      _backgroundTaskName,
      frequency: Duration(minutes: effectiveMinutes),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}
