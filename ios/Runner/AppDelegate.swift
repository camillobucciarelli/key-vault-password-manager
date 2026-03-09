import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let autofillChannelName = "dev.camillobucciarelli.kdbxKeyVault/ios_autofill"
  private let autofillEntriesKey = "autofill_entries_json"
  private let autofillLastSyncKey = "autofill_last_sync_epoch_ms"
  private let appGroupId = "group.dev.camillobucciarelli.kdbxKeyVault"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let rootController = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: autofillChannelName,
        binaryMessenger: rootController.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleAutofillChannel(call: call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func handleAutofillChannel(call: FlutterMethodCall, result: FlutterResult) {
    guard let defaults = UserDefaults(suiteName: appGroupId) else {
      result(
        FlutterError(
          code: "NO_APP_GROUP",
          message: "Unable to open shared App Group defaults.",
          details: appGroupId
        )
      )
      return
    }

    switch call.method {
    case "saveSnapshot":
      guard
        let args = call.arguments as? [String: Any],
        let entries = args["entries"] as? String
      else {
        result(
          FlutterError(
            code: "INVALID_ARGS",
            message: "Missing entries payload.",
            details: nil
          )
        )
        return
      }

      defaults.set(entries, forKey: autofillEntriesKey)
      let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
      defaults.set(timestamp, forKey: autofillLastSyncKey)
      defaults.synchronize()
      result(nil)

    case "clearSnapshot":
      defaults.removeObject(forKey: autofillEntriesKey)
      defaults.removeObject(forKey: autofillLastSyncKey)
      defaults.synchronize()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
