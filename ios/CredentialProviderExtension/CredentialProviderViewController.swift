import AuthenticationServices

final class CredentialProviderViewController: ASCredentialProviderViewController {
  private let store = SharedAutofillStore()

  override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
    let credentials = store.readCredentials()
    guard let matched = credentials.first(where: { credential in
      credential.username == credentialIdentity.user
    }) else {
      let error = NSError(
        domain: ASExtensionErrorDomain,
        code: ASExtensionError.userInteractionRequired.rawValue,
        userInfo: nil
      )
      extensionContext.cancelRequest(withError: error)
      return
    }

    let credential = ASPasswordCredential(user: matched.username, password: matched.password)
    extensionContext.completeRequest(withSelectedCredential: credential)
  }

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    let credentials = store.readCredentials()
    guard let first = credentials.first else {
      let error = NSError(
        domain: ASExtensionErrorDomain,
        code: ASExtensionError.failed.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "No credentials available"]
      )
      extensionContext.cancelRequest(withError: error)
      return
    }

    let credential = ASPasswordCredential(user: first.username, password: first.password)
    extensionContext.completeRequest(withSelectedCredential: credential)
  }

  override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
    provideCredentialWithoutUserInteraction(for: credentialIdentity)
  }

  override func prepareInterfaceForExtensionConfiguration() {
    extensionContext.completeExtensionConfigurationRequest()
  }
}
