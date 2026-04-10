import Foundation

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

final class SharedAutofillStore {
  private let appGroupId = "group.dev.camillobucciarelli.kdbxKeyVault"
  private let autofillEntriesKey = "autofill_entries_json"
  private let pendingSavesKey = "pending_autofill_saves"

  func readCredentials() -> [SharedAutofillCredential] {
    guard
      let defaults = UserDefaults(suiteName: appGroupId),
      let json = defaults.string(forKey: autofillEntriesKey),
      let data = json.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([SharedAutofillCredential].self, from: data)
    else {
      return []
    }
    return decoded.filter { !$0.username.isEmpty || !$0.password.isEmpty }
  }

  // MARK: - Pending saves (written by extension, read by main app)

  func writePendingSave(_ credential: PendingAutofillSave) {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
    var existing = _readPendingSaves(defaults: defaults)
    existing.append(credential)
    if let data = try? JSONEncoder().encode(existing),
       let json = String(data: data, encoding: .utf8) {
      defaults.set(json, forKey: pendingSavesKey)
      defaults.synchronize()
    }
  }

  private func _readPendingSaves(defaults: UserDefaults) -> [PendingAutofillSave] {
    guard
      let json = defaults.string(forKey: pendingSavesKey),
      let data = json.data(using: .utf8),
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
