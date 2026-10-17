import Foundation
import LocalAuthentication
import os

/// spec 023 FR-015 — the user proves they are present before any signature.
///
/// Every time, with no session and no reuse window. The password path has
/// its own 30-second reuse window (one login prompts once for username and
/// password); a passkey has no such pair, so there is nothing a window would
/// buy except a signature the user did not watch happen.
///
/// `.deviceOwnerAuthentication`, not `.deviceOwnerAuthenticationWithBiometrics`:
/// the passcode fallback must stay available, or a user whose Face ID failed
/// three times could not sign in at all.
enum PasskeyUserPresence {
  private static let log = Logger(
    subsystem: "dev.camillobucciarelli.keyvault",
    category: "passkey"
  )

  static func require(reason: String, completion: @escaping (Bool) -> Void) {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      // No passcode set, or the policy is unavailable in this extension. A
      // device that cannot prove presence must not sign: failing closed here
      // costs a sign-in, failing open costs the key.
      log.error("user presence unavailable code=\(error?.code ?? -1, privacy: .public)")
      DispatchQueue.main.async { completion(false) }
      return
    }

    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
      DispatchQueue.main.async { completion(success) }
    }
  }
}
