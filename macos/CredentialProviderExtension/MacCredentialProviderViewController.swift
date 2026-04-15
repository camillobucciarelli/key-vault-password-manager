import AuthenticationServices
import SwiftUI

final class MacCredentialProviderViewController: ASCredentialProviderViewController {
  private let store = SharedAutofillStore()
  private let bridge = BridgeClient()

  // MARK: - Credential list

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    Task { @MainActor in
      let allCredentials = await fetchCredentials(for: serviceIdentifiers)

      let candidates = allCredentials.filter {
        !$0.username.trimmingCharacters(in: .whitespaces).isEmpty ||
        !$0.password.trimmingCharacters(in: .whitespaces).isEmpty
      }

      guard !candidates.isEmpty else {
        cancelWithError(.failed, message: "No credentials available")
        return
      }

      // Match score: pure URL / package / title signal — no credential bonus.
      // Used as the scoped-search gate and for silent-fill decisions.
      let withMatchScore = candidates.map { cred -> (SharedAutofillCredential, Int) in
        let ms = serviceIdentifiers.reduce(0) { $0 + matchScore(credential: cred, serviceId: $1) }
        return (cred, ms)
      }

      // Drop zero-match entries only when service identifiers are known.
      let scoped = serviceIdentifiers.isEmpty
        ? withMatchScore
        : withMatchScore.filter { $0.1 > 0 }

      // No credentials matched this site — show full list so the user can pick.
      let displayPairs: [(SharedAutofillCredential, Int)]
      let topMatchScore: Int
      let matchCount: Int
      let bestId: String?

      if scoped.isEmpty {
        displayPairs  = withMatchScore
        topMatchScore = 0
        matchCount    = 0
        bestId        = nil
      } else {
        displayPairs  = scoped
        topMatchScore = withMatchScore.map { $0.1 }.max() ?? 0
        matchCount    = withMatchScore.filter { $0.1 > 0 }.count
        bestId        = withMatchScore.sorted { $0.1 > $1.1 }.first(where: { $0.1 > 0 })?.0.id
      }

      // Add credential-completeness bonus for ranking tiebreaking (mirrors Android).
      let sorted = displayPairs
        .map { (cred, ms) -> (SharedAutofillCredential, Int) in
          let hasUsername = !cred.username.trimmingCharacters(in: .whitespaces).isEmpty
          let hasPassword = !cred.password.trimmingCharacters(in: .whitespaces).isEmpty
          return (cred, ms + ((hasUsername && hasPassword) ? 20 : 10))
        }
        .sorted {
          if $0.1 != $1.1 { return $0.1 > $1.1 }
          return $0.0.title.localizedCompare($1.0.title) == .orderedAscending
        }

      // Silent fill: one unambiguous match or an exact-domain / exact-bundle hit.
      if matchCount == 1 || topMatchScore >= 140 {
        if let best = sorted.first?.0 {
          extensionContext.completeRequest(
            withSelectedCredential: ASPasswordCredential(
              user: best.username,
              password: best.password
            )
          )
          return
        }
      }

      showCredentialList(sorted.map { $0.0 }, bestMatchId: bestId)
    }
  }

  private func showCredentialList(
    _ credentials: [SharedAutofillCredential],
    bestMatchId: String?
  ) {
    let rootView = CredentialListView(
      credentials: credentials,
      bestMatchId: bestMatchId,
      onSelect: { [weak self] cred in
        self?.extensionContext.completeRequest(
          withSelectedCredential: ASPasswordCredential(
            user: cred.username,
            password: cred.password
          )
        )
      },
      onCancel: { [weak self] in
        self?.cancelWithError(.userCanceled)
      }
    )

    let host = NSHostingController(rootView: rootView)
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  // MARK: - Silent fill

  override func provideCredentialWithoutUserInteraction(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    Task { @MainActor in
      let credentials = await fetchCredentials(for: [credentialIdentity.serviceIdentifier])
      guard let matched = credentials.first(where: { credential in
        credential.username == credentialIdentity.user &&
        credentialMatchesService(credential, serviceId: credentialIdentity.serviceIdentifier)
      }) else {
        cancelWithError(.userInteractionRequired)
        return
      }
      extensionContext.completeRequest(
        withSelectedCredential: ASPasswordCredential(
          user: matched.username,
          password: matched.password
        )
      )
    }
  }

  // macOS 14 API
  override func provideCredentialWithoutUserInteraction(
    for credentialRequest: any ASCredentialRequest
  ) {
    if let passwordRequest = credentialRequest as? ASPasswordCredentialRequest,
       let identity = passwordRequest.credentialIdentity as? ASPasswordCredentialIdentity {
      provideCredentialWithoutUserInteraction(for: identity)
    } else {
      cancelWithError(.failed)
    }
  }

  override func prepareInterfaceToProvideCredential(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    // Called after userInteractionRequired — show full list, no silent fill.
    Task { @MainActor in
      let credentials = await fetchCredentials(for: [credentialIdentity.serviceIdentifier])
      let candidates = credentials.filter {
        !$0.username.trimmingCharacters(in: .whitespaces).isEmpty ||
        !$0.password.trimmingCharacters(in: .whitespaces).isEmpty
      }
      guard !candidates.isEmpty else {
        cancelWithError(.failed, message: "No credentials available")
        return
      }
      let withMatchScore = candidates.map { cred -> (SharedAutofillCredential, Int) in
        let ms = matchScore(credential: cred, serviceId: credentialIdentity.serviceIdentifier)
        return (cred, ms)
      }
      let sorted = withMatchScore
        .map { (cred, ms) -> (SharedAutofillCredential, Int) in
          let hasUsername = !cred.username.trimmingCharacters(in: .whitespaces).isEmpty
          let hasPassword = !cred.password.trimmingCharacters(in: .whitespaces).isEmpty
          return (cred, ms + ((hasUsername && hasPassword) ? 20 : 10))
        }
        .sorted {
          if $0.1 != $1.1 { return $0.1 > $1.1 }
          return $0.0.title.localizedCompare($1.0.title) == .orderedAscending
        }
      let bestId = withMatchScore.sorted { $0.1 > $1.1 }.first(where: { $0.1 > 0 })?.0.id
      showCredentialList(sorted.map { $0.0 }, bestMatchId: bestId)
    }
  }

  override func prepareInterfaceForExtensionConfiguration() {
    extensionContext.completeExtensionConfigurationRequest()
  }

  // MARK: - Data fetching

  private func fetchCredentials(
    for serviceIdentifiers: [ASCredentialServiceIdentifier]
  ) async -> [SharedAutofillCredential] {
    let url = serviceIdentifiers.first?.identifier ?? ""
    if let bridgeResults = await bridge.findCredentials(for: url),
       !bridgeResults.isEmpty {
      return bridgeResults
    }
    return store.readCredentials()
  }

  // MARK: - Matching

  private func credentialMatchesService(
    _ credential: SharedAutofillCredential,
    serviceId: ASCredentialServiceIdentifier
  ) -> Bool {
    matchScore(credential: credential, serviceId: serviceId) > 0
  }

  /// Scores a credential against a single service identifier.
  /// Returns the match signal (URL / package / title) without any credential
  /// completeness bonus so that callers can use it as a gate condition.
  private func matchScore(
    credential: SharedAutofillCredential,
    serviceId: ASCredentialServiceIdentifier
  ) -> Int {
    let identifier = serviceId.identifier.lowercased()
    var score = 0

    // Domain matching (3-tier: exact / subdomain / registrable)
    if let entryHost = urlHost(from: credential.url)?.lowercased() {
      let normalizedEntry = stripCommonPrefixes(entryHost)
      let normalizedId    = stripCommonPrefixes(identifier)
      if normalizedEntry == normalizedId {
        score += 140
      } else if normalizedEntry.hasSuffix(".\(normalizedId)") ||
                normalizedId.hasSuffix(".\(normalizedEntry)") {
        score += 110
      } else if registrable(normalizedEntry) == registrable(normalizedId) {
        score += 80
      }
    }

    // Bundle ID via androidapp:// / iosbundleid:// URL scheme (3-tier: exact / related / substring)
    if let url = URL(string: credential.url),
       let scheme = url.scheme,
       (scheme == "androidapp" || scheme == "iosbundleid"),
       let bundleId = url.host?.lowercased() {
      if bundleId == identifier {
        score += 140
      } else if bundleId.hasSuffix(".\(identifier)") || identifier.hasSuffix(".\(bundleId)") {
        score += 100
      } else if bundleId.contains(identifier) || identifier.contains(bundleId) {
        score += 70
      }
    }

    // Bundle ID via KPH custom fields (3-tier: exact / related / substring)
    outer: for field in credential.customFields {
      let key = field.key.lowercased()
      if key == "kph: iosbundle" || key == "kph: androidpackage" {
        let values = field.value
          .split(whereSeparator: { ",; ".contains($0) })
          .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        if values.contains(identifier) {
          score += 140; break outer
        } else if values.contains(where: { $0.hasSuffix(".\(identifier)") || identifier.hasSuffix(".\($0)") }) {
          score += 100; break outer
        } else if values.contains(where: { $0.contains(identifier) || identifier.contains($0) }) {
          score += 70; break outer
        }
      }
    }

    // Title-in-domain heuristic (+35) — mirrors Android VaultAutofillMatcher.
    // Only applied when the service identifier is a URL (not an app bundle ID).
    if identifier.hasPrefix("https://") || identifier.hasPrefix("http://") {
      let reqDomain = stripCommonPrefixes(urlHost(from: identifier) ?? "")
      if !reqDomain.isEmpty && credential.title.lowercased().contains(reqDomain) {
        score += 35
      }
    }

    return score
  }

  // MARK: - URL utilities

  private func urlHost(from rawUrl: String) -> String? {
    guard !rawUrl.isEmpty else { return nil }
    let url = rawUrl.contains("://") ? URL(string: rawUrl) : URL(string: "https://\(rawUrl)")
    return url?.host
  }

  private func stripCommonPrefixes(_ domain: String) -> String {
    var d = domain
    for prefix in ["www.", "m.", "mobile."] {
      if d.hasPrefix(prefix) { d = String(d.dropFirst(prefix.count)); break }
    }
    return d
  }

  private func registrable(_ domain: String) -> String {
    let parts = domain.split(separator: ".").filter { !$0.isEmpty }
    guard parts.count >= 2 else { return domain }
    return "\(parts[parts.count - 2]).\(parts.last!)"
  }

  // MARK: - Error helper

  private func cancelWithError(_ code: ASExtensionError.Code, message: String? = nil) {
    let userInfo: [String: Any]? = message.map { [NSLocalizedDescriptionKey: $0] }
    extensionContext.cancelRequest(
      withError: NSError(
        domain: ASExtensionErrorDomain,
        code: code.rawValue,
        userInfo: userInfo
      )
    )
  }
}
