import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var selfDestructChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    selfDestructChannel = FlutterMethodChannel(
      name: "dev.chendusk.aiusage/self_destruct",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    selfDestructChannel?.setMethodCallHandler { call, result in
      guard call.method == "crash" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let message = arguments?["message"] as? String ?? "AiUsage self-destruct"
      fatalError(message)
    }
  }
}
