import Foundation
import OSLog

private let bridgeLog = Logger(
  subsystem: "dev.camillobucciarelli.kdbxKeyVault.CredentialProviderExtension",
  category: "bridge"
)

/// macOS AutoFill v2 intentionally disables the legacy browser bridge path.
///
/// The previous implementation read a user-home bridge configuration and
/// accepted password-bearing HTTP responses from the running Flutter app. That
/// flow bypassed the App Group/Keychain model expected for the credential
/// provider extension, so it is kept as an explicit no-op until a reviewed v2
/// encrypted cache/identity-store design replaces it.
struct BridgeClient {
  func findCredentialMetadata(for url: String, limit: Int = 10) async -> [AutofillCredentialMetadata]? {
    bridgeLog.info("legacy bridge disabled urlProvided=\(!url.isEmpty, privacy: .public) limit=\(limit, privacy: .public)")
    return nil
  }
}
