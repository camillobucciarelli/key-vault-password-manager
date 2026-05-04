import Cocoa
import FlutterMacOS

final class OtpAuthDeepLinkForwarder {
  static let shared = OtpAuthDeepLinkForwarder()

  private let channelName = "dev.camillobucciarelli.kdbxKeyVault/otpauth_deep_link"
  private var channel: FlutterMethodChannel?
  private var pendingUrls: [String] = []

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takePendingUrls" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.drainPendingUrls() ?? [])
    }
    self.channel = channel
  }

  func receive(_ url: URL) {
    guard url.scheme?.lowercased() == "otpauth" else { return }
    let urlString = url.absoluteString
    pendingUrls.append(urlString)
    channel?.invokeMethod("receiveOtpAuthUrl", arguments: urlString)
  }

  private func drainPendingUrls() -> [String] {
    let urls = pendingUrls
    pendingUrls.removeAll()
    return urls
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 420, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)
    OtpAuthDeepLinkForwarder.shared.configure(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

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

      let entriesKey      = "autofill_entries_json"
      let lastSyncKey     = "autofill_last_sync_epoch_ms"
      let pendingSavesKey = "pending_autofill_saves"

      switch call.method {
      case "saveSnapshot":
        guard
          let args = call.arguments as? [String: Any],
          let entries = args["entries"] as? String
        else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing entries payload.", details: nil))
          return
        }
        defaults.set(entries, forKey: entriesKey)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        defaults.set(timestamp, forKey: lastSyncKey)
        result(nil)

      case "clearSnapshot":
        defaults.removeObject(forKey: entriesKey)
        defaults.removeObject(forKey: lastSyncKey)
        result(nil)

      case "readAndClearPendingSaves":
        struct PendingSave: Decodable {
          let title: String
          let username: String
          let password: String
          let url: String
        }
        var saves: [[String: String]] = []
        if let json = defaults.string(forKey: pendingSavesKey),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([PendingSave].self, from: data) {
          saves = decoded.map { ["title": $0.title, "username": $0.username, "password": $0.password, "url": $0.url] }
        }
        defaults.removeObject(forKey: pendingSavesKey)
        result(saves)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
