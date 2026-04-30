import AuthenticationServices
import Flutter
import OSLog
import UIKit

private let autofillLog = Logger(
  subsystem: "dev.camillobucciarelli.kdbxKeyVault",
  category: "autofill-host"
)

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let autofillChannelName = "dev.camillobucciarelli.kdbxKeyVault/ios_autofill"
  private let autofillLastSyncKey = "autofill_last_sync_epoch_ms"
  private let appGroupId = "group.dev.camillobucciarelli.kdbxKeyVault"

  // File-based shared storage (mirrors SharedAutofillPaths in extension target).
  // iOS 18 cfprefsd rejects `UserDefaults(suiteName:)` reads from the extension
  // process with "kCFPreferencesAnyUser with a container is only allowed for
  // System Containers", so entries + pending saves live in container files.
  private let entriesFileName = "autofill_entries.json"
  private let pendingSavesFileName = "pending_autofill_saves.json"

  private var sharedContainerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
  }

  private var entriesFileURL: URL? {
    sharedContainerURL?.appendingPathComponent(entriesFileName)
  }

  private var pendingSavesFileURL: URL? {
    sharedContainerURL?.appendingPathComponent(pendingSavesFileName)
  }

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
    guard let entriesURL = entriesFileURL, let pendingURL = pendingSavesFileURL else {
      result(
        FlutterError(
          code: "NO_APP_GROUP",
          message: "Unable to resolve shared App Group container URL.",
          details: appGroupId
        )
      )
      return
    }

    switch call.method {
    case "saveSnapshot":
      guard
        let args = call.arguments as? [String: Any],
        let entries = args["entries"] as? String,
        let data = entries.data(using: .utf8)
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

      do {
        try data.write(to: entriesURL, options: .atomic)
        autofillLog.info("saveSnapshot wrote bytes=\(data.count, privacy: .public) path=\(entriesURL.path, privacy: .public)")
      } catch {
        autofillLog.error("saveSnapshot write failed \(error.localizedDescription, privacy: .public) path=\(entriesURL.path, privacy: .public)")
        result(
          FlutterError(
            code: "WRITE_FAILED",
            message: "Unable to write autofill snapshot file.",
            details: error.localizedDescription
          )
        )
        return
      }

      // Timestamp is main-app-only; UserDefaults is fine for this (no extension read).
      if let defaults = UserDefaults(suiteName: appGroupId) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        defaults.set(timestamp, forKey: autofillLastSyncKey)
      }

      // Register credentials in ASCredentialIdentityStore
      // so they appear in the QuickType keyboard bar
      if #available(iOS 17, *) {
        if let decoded = try? JSONDecoder().decode([SharedAutofillCredentialPayload].self, from: data) {
          registerCredentialIdentities(from: decoded)
        }
      }

      result(nil)

    case "clearSnapshot":
      autofillLog.info("clearSnapshot path=\(entriesURL.path, privacy: .public)")
      try? FileManager.default.removeItem(at: entriesURL)
      if let defaults = UserDefaults(suiteName: appGroupId) {
        defaults.removeObject(forKey: autofillLastSyncKey)
      }
      result(nil)

    case "readAndClearPendingSaves":
      guard
        let data = try? Data(contentsOf: pendingURL),
        let decoded = try? JSONDecoder().decode([PendingAutofillSavePayload].self, from: data)
      else {
        result([])
        return
      }
      try? FileManager.default.removeItem(at: pendingURL)
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
