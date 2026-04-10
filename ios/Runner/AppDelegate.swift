import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let autofillChannelName = "dev.camillobucciarelli.kdbxKeyVault/ios_autofill"
  private let autofillEntriesKey = "autofill_entries_json"
  private let autofillLastSyncKey = "autofill_last_sync_epoch_ms"
  private let appGroupId = "group.dev.camillobucciarelli.kdbxKeyVault"
  private let pendingSavesKey = "pending_autofill_saves"

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

      // Register credentials in ASCredentialIdentityStore
      // so they appear in the QuickType keyboard bar
      if #available(iOS 17, *) {
        if let data = entries.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([SharedAutofillCredentialPayload].self, from: data) {
          registerCredentialIdentities(from: decoded)
        }
      }

      result(nil)

    case "clearSnapshot":
      defaults.removeObject(forKey: autofillEntriesKey)
      defaults.removeObject(forKey: autofillLastSyncKey)
      defaults.synchronize()
      result(nil)

    case "readAndClearPendingSaves":
      guard let savesDefaults = UserDefaults(suiteName: appGroupId) else {
        result([])
        return
      }
      guard
        let json = savesDefaults.string(forKey: pendingSavesKey),
        let data = json.data(using: .utf8),
        let decoded = try? JSONDecoder().decode([PendingAutofillSavePayload].self, from: data)
      else {
        result([])
        return
      }
      savesDefaults.removeObject(forKey: pendingSavesKey)
      savesDefaults.synchronize()
      let mapped: [[String: String]] = decoded.map { save in
        ["title": save.title, "username": save.username, "password": save.password, "url": save.url]
      }
      result(mapped)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 17, *)
  private func registerCredentialIdentities(from entries: [SharedAutofillCredentialPayload]) {
    var identities: [ASPasswordCredentialIdentity] = []

    for entry in entries {
      // URL-based service identifier
      if !entry.url.isEmpty,
         let url = URL(string: entry.url),
         let host = url.host, !host.isEmpty,
         !entry.username.isEmpty {
        let serviceId = ASCredentialServiceIdentifier(identifier: host, type: .domain)
        let identity = ASPasswordCredentialIdentity(
          serviceIdentifier: serviceId,
          user: entry.username,
          recordIdentifier: entry.id
        )
        identities.append(identity)
      }

      // Bundle ID via KPH: iosBundle custom field
      if let bundleField = entry.customFields.first(where: {
        $0.key.lowercased() == "kph: iosbundle"
      }), !bundleField.value.isEmpty, !entry.username.isEmpty {
        let serviceId = ASCredentialServiceIdentifier(
          identifier: bundleField.value,
          type: .domain
        )
        let identity = ASPasswordCredentialIdentity(
          serviceIdentifier: serviceId,
          user: entry.username,
          recordIdentifier: entry.id
        )
        identities.append(identity)
      }
    }

    ASCredentialIdentityStore.shared.replaceCredentialIdentities(
      with: identities
    ) { success, error in
      if let error = error {
        print("[Autofill] Failed to register identities: \(error)")
      }
    }
  }
}

private struct SharedAutofillCredentialPayload: Decodable {
  struct CustomField: Decodable {
    let key: String
    let value: String
  }
  let id: String
  let username: String
  let url: String
  let customFields: [CustomField]
}

private struct PendingAutofillSavePayload: Decodable {
  let title: String
  let username: String
  let password: String
  let url: String
}
