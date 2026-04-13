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

  // Explicit memberwise init — required because the Decodable init below
  // suppresses Swift's auto-generated memberwise initializer.
  init(
    id: String, title: String, username: String,
    password: String, url: String, notes: String,
    customFields: [SharedCustomField]
  ) {
    self.id = id
    self.title = title
    self.username = username
    self.password = password
    self.url = url
    self.notes = notes
    self.customFields = customFields
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
}
