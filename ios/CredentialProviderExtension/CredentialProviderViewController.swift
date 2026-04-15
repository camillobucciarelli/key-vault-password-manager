import AuthenticationServices
import SwiftUI

final class CredentialProviderViewController: ASCredentialProviderViewController {
  private let store = SharedAutofillStore()

  // MARK: - Credential list (user explicitly opened the extension)

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    let allCredentials = store.readCredentials()

    guard !allCredentials.isEmpty else {
      cancelWithError(.failed, message: "No credentials available")
      return
    }

    // Score and sort: best matches first, unmatched entries below
    let scored = allCredentials
      .map { cred -> (SharedAutofillCredential, Int) in
        let score = serviceIdentifiers.reduce(0) {
          $0 + matchScore(credential: cred, serviceId: $1)
        }
        return (cred, score)
      }
      .sorted { $0.1 > $1.1 }

    let sorted = scored.map { $0.0 }
    let bestId = scored.first(where: { $0.1 > 0 })?.0.id

    showCredentialList(sorted, bestMatchId: bestId)
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

    let host = UIHostingController(rootView: rootView)
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    host.didMove(toParent: self)
  }

  // MARK: - Silent fill (iOS already knows which credential to use)

  override func provideCredentialWithoutUserInteraction(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    let credentials = store.readCredentials()
    guard let matched = credentials.first(where: { credential in
      credential.username == credentialIdentity.user &&
      credentialMatchesService(
        credential,
        serviceId: credentialIdentity.serviceIdentifier
      )
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

  // MARK: - iOS 17: new password requests + save flow

  @available(iOS 17.0, *)
  override func provideCredentialWithoutUserInteraction(
    for credentialRequest: any ASCredentialRequest
  ) {
    // Regular fill: delegate to the password-identity based method
    if let passwordRequest = credentialRequest as? ASPasswordCredentialRequest,
       let identity = passwordRequest.credentialIdentity as? ASPasswordCredentialIdentity {
      provideCredentialWithoutUserInteraction(for: identity)
    } else {
      cancelWithError(.failed, message: "Unsupported credential type")
    }
  }

  override func prepareInterfaceToProvideCredential(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    // Called by iOS when non-interactive fill returned userInteractionRequired.
    // Delegate back to the matching logic; cancel if still no match.
    provideCredentialWithoutUserInteraction(for: credentialIdentity)
  }

  override func prepareInterfaceForExtensionConfiguration() {
    extensionContext.completeExtensionConfigurationRequest()
  }

  // MARK: - Matching helpers

  private func topMatch(
    in credentials: [SharedAutofillCredential],
    for serviceIdentifiers: [ASCredentialServiceIdentifier]
  ) -> SharedAutofillCredential? {
    var best: (credential: SharedAutofillCredential, score: Int)?

    for credential in credentials {
      var score = 0
      for serviceId in serviceIdentifiers {
        score += matchScore(credential: credential, serviceId: serviceId)
      }
      if score > 0 {
        if best == nil || score > best!.score {
          best = (credential, score)
        }
      }
    }

    return best?.credential
  }

  private func credentialMatchesService(
    _ credential: SharedAutofillCredential,
    serviceId: ASCredentialServiceIdentifier
  ) -> Bool {
    return matchScore(credential: credential, serviceId: serviceId) > 0
  }

  private func matchScore(
    credential: SharedAutofillCredential,
    serviceId: ASCredentialServiceIdentifier
  ) -> Int {
    let identifier = serviceId.identifier.lowercased()

    // Domain match against entry URL
    if let entryHost = urlHost(from: credential.url)?.lowercased() {
      let normalizedEntry = stripCommonPrefixes(entryHost)
      let normalizedId = stripCommonPrefixes(identifier)
      if normalizedEntry == normalizedId { return 140 }
      if normalizedEntry.hasSuffix(".\(normalizedId)") ||
         normalizedId.hasSuffix(".\(normalizedEntry)") { return 110 }
      if registrable(normalizedEntry) == registrable(normalizedId) { return 80 }
    }

    // Bundle ID match via androidapp:// / iosbundleid:// URL
    if let url = URL(string: credential.url),
       let scheme = url.scheme,
       (scheme == "androidapp" || scheme == "iosbundleid"),
       let bundleId = url.host?.lowercased() {
      if bundleId == identifier { return 140 }
    }

    // Bundle ID match via KPH: iosBundle / KPH: androidPackage custom fields
    for field in credential.customFields {
      let key = field.key.lowercased()
      if key == "kph: iosbundle" || key == "kph: androidpackage" {
        let values = field.value.split(whereSeparator: { ",; ".contains($0) })
          .map { $0.lowercased().trimmingCharacters(in: CharacterSet.whitespaces) }
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

  // MARK: - Error helpers

  private func cancelWithError(
    _ code: ASExtensionError.Code,
    message: String? = nil
  ) {
    var userInfo: [String: Any]? = nil
    if let message = message {
      userInfo = [NSLocalizedDescriptionKey: message]
    }
    extensionContext.cancelRequest(
      withError: NSError(
        domain: ASExtensionErrorDomain,
        code: code.rawValue,
        userInfo: userInfo
      )
    )
  }
}
