import Foundation
import OSLog

private let storeLog = Logger(
  subsystem: "dev.camillobucciarelli.kdbxKeyVault.CredentialProviderExtension",
  category: "store"
)

struct SharedAutofillCredential: Codable {
  let id: String
  let title: String
  let username: String
  let password: String
  let url: String
  let notes: String
  let customFields: [SharedCustomField]

  struct SharedCustomField: Codable {
    let key: String
    let value: String
  }

  // Custom decoder: `customFields` defaults to [] for cached JSON written
  // by older versions of the app that did not include this field.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id           = try c.decode(String.self, forKey: .id)
    title        = try c.decode(String.self, forKey: .title)
    username     = try c.decode(String.self, forKey: .username)
    password     = try c.decode(String.self, forKey: .password)
    url          = try c.decode(String.self, forKey: .url)
    notes        = try c.decode(String.self, forKey: .notes)
    customFields = try c.decodeIfPresent([SharedCustomField].self, forKey: .customFields) ?? []
  }
}

/// File-based shared store. We write/read JSON files inside the App Group
/// container URL instead of using `UserDefaults(suiteName:)` — iOS 18's
/// `cfprefsd` rejects app-group reads from extensions with
/// "kCFPreferencesAnyUser with a container is only allowed for System Containers",
/// leaving the extension with no credentials.
enum SharedAutofillPaths {
  static let appGroupId = "group.dev.camillobucciarelli.kdbxKeyVault"
  static let entriesFileName = "autofill_entries.json"
  static let pendingSavesFileName = "pending_autofill_saves.json"

  static func containerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
  }

  static func entriesURL() -> URL? {
    containerURL()?.appendingPathComponent(entriesFileName)
  }

  static func pendingSavesURL() -> URL? {
    containerURL()?.appendingPathComponent(pendingSavesFileName)
  }
}

final class SharedAutofillStore {
  func readCredentials() -> [SharedAutofillCredential] {
    guard let url = SharedAutofillPaths.entriesURL() else {
      storeLog.error("readCredentials: containerURL nil — App Group not accessible")
      return []
    }
    storeLog.info("readCredentials: path=\(url.path, privacy: .public)")

    let exists = FileManager.default.fileExists(atPath: url.path)
    storeLog.info("readCredentials: exists=\(exists, privacy: .public)")
    guard exists else { return [] }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      storeLog.error("readCredentials: read failed \(error.localizedDescription, privacy: .public)")
      return []
    }
    storeLog.info("readCredentials: bytes=\(data.count, privacy: .public)")

    do {
      let decoded = try JSONDecoder().decode([SharedAutofillCredential].self, from: data)
      storeLog.info("readCredentials: decoded count=\(decoded.count, privacy: .public)")
      let filtered = decoded.filter { !$0.username.isEmpty || !$0.password.isEmpty }
      storeLog.info("readCredentials: after filter count=\(filtered.count, privacy: .public)")
      return filtered
    } catch {
      let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
      storeLog.error("readCredentials: decode failed \(error.localizedDescription, privacy: .public) preview=\(preview, privacy: .public)")
      return []
    }
  }

  // MARK: - Pending saves (written by extension, read by main app)

  func writePendingSave(_ credential: PendingAutofillSave) {
    var existing = readPendingSaves()
    existing.append(credential)
    guard
      let url = SharedAutofillPaths.pendingSavesURL(),
      let data = try? JSONEncoder().encode(existing)
    else { return }
    try? data.write(to: url, options: .atomic)
  }

  private func readPendingSaves() -> [PendingAutofillSave] {
    guard
      let url = SharedAutofillPaths.pendingSavesURL(),
      let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode([PendingAutofillSave].self, from: data)
    else {
      return []
    }
    return decoded
  }
}

struct PendingAutofillSave: Codable {
  let title: String
  let username: String
  let password: String
  let url: String
}
