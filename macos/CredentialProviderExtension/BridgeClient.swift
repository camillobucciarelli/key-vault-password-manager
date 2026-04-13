import Foundation

private struct BridgeConfig: Decodable {
  let host: String
  let port: Int
  let token: String
  let expiresAtEpochMs: Int64
}

struct BridgeClient {
  private static var bridgeConfigURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".keyvault_autofill")
      .appendingPathComponent("bridge.json")
  }

  private let timeout: TimeInterval = 1.5

  /// Returns the best-matching credentials from the running app, or nil if
  /// the bridge is unavailable (app closed, token expired, network error).
  func findCredentials(for url: String, limit: Int = 10) async -> [SharedAutofillCredential]? {
    guard let config = Self.readConfig(), !isExpired(config) else { return nil }
    return await post(config: config, url: url, limit: limit)
  }

  // MARK: - Private

  private static func readConfig() -> BridgeConfig? {
    guard let data = try? Data(contentsOf: bridgeConfigURL) else { return nil }
    return try? JSONDecoder().decode(BridgeConfig.self, from: data)
  }

  private func isExpired(_ config: BridgeConfig) -> Bool {
    let expiresAt = Date(timeIntervalSince1970: Double(config.expiresAtEpochMs) / 1000.0)
    return Date() >= expiresAt
  }

  private func post(
    config: BridgeConfig,
    url: String,
    limit: Int
  ) async -> [SharedAutofillCredential]? {
    guard let endpoint = URL(string: "http://\(config.host):\(config.port)/v1/find") else {
      return nil
    }

    var request = URLRequest(url: endpoint, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["url": url, "limit": limit]
    )

    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.timeoutIntervalForRequest = timeout
    sessionConfig.timeoutIntervalForResource = timeout
    let session = URLSession(configuration: sessionConfig)

    guard
      let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse,
      http.statusCode == 200
    else { return nil }

    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawList = json["credentials"] as? [[String: Any]]
    else { return nil }

    return rawList.compactMap { dict -> SharedAutofillCredential? in
      guard
        let id       = dict["id"]       as? String,
        let title    = dict["title"]    as? String,
        let username = dict["username"] as? String,
        let password = dict["password"] as? String,
        let url      = dict["url"]      as? String
      else { return nil }
      // Bridge omits `notes` and `customFields` — update both sides together if needed.
      return SharedAutofillCredential(
        id: id, title: title, username: username,
        password: password, url: url, notes: "",
        customFields: []
      )
    }
  }
}
