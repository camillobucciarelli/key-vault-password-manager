import Foundation
import Security

/// A pure-Swift password generator for the Credential Provider Extension process.
/// Mirrors PasswordGeneratorService defaults: 16 chars, all character sets.
struct CredentialProviderPasswordGenerator {
  private static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  private static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
  private static let digits    = Array("0123456789")
  private static let symbols   = Array("!@#$%^&*()-_=+[]{};:,.<>?")

  func generateDefault() -> String {
    let sets: [[Character]] = [
      CredentialProviderPasswordGenerator.uppercase,
      CredentialProviderPasswordGenerator.lowercase,
      CredentialProviderPasswordGenerator.digits,
      CredentialProviderPasswordGenerator.symbols,
    ]
    return generate(length: 16, sets: sets)
  }

  private func generate(length: Int, sets: [[Character]]) -> String {
    let combined = sets.flatMap { $0 }
    var chars = [Character]()

    // Guarantee one char from each set
    for set in sets {
      chars.append(secureChoice(from: set))
    }

    // Fill remaining positions
    for _ in chars.count..<length {
      chars.append(secureChoice(from: combined))
    }

    // Fisher-Yates shuffle
    for i in stride(from: chars.count - 1, through: 1, by: -1) {
      let j = secureInt(lessThan: i + 1)
      chars.swapAt(i, j)
    }

    return String(chars)
  }

  private func secureChoice<T>(from array: [T]) -> T {
    return array[secureInt(lessThan: array.count)]
  }

  private func secureInt(lessThan max: Int) -> Int {
    let limit = 256 - (256 % max)
    while true {
      var byte: UInt8 = 0
      SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
      let value = Int(byte)
      if value < limit { return value % max }
    }
  }
}
