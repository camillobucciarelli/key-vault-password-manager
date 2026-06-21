import AuthenticationServices
import OSLog
import SwiftUI

private let log = Logger(
  subsystem: "dev.camillobucciarelli.kdbxKeyVault.CredentialProviderExtension",
  category: "ext"
)

final class MacCredentialProviderViewController: ASCredentialProviderViewController {
  private let store = SharedAutofillStore()
  private var hostingController: NSHostingController<CredentialListView>?

  override func viewDidLoad() {
    super.viewDidLoad()
    store.wipeLegacyPlaintextArtifacts(reason: "viewDidLoad")
    log.info("viewDidLoad")
  }

  // MARK: - Credential list

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    log.info("prepareCredentialList serviceIdentifierCount=\(serviceIdentifiers.count, privacy: .public)")
    showCredentialList(
      reason: "credential list",
      serviceIdentifiers: serviceIdentifiers,
      preferredRecordIdentifier: nil
    )
  }

  override func prepareCredentialList(
    for serviceIdentifiers: [ASCredentialServiceIdentifier],
    requestParameters: ASPasskeyCredentialRequestParameters
  ) {
    log.info("prepareCredentialList(requestParameters) serviceIdentifierCount=\(serviceIdentifiers.count, privacy: .public)")
    showCredentialList(
      reason: "credential list request parameters",
      serviceIdentifiers: serviceIdentifiers,
      preferredRecordIdentifier: nil
    )
  }

  // MARK: - Silent fill

  override func provideCredentialWithoutUserInteraction(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    log.info("provideCredentialWithoutUserInteraction(identity) requires user interaction")
    store.wipeLegacyPlaintextArtifacts(reason: "silent fill")
    cancelWithError(.userInteractionRequired)
  }

  override func provideCredentialWithoutUserInteraction(
    for credentialRequest: any ASCredentialRequest
  ) {
    log.info("provideCredentialWithoutUserInteraction(any) type=\(String(describing: type(of: credentialRequest)), privacy: .public)")
    guard let passwordRequest = credentialRequest as? ASPasswordCredentialRequest,
          let identity = passwordRequest.credentialIdentity as? ASPasswordCredentialIdentity else {
      log.error("unsupported credential request → .failed")
      cancelWithError(.failed)
      return
    }

    provideCredentialWithoutUserInteraction(for: identity)
  }

  // MARK: - Interactive fill

  override func prepareInterfaceToProvideCredential(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    log.info("prepareInterfaceToProvideCredential(identity)")
    showCredentialList(
      reason: "interactive fill",
      serviceIdentifiers: [credentialIdentity.serviceIdentifier],
      preferredRecordIdentifier: credentialIdentity.recordIdentifier
    )
  }

  override func prepareInterfaceToProvideCredential(
    for credentialRequest: any ASCredentialRequest
  ) {
    log.info("prepareInterfaceToProvideCredential(any) type=\(String(describing: type(of: credentialRequest)), privacy: .public)")
    guard let passwordRequest = credentialRequest as? ASPasswordCredentialRequest,
          let identity = passwordRequest.credentialIdentity as? ASPasswordCredentialIdentity else {
      log.error("unsupported interactive credential request → .failed")
      cancelWithError(.failed)
      return
    }

    prepareInterfaceToProvideCredential(for: identity)
  }

  override func prepareInterfaceForExtensionConfiguration() {
    log.info("prepareInterfaceForExtensionConfiguration")
    store.wipeLegacyPlaintextArtifacts(reason: "extension configuration")
    extensionContext.completeExtensionConfigurationRequest()
  }

  // MARK: - UI

  private func showCredentialList(
    reason: String,
    serviceIdentifiers: [ASCredentialServiceIdentifier],
    preferredRecordIdentifier: String?
  ) {
    store.wipeLegacyPlaintextArtifacts(reason: reason)

    let allCredentials = store.readCredentialMetadata()
    let credentials: [AutofillCredentialMetadata]
    let bestMatchId: String?

    if let preferredRecordIdentifier {
      guard let exact = allCredentials.first(where: { $0.id == preferredRecordIdentifier }) else {
        log.error("preferred credential not found reason=\(reason, privacy: .public)")
        cancelWithError(.credentialIdentityNotFound)
        return
      }
      credentials = [exact]
      bestMatchId = preferredRecordIdentifier
    } else {
      let filtered = store.filteredCredentialMetadata(
        allCredentials,
        for: serviceIdentifiers
      )
      credentials = filtered.credentials
      bestMatchId = filtered.bestMatchId
    }

    log.info(
      "showCredentialList reason=\(reason, privacy: .public) total=\(allCredentials.count, privacy: .public) filtered=\(credentials.count, privacy: .public) encryptedCacheExists=\(self.store.encryptedCredentialCacheExists(), privacy: .public)"
    )

    let rootView = CredentialListView(
      credentials: credentials,
      bestMatchId: bestMatchId,
      onSelect: { [weak self] metadata in
        self?.completeCredentialSelection(metadata)
      },
      onCancel: { [weak self] in
        log.info("user cancelled")
        self?.cancelWithError(.userCanceled)
      }
    )

    install(rootView: rootView)
  }

  private func install(rootView: CredentialListView) {
    if let hostingController {
      hostingController.rootView = rootView
      return
    }

    let host = NSHostingController(rootView: rootView)
    hostingController = host
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    log.info("host controller attached")
  }

  // MARK: - Fill completion

  private func completeCredentialSelection(_ metadata: AutofillCredentialMetadata) {
    do {
      let secret = try store.readCredentialSecret(id: metadata.id)
      let user = secret.username.isEmpty ? metadata.username : secret.username
      let credential = ASPasswordCredential(user: user, password: secret.password)
      log.info("completeCredentialSelection succeeded")
      extensionContext.completeRequest(
        withSelectedCredential: credential,
        completionHandler: nil
      )
    } catch SharedAutofillStoreError.credentialNotFound {
      log.error("completeCredentialSelection credential not found")
      cancelWithError(.credentialIdentityNotFound)
    } catch {
      log.error("completeCredentialSelection failed error=\(String(describing: type(of: error)), privacy: .public)")
      cancelWithError(.failed)
    }
  }

  // MARK: - Error helper

  private func cancelWithError(_ code: ASExtensionError.Code, message: String? = nil) {
    log.info("cancelWithError code=\(code.rawValue, privacy: .public) hasMessage=\(message != nil, privacy: .public)")
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
