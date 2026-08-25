package dev.chendusk.aiusage

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.chendusk.aiusage/settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openApplicationDetails" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(null)
                }
                "openBatterySettings" -> {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.chendusk.aiusage/self_destruct",
        ).setMethodCallHandler { call, result ->
            if (call.method != "crash") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val message = call.argument<String>("message") ?: "AiUsage self-destruct"
            val error = IllegalStateException(message)
            Log.e("AiUsageSelfDestruct", message, error)
            result.success(null)
            Handler(Looper.getMainLooper()).post { throw error }
        }
    }
}
