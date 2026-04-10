import AuthenticationServices

final class CredentialProviderViewController: ASCredentialProviderViewController {
  private let store = SharedAutofillStore()

  // MARK: - Credential list (user explicitly opened the extension)

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    let credentials = store.readCredentials()
    let best = topMatch(in: credentials, for: serviceIdentifiers)
      ?? credentials.first

    guard let credential = best else {
      cancelWithError(.failed, message: "No credentials available")
      return
    }

    extensionContext.completeRequest(
      withSelectedCredential: ASPasswordCredential(
        user: credential.username,
        password: credential.password
      )
    )
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
    // iOS 18+: handle new-password requests by generating and saving a strong password
    if #available(iOS 18.0, *),
       let passwordRequest = credentialRequest as? ASPasswordCredentialRequest,
       passwordRequest.isNewPassword {
      let generated = CredentialProviderPasswordGenerator.generateDefault()
      let store = SharedAutofillStore()
      let serviceId = passwordRequest.credentialIdentity.serviceIdentifier
      let title = serviceId.identifier
      let pending = PendingAutofillSave(
        title: title,
        username: "",
        password: generated,
        url: serviceId.type == .URL ? serviceId.identifier : ""
      )
      store.writePendingSave(pending)
      extensionContext.completeRequest(
        withSelectedCredential: ASPasswordCredential(user: "", password: generated)
      )
      return
    }

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
