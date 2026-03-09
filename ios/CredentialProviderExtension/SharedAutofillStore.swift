import Foundation

struct SharedAutofillCredential: Codable {
  let id: String
  let title: String
  let username: String
  let password: String
  let url: String
  let notes: String
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
