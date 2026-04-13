import AuthenticationServices
import SwiftUI

final class MacCredentialProviderViewController: ASCredentialProviderViewController {
  private let store = SharedAutofillStore()
  private let bridge = BridgeClient()

  // MARK: - Credential list

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    Task { @MainActor in
      let allCredentials = await fetchCredentials(for: serviceIdentifiers)

      guard !allCredentials.isEmpty else {
        cancelWithError(.credentialIdentityNotFound)
        return
      }

      let scored = allCredentials
        .map { cred -> (SharedAutofillCredential, Int) in
          let score = serviceIdentifiers.reduce(0) {
            $0 + matchScore(credential: cred, serviceId: $1)
          }
          return (cred, score)
        }
        .sorted { $0.1 > $1.1 }

      let sorted      = scored.map { $0.0 }
      let topScore    = scored.first?.1 ?? 0
      let matchCount  = scored.filter { $0.1 > 0 }.count
      let bestId      = scored.first(where: { $0.1 > 0 })?.0.id

      // Silent fill: one unambiguous match or exact-domain hit
      if matchCount == 1 || topScore >= 140 {
        guard let best = scored.first(where: { $0.1 > 0 })?.0 else {
          showCredentialList(sorted, bestMatchId: bestId)
          return
        }
        extensionContext.completeRequest(
          withSelectedCredential: ASPasswordCredential(
            user: best.username,
            password: best.password
          )
        )
        return
      }

      showCredentialList(sorted, bestMatchId: bestId)
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
      guard !credentials.isEmpty else {
        cancelWithError(.credentialIdentityNotFound)
        return
      }
      let scored = credentials
        .map { ($0, matchScore(credential: $0, serviceId: credentialIdentity.serviceIdentifier)) }
        .sorted { $0.1 > $1.1 }
      let bestId = scored.first(where: { $0.1 > 0 })?.0.id
      showCredentialList(scored.map { $0.0 }, bestMatchId: bestId)
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

  private func matchScore(
    credential: SharedAutofillCredential,
    serviceId: ASCredentialServiceIdentifier
  ) -> Int {
    let identifier = serviceId.identifier.lowercased()

    if let entryHost = urlHost(from: credential.url)?.lowercased() {
      let normalizedEntry = stripCommonPrefixes(entryHost)
      let normalizedId    = stripCommonPrefixes(identifier)
      if normalizedEntry == normalizedId { return 140 }
      if normalizedEntry.hasSuffix(".\(normalizedId)") ||
         normalizedId.hasSuffix(".\(normalizedEntry)") { return 110 }
      if registrable(normalizedEntry) == registrable(normalizedId) { return 80 }
    }

    if let url = URL(string: credential.url),
       let scheme = url.scheme,
       (scheme == "androidapp" || scheme == "iosbundleid"),
       let bundleId = url.host?.lowercased() {
      if bundleId == identifier { return 140 }
    }

    for field in credential.customFields {
      let key = field.key.lowercased()
      if key == "kph: iosbundle" || key == "kph: androidpackage" {
        let values = field.value
          .split(whereSeparator: { ",; ".contains($0) })
          .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        if values.contains(identifier) { return 140 }
      }
    }

    return 0
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

  private func cancelWithError(_ code: ASExtensionError.Code) {
    extensionContext.cancelRequest(
      withError: NSError(
        domain: ASExtensionErrorDomain,
        code: code.rawValue,
        userInfo: nil
      )
    )
  }
}
