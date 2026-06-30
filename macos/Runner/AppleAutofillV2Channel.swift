import FlutterMacOS
import Foundation
import OSLog

private let appleAutofillV2Log = Logger(
  subsystem: "dev.camillobucciarelli.kdbxKeyVault",
  category: "apple-autofill-v2"
)

final class AppleAutofillV2Channel {
  static let shared = AppleAutofillV2Channel()

  private let channelName = "dev.camillobucciarelli.keyvault/apple_autofill_v2"
  private let store = SharedAutofillStore()
  private var channel: FlutterMethodChannel?

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.channel = channel
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "publishCredentials":
      handlePublishCredentials(arguments: call.arguments, result: result)
    case "clearCredentials":
      handleClearCredentials(arguments: call.arguments, result: result)
    case "readPendingAssociations":
      handleReadPendingAssociations(result: result)
    case "clearPendingAssociations":
      handleClearPendingAssociations(arguments: call.arguments, result: result)
    case "getStatus":
      result(store.status().dictionary)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handlePublishCredentials(arguments: Any?, result: @escaping FlutterResult) {
    do {
      let request = try parsePublishArguments(arguments)
      appleAutofillV2Log.info("publishCredentials received entryCount=\(request.entries.count, privacy: .public)")
      store.publishCredentials(databaseId: request.databaseId, entries: request.entries) { publishResult in
        DispatchQueue.main.async {
          switch publishResult {
          case .success(let outcome):
            result(outcome.dictionary)
          case .failure(let error):
            result(self.flutterError(code: "publish_failed", error: error))
          }
        }
      }
    } catch {
      result(flutterError(code: "invalid_args", error: error))
    }
  }

  private func handleClearCredentials(arguments: Any?, result: @escaping FlutterResult) {
    let databaseId = (arguments as? [String: Any])?["databaseId"] as? String
    appleAutofillV2Log.info("clearCredentials received hasDatabaseId=\(databaseId != nil, privacy: .public)")
    store.clearCredentials(databaseId: databaseId) { clearResult in
      DispatchQueue.main.async {
        switch clearResult {
        case .success(let outcome):
          result(outcome.dictionary)
        case .failure(let error):
          result(self.flutterError(code: "clear_failed", error: error))
        }
      }
    }
  }

  private func handleReadPendingAssociations(result: @escaping FlutterResult) {
    result(store.readPendingAssociations().map { $0.dictionary })
  }

  private func handleClearPendingAssociations(arguments: Any?, result: @escaping FlutterResult) {
    do {
      let ids = try parsePendingAssociationIds(arguments)
      let clearedCount = try store.clearPendingAssociations(ids: ids)
      result(["clearedCount": clearedCount])
    } catch {
      result(flutterError(code: "clear_pending_associations_failed", error: error))
    }
  }

  private func parsePublishArguments(_ arguments: Any?) throws -> (databaseId: String, entries: [AutofillCredentialPublishEntry]) {
    guard let dictionary = arguments as? [String: Any] else {
      throw SharedAutofillStoreError.invalidPayload("arguments must be a map")
    }
    guard let databaseId = dictionary["databaseId"] as? String else {
      throw SharedAutofillStoreError.invalidPayload("databaseId must be a string")
    }
    guard let rawEntries = dictionary["entries"] as? [Any] else {
      throw SharedAutofillStoreError.invalidPayload("entries must be an array")
    }

    let entries = try rawEntries.map { rawEntry -> AutofillCredentialPublishEntry in
      guard let entry = rawEntry as? [String: Any] else {
        throw SharedAutofillStoreError.invalidPayload("entry must be a map")
      }
      guard let id = entry["id"] as? String else {
        throw SharedAutofillStoreError.invalidPayload("entry.id must be a string")
      }
      guard let title = entry["title"] as? String else {
        throw SharedAutofillStoreError.invalidPayload("entry.title must be a string")
      }
      guard let username = entry["username"] as? String else {
        throw SharedAutofillStoreError.invalidPayload("entry.username must be a string")
      }
      guard let password = entry["password"] as? String else {
        throw SharedAutofillStoreError.invalidPayload("entry.password must be a string")
      }

      let url = entry["url"] as? String
      let serviceIdentifiers = try parseServiceIdentifiers(entry["serviceIdentifiers"])
      return AutofillCredentialPublishEntry(
        id: id,
        title: title,
        username: username,
        password: password,
        url: url,
        serviceIdentifiers: serviceIdentifiers
      )
    }

    return (databaseId, entries)
  }

  private func parseServiceIdentifiers(_ rawValue: Any?) throws -> [AutofillInputServiceIdentifier] {
    guard let rawValue else { return [] }
    guard let rawIdentifiers = rawValue as? [Any] else {
      throw SharedAutofillStoreError.invalidPayload("serviceIdentifiers must be an array")
    }

    return try rawIdentifiers.map { rawIdentifier -> AutofillInputServiceIdentifier in
      guard let identifier = rawIdentifier as? [String: Any] else {
        throw SharedAutofillStoreError.invalidPayload("serviceIdentifier must be a map")
      }
      guard let type = identifier["type"] as? String else {
        throw SharedAutofillStoreError.invalidPayload("serviceIdentifier.type must be a string")
      }
      guard let value = identifier["value"] as? String else {
        throw SharedAutofillStoreError.invalidPayload("serviceIdentifier.value must be a string")
      }
      return AutofillInputServiceIdentifier(type: type, value: value)
    }
  }

  private func parsePendingAssociationIds(_ arguments: Any?) throws -> [String]? {
    guard let arguments else { return nil }
    guard let dictionary = arguments as? [String: Any] else {
      throw SharedAutofillStoreError.invalidPayload("arguments must be a map")
    }
    guard let rawIds = dictionary["ids"] else { return nil }
    if rawIds is NSNull { return nil }
    guard let ids = rawIds as? [Any] else {
      throw SharedAutofillStoreError.invalidPayload("ids must be an array")
    }

    return try ids.map { rawId -> String in
      guard let id = rawId as? String else {
        throw SharedAutofillStoreError.invalidPayload("ids must contain only strings")
      }
      return id
    }
  }

  private func flutterError(code: String, error: Error) -> FlutterError {
    FlutterError(
      code: code,
      message: error.localizedDescription,
      details: nil
    )
  }
}
