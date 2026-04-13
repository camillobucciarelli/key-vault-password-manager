import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 420, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let autofillChannel = FlutterMethodChannel(
      name: "dev.camillobucciarelli.kdbxKeyVault/ios_autofill",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    autofillChannel.setMethodCallHandler { (call, result) in
      let suiteName = "group.dev.camillobucciarelli.kdbxKeyVault"
      guard let defaults = UserDefaults(suiteName: suiteName) else {
        result(FlutterError(
          code: "NO_APP_GROUP",
          message: "Unable to open shared App Group defaults.",
          details: suiteName
        ))
        return
      }

      switch call.method {
      case "saveSnapshot":
        let args = call.arguments as? [String: Any]
        if let entries = args?["entries"] as? String {
          defaults.set(entries, forKey: "autofill_entries_json")
          let epochMs = Int64(Date().timeIntervalSince1970 * 1000)
          defaults.set(epochMs, forKey: "autofill_last_sync_epoch_ms")
          defaults.synchronize()
        }
        result(nil)

      case "clearSnapshot":
        defaults.removeObject(forKey: "autofill_entries_json")
        defaults.removeObject(forKey: "autofill_last_sync_epoch_ms")
        defaults.synchronize()
        result(nil)

      case "readAndClearPendingSaves":
        var saves: [[String: String]] = []
        if let raw = defaults.object(forKey: "pending_autofill_saves") as? String,
           let data = raw.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
          saves = decoded
        } else if let raw = defaults.object(forKey: "pending_autofill_saves") as? Data,
                  let decoded = try? JSONSerialization.jsonObject(with: raw) as? [[String: String]] {
          saves = decoded
        }
        defaults.removeObject(forKey: "pending_autofill_saves")
        defaults.synchronize()
        result(saves)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
