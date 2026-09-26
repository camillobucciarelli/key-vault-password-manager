import AuthenticationServices
import CryptoKit
import Foundation
import OSLog
import Security

private let storeLog = Logger(
  subsystem: "dev.camillobucciarelli.kdbxKeyVault.CredentialProviderExtension",
  category: "store"
)

enum SharedAutofillStoreError: Error, LocalizedError {
  case appGroupUnavailable
  case keychainAccessGroupUnavailable
  case keychain(OSStatus)
  case invalidPayload(String)
  case metadataUnavailable
  case encryptedCacheUnavailable
  case encryptionFailed
  case decryptionFailed
  case credentialNotFound

  var errorDescription: String? {
    switch self {
    case .appGroupUnavailable:
      return "App Group container is not available."
    case .keychainAccessGroupUnavailable:
      return "Shared Keychain access group is not available."
    case .keychain(let status):
      return "Keychain operation failed with status \(status)."
    case .invalidPayload(let reason):
      return "Invalid AutoFill payload: \(reason)."
    case .metadataUnavailable:
      return "AutoFill metadata cache is unavailable."
    case .encryptedCacheUnavailable:
      return "Encrypted AutoFill cache is unavailable."
    case .encryptionFailed:
      return "Unable to encrypt AutoFill cache."
    case .decryptionFailed:
      return "Unable to decrypt AutoFill cache."
    case .credentialNotFound:
      return "Credential was not found in encrypted cache."
    }
  }
}

enum AutofillServiceIdentifierType: String, Codable {
  case domain
  case url
  case bundleId
}

struct AutofillServiceIdentifier: Codable, Hashable, Equatable {
  let type: AutofillServiceIdentifierType
  let value: String
}

/// Password-free routing/display metadata for Apple AutoFill v2.
///
/// This model intentionally excludes passwords and other secret fields. URLs are
/// normalized to host/origin identifiers only; full URL paths and query strings
/// are not persisted or logged.
struct AutofillCredentialMetadata: Codable, Identifiable, Equatable {
  let id: String
  let title: String
  let username: String
  let displayService: String
  let serviceIdentifiers: [AutofillServiceIdentifier]
  let updatedAtEpochMs: Int64?

  /// spec 023 — which passkeys this record holds, by site and credential id
  /// only. Enough to answer `prepareCredentialList` without unsealing
  /// anything; not enough to sign, which is the point.
  let passkeys: [AutofillPasskeyMetadata]

  /// spec 023 — whether a password exists, never what it is.
  ///
  /// Needed here because a passkey-only record must not register a password
  /// identity, and that decision is made from the metadata. Defaults to true
  /// when decoding a pre-023 file, where every record had one by
  /// construction.
  let hasPassword: Bool

  var hasPasskey: Bool { !passkeys.isEmpty }

  init(
    id: String,
    title: String,
    username: String,
    displayService: String,
    serviceIdentifiers: [AutofillServiceIdentifier],
    updatedAtEpochMs: Int64? = nil,
    passkeys: [AutofillPasskeyMetadata] = [],
    hasPassword: Bool = true
  ) {
    self.id = id
    self.title = title
    self.username = username
    self.displayService = displayService
    self.serviceIdentifiers = serviceIdentifiers
    self.updatedAtEpochMs = updatedAtEpochMs
    self.passkeys = passkeys
    self.hasPassword = hasPassword
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
    updatedAtEpochMs = try c.decodeIfPresent(Int64.self, forKey: .updatedAtEpochMs)

    // Both absent in every metadata file written before spec 023, where a
    // published record always had a password.
    passkeys = try c.decodeIfPresent([AutofillPasskeyMetadata].self, forKey: .passkeys) ?? []
    hasPassword = try c.decodeIfPresent(Bool.self, forKey: .hasPassword) ?? true

    let decodedService = try c.decodeIfPresent(String.self, forKey: .displayService)
    let legacyURL = try c.decodeIfPresent(String.self, forKey: .url)
    displayService = decodedService ?? SharedAutofillStoreNormalizer.displayService(from: legacyURL)

    if let decoded = try c.decodeIfPresent([AutofillServiceIdentifier].self, forKey: .serviceIdentifiers) {
      serviceIdentifiers = decoded
    } else if let legacyURL, let host = SharedAutofillStoreNormalizer.normalizedHost(from: legacyURL) {
      serviceIdentifiers = [AutofillServiceIdentifier(type: .domain, value: host)]
    } else {
      serviceIdentifiers = []
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(title, forKey: .title)
    try c.encode(username, forKey: .username)
    try c.encode(displayService, forKey: .displayService)
    try c.encode(serviceIdentifiers, forKey: .serviceIdentifiers)
    try c.encodeIfPresent(updatedAtEpochMs, forKey: .updatedAtEpochMs)
    if !passkeys.isEmpty {
      try c.encode(passkeys, forKey: .passkeys)
      // Written only alongside passkeys: without them the field cannot be
      // false, and an older reader defaults it to true anyway.
      try c.encode(hasPassword, forKey: .hasPassword)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case username
    case displayService
    case serviceIdentifiers
    case updatedAtEpochMs
    case passkeys
    case hasPassword
    case url
  }
}

struct AutofillMetadataCache: Codable, Equatable {
  let version: Int
  let databaseId: String
  let generatedAtEpochMs: Int64
  let entries: [AutofillCredentialMetadata]
}

struct AutofillInputServiceIdentifier {
  let type: String
  let value: String
}

/// spec 023 — the COSE algorithms a stored passkey may name.
enum AutofillPasskeyAlgorithm: String, Codable {
  case es256 = "ES256"
  case eddsa = "EdDSA"
  case rs256 = "RS256"

  /// The identifier WebAuthn uses on the wire, for the rare relying party
  /// that reads it back off the credential.
  var coseIdentifier: Int {
    switch self {
    case .es256: return -7
    case .eddsa: return -8
    case .rs256: return -257
    }
  }
}

/// spec 023 — one passkey on its way in from Dart. `privateKeyPem` is the
/// secret and must reach nothing but the sealed cache.
struct AutofillInputPasskey {
  let rpId: String
  let credentialId: String
  let userHandle: String?
  let username: String
  let privateKeyPem: String
  let algorithm: String
  let backupEligible: Bool
  let backupState: Bool
}

struct AutofillCredentialPublishEntry {
  let id: String
  let title: String
  let username: String
  let password: String
  let url: String?
  let serviceIdentifiers: [AutofillInputServiceIdentifier]
  let passkeys: [AutofillInputPasskey]

  init(
    id: String,
    title: String,
    username: String,
    password: String,
    url: String?,
    serviceIdentifiers: [AutofillInputServiceIdentifier],
    passkeys: [AutofillInputPasskey] = []
  ) {
    self.id = id
    self.title = title
    self.username = username
    self.password = password
    self.url = url
    self.serviceIdentifiers = serviceIdentifiers
    self.passkeys = passkeys
  }
}

/// spec 023 — a passkey inside the sealed cache. The PEM lives here and
/// nowhere else on the device; `AutofillPasskeyMetadata` is what the
/// plaintext metadata file gets.
struct AutofillPasskeySecret: Codable, Equatable {
  let rpId: String
  let credentialId: String
  let userHandle: String?
  let username: String
  let privateKeyPem: String
  let algorithm: AutofillPasskeyAlgorithm
  let backupEligible: Bool
  let backupState: Bool
}

/// spec 023 — what the plaintext metadata may say about a passkey: which
/// site it belongs to and which credential it is. Never the key, never the
/// user handle (which is an account identifier at the relying party).
struct AutofillPasskeyMetadata: Codable, Equatable {
  let rpId: String
  let credentialId: String
}

extension AutofillPasskeySecret {
  /// Validates one passkey arriving from Dart. Anything the extension could
  /// not sign with is dropped rather than sealed: a key on the device that
  /// can never answer a request is a secret held for nothing.
  init?(input: AutofillInputPasskey) {
    let rpId = input.rpId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let credentialId = input.credentialId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rpId.isEmpty,
          rpId.count <= 253,
          !credentialId.isEmpty,
          Data(base64URLEncoded: credentialId) != nil,
          !input.privateKeyPem.isEmpty,
          let algorithm = AutofillPasskeyAlgorithm(rawValue: input.algorithm) else {
      return nil
    }
    let userHandle = input.userHandle?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.init(
      rpId: rpId,
      credentialId: credentialId,
      userHandle: (userHandle?.isEmpty ?? true) ? nil : userHandle,
      username: String(input.username.prefix(512)),
      privateKeyPem: input.privateKeyPem,
      algorithm: algorithm,
      // WebAuthn forbids BS without BE: a record claiming "backed up but not
      // eligible" would sign a flag byte relying parties reject.
      backupEligible: input.backupEligible,
      backupState: input.backupEligible && input.backupState
    )
  }
}

extension Data {
  /// base64url, padded or not — KeePassXC omits the padding.
  init?(base64URLEncoded value: String) {
    var text = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = text.count % 4
    if remainder > 0 {
      text += String(repeating: "=", count: 4 - remainder)
    }
    guard let data = Data(base64Encoded: text) else { return nil }
    self = data
  }

  /// base64url without padding, which is how every WebAuthn field is spelled.
  var base64URLEncodedString: String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

struct AutofillCredentialSecret: Codable, Equatable {
  let id: String
  let username: String
  let password: String
  let passkeys: [AutofillPasskeySecret]

  init(
    id: String,
    username: String,
    password: String,
    passkeys: [AutofillPasskeySecret] = []
  ) {
    self.id = id
    self.username = username
    self.password = password
    self.passkeys = passkeys
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
    password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
    // Absent in every cache written before spec 023.
    passkeys = try c.decodeIfPresent([AutofillPasskeySecret].self, forKey: .passkeys) ?? []
  }
}

struct AutofillPendingAssociation: Codable, Equatable, Identifiable {
  let id: String
  let databaseId: String
  let entryId: String
  let serviceIdentifierType: String
  let serviceIdentifierValue: String
  let displayService: String
  let createdAtEpochMs: Int64
  let platform: String?

  var dictionary: [String: Any] {
    var value: [String: Any] = [
      "id": id,
      "databaseId": databaseId,
      "entryId": entryId,
      "serviceIdentifierType": serviceIdentifierType,
      "serviceIdentifierValue": serviceIdentifierValue,
      "displayService": displayService,
      "createdAtEpochMs": createdAtEpochMs,
    ]
    if let platform {
      value["platform"] = platform
    }
    return value
  }
}

private struct AutofillSecretCache: Codable {
  let version: Int
  let databaseId: String
  let generatedAtEpochMs: Int64
  let entries: [AutofillCredentialSecret]
}

private struct AutofillEncryptedCacheEnvelope: Codable {
  let version: Int
  let algorithm: String
  let keyId: String
  let databaseId: String
  let generatedAtEpochMs: Int64
  let sealedCombined: String
}

struct AutofillPublishOutcome {
  let publishedCount: Int
  let skippedCount: Int
  let identityCount: Int
  let identityStoreSynced: Bool
  /// spec 023 — how many passkeys were sealed, across every record.
  let passkeyPublishedCount: Int
  let warnings: [String]

  init(
    publishedCount: Int,
    skippedCount: Int,
    identityCount: Int,
    identityStoreSynced: Bool,
    passkeyPublishedCount: Int = 0,
    warnings: [String]
  ) {
    self.publishedCount = publishedCount
    self.skippedCount = skippedCount
    self.identityCount = identityCount
    self.identityStoreSynced = identityStoreSynced
    self.passkeyPublishedCount = passkeyPublishedCount
    self.warnings = warnings
  }

  var dictionary: [String: Any] {
    [
      "publishedCount": publishedCount,
      "skippedCount": skippedCount,
      "identityCount": identityCount,
      "identityStoreSynced": identityStoreSynced,
      "passkeyPublishedCount": passkeyPublishedCount,
      "warnings": warnings,
    ]
  }
}

struct AutofillClearOutcome {
  let cleared: Bool
  let identityStoreCleared: Bool
  let keychainKeyCleared: Bool
  let warnings: [String]

  var dictionary: [String: Any] {
    [
      "cleared": cleared,
      "identityStoreCleared": identityStoreCleared,
      "keychainKeyCleared": keychainKeyCleared,
      "warnings": warnings,
    ]
  }
}

struct AutofillStoreStatus {
  let appGroupAvailable: Bool
  let keychainAccessGroupAvailable: Bool
  let metadataCount: Int
  let encryptedCacheAvailable: Bool
  let cacheAvailable: Bool
  let databaseId: String?
  let generatedAtEpochMs: Int64?

  var dictionary: [String: Any] {
    var value: [String: Any] = [
      "version": SharedAutofillPaths.cacheVersion,
      "appGroupAvailable": appGroupAvailable,
      "keychainAccessGroupAvailable": keychainAccessGroupAvailable,
      "metadataCount": metadataCount,
      "encryptedCacheAvailable": encryptedCacheAvailable,
      "cacheAvailable": cacheAvailable,
    ]
    if let databaseId {
      value["databaseId"] = databaseId
    }
    if let generatedAtEpochMs {
      value["generatedAtEpochMs"] = generatedAtEpochMs
    }
    return value
  }
}

/// App Group and Keychain constants used by the Apple AutoFill integration.
///
/// v1 plaintext files are never read. They are removed best-effort whenever the
/// app/extension touches this store.
enum SharedAutofillPaths {
  static let appGroupId = "group.dev.camillobucciarelli.kdbxKeyVault"
  static let keychainAccessGroupSuffix = "dev.camillobucciarelli.kdbxKeyVault"

  static let cacheVersion = 2
  static let metadataFileName = "autofill_metadata_v2.json"
  static let encryptedCacheFileName = "autofill_cache_v2.sealed.json"
  static let pendingAssociationsFileName = "autofill_pending_associations_v2.json"
  static let keychainService = "dev.camillobucciarelli.keyvault.apple_autofill_v2"
  static let keychainAccount = "cache-key"
  static let keyId = "apple-autofill-v2-cache-key"

  static let legacyPlaintextFileNames = [
    "autofill_entries.json",
    "pending_autofill_saves.json",
  ]
  static let legacyDefaultsKeys = [
    "autofill_entries_json",
    "autofill_last_sync_epoch_ms",
    "pending_autofill_saves",
  ]

  static func containerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
  }

  static func metadataURL() -> URL? {
    containerURL()?.appendingPathComponent(metadataFileName)
  }

  static func encryptedCacheURL() -> URL? {
    containerURL()?.appendingPathComponent(encryptedCacheFileName)
  }

  static func pendingAssociationsURL() -> URL? {
    containerURL()?.appendingPathComponent(pendingAssociationsFileName)
  }
}

final class SharedAutofillStore {
  private let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private let jsonDecoder = JSONDecoder()

  init() {
    wipeLegacyPlaintextArtifacts(reason: "store init")
  }

  func publishCredentials(
    databaseId: String,
    entries: [AutofillCredentialPublishEntry],
    completion: @escaping (Result<AutofillPublishOutcome, Error>) -> Void
  ) {
    wipeLegacyPlaintextArtifacts(reason: "publish")

    do {
      let prepared = try prepareCache(databaseId: databaseId, entries: entries)

      guard !prepared.metadata.entries.isEmpty else {
        try removeCacheFiles()
        let keyCleared = deleteKeyBestEffort()
        replaceCredentialIdentities([]) { identitySynced, warning in
          var warnings = prepared.warnings
          if !keyCleared { warnings.append("keychain_key_not_cleared") }
          if let warning { warnings.append(warning) }
          completion(.success(AutofillPublishOutcome(
            publishedCount: 0,
            skippedCount: prepared.skippedCount,
            identityCount: 0,
            identityStoreSynced: identitySynced,
            passkeyPublishedCount: 0,
            warnings: warnings
          )))
        }
        return
      }

      try replaceEncryptedCache(
        metadataData: prepared.metadataData,
        envelopeData: prepared.envelopeData,
        keyData: prepared.keyData
      )

      replaceCredentialIdentities(prepared.identities) { identitySynced, warning in
        var warnings = prepared.warnings
        if let warning { warnings.append(warning) }
        completion(.success(AutofillPublishOutcome(
          publishedCount: prepared.metadata.entries.count,
          skippedCount: prepared.skippedCount,
          identityCount: prepared.identities.count,
          identityStoreSynced: identitySynced,
          passkeyPublishedCount: prepared.passkeyPublishedCount,
          warnings: warnings
        )))
      }
    } catch {
      removeCacheFilesBestEffort()
      _ = deleteKeyBestEffort()
      storeLog.error("publishCredentials failed error=\(String(describing: type(of: error)), privacy: .public)")
      completion(.failure(error))
    }
  }

  func clearCredentials(
    databaseId: String?,
    completion: @escaping (Result<AutofillClearOutcome, Error>) -> Void
  ) {
    wipeLegacyPlaintextArtifacts(reason: "clear")

    let pendingAssociationsCleared = clearPendingAssociationsBestEffort()

    let currentDatabaseId = readMetadataCache()?.databaseId
    if let databaseId,
       let currentDatabaseId,
       currentDatabaseId != databaseId {
      storeLog.info("clearCredentials skipped: database mismatch")
      var warnings = ["database_id_mismatch"]
      if !pendingAssociationsCleared { warnings.append("pending_associations_not_cleared") }
      completion(.success(AutofillClearOutcome(
        cleared: false,
        identityStoreCleared: false,
        keychainKeyCleared: false,
        warnings: warnings
      )))
      return
    }

    do {
      try removeCacheFiles()
      let keyCleared = deleteKeyBestEffort()
      replaceCredentialIdentities([]) { identitySynced, warning in
        var warnings: [String] = []
        if !pendingAssociationsCleared { warnings.append("pending_associations_not_cleared") }
        if !keyCleared { warnings.append("keychain_key_not_cleared") }
        if let warning { warnings.append(warning) }
        completion(.success(AutofillClearOutcome(
          cleared: true,
          identityStoreCleared: identitySynced,
          keychainKeyCleared: keyCleared,
          warnings: warnings
        )))
      }
    } catch {
      storeLog.error("clearCredentials failed error=\(String(describing: type(of: error)), privacy: .public)")
      completion(.failure(error))
    }
  }

  func status() -> AutofillStoreStatus {
    wipeLegacyPlaintextArtifacts(reason: "status")
    let metadata = readMetadataCache()
    let encryptedExists = encryptedCredentialCacheExists()
    let keychainGroupAvailable = canUseKeychainCache()
    return AutofillStoreStatus(
      appGroupAvailable: SharedAutofillPaths.containerURL() != nil,
      keychainAccessGroupAvailable: keychainGroupAvailable,
      metadataCount: metadata?.entries.count ?? 0,
      encryptedCacheAvailable: encryptedExists,
      cacheAvailable: metadata != nil && encryptedExists && keychainGroupAvailable,
      databaseId: metadata?.databaseId,
      generatedAtEpochMs: metadata?.generatedAtEpochMs
    )
  }

  /// Reads password-free metadata only.
  func readCredentialMetadata() -> [AutofillCredentialMetadata] {
    readMetadataCache()?.entries ?? []
  }

  /// Reads pending entry-to-service associations. Contains metadata only, never passwords.
  func readPendingAssociations() -> [AutofillPendingAssociation] {
    wipeLegacyPlaintextArtifacts(reason: "pending associations read")
    return readPendingAssociationsFile()
  }

  @discardableResult
  func clearPendingAssociations(ids: [String]? = nil) throws -> Int {
    wipeLegacyPlaintextArtifacts(reason: "pending associations clear")
    guard let url = SharedAutofillPaths.pendingAssociationsURL() else {
      throw SharedAutofillStoreError.appGroupUnavailable
    }

    guard let ids else {
      let associations = (try? loadPendingAssociations()) ?? []
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      storeLog.info("pending associations cleared all count=\(associations.count, privacy: .public)")
      return associations.count
    }

    let associations = try loadPendingAssociations()
    guard !associations.isEmpty else { return 0 }

    let idsToClear = Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    guard !idsToClear.isEmpty else { return 0 }

    let remaining = associations.filter { !idsToClear.contains($0.id) }
    let clearedCount = associations.count - remaining.count
    guard clearedCount > 0 else { return 0 }

    if remaining.isEmpty {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    } else {
      try writePendingAssociations(remaining)
    }
    storeLog.info("pending associations cleared by id count=\(clearedCount, privacy: .public)")
    return clearedCount
  }

  func savePendingAssociation(
    for metadata: AutofillCredentialMetadata,
    requestedServiceIdentifiers: [ASCredentialServiceIdentifier]
  ) {
    wipeLegacyPlaintextArtifacts(reason: "pending association save")

    guard let pending = makePendingAssociation(
      for: metadata,
      requestedServiceIdentifiers: requestedServiceIdentifiers
    ) else {
      storeLog.info("pending association skipped missing normalized target")
      return
    }

    do {
      var associations = try loadPendingAssociations()
      associations.removeAll {
        $0.databaseId == pending.databaseId &&
          $0.entryId == pending.entryId &&
          $0.serviceIdentifierType == pending.serviceIdentifierType &&
          $0.serviceIdentifierValue == pending.serviceIdentifierValue
      }
      associations.append(pending)
      if associations.count > 200 {
        associations = Array(associations.suffix(200))
      }
      try writePendingAssociations(associations)
      storeLog.info("pending association saved count=\(associations.count, privacy: .public)")
    } catch {
      storeLog.error("pending association save failed error=\(String(describing: type(of: error)), privacy: .public)")
    }
  }

  func encryptedCredentialCacheExists() -> Bool {
    guard let url = SharedAutofillPaths.encryptedCacheURL() else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  func readCredentialSecret(id: String) throws -> AutofillCredentialSecret {
    wipeLegacyPlaintextArtifacts(reason: "decrypt")

    guard let metadataURL = SharedAutofillPaths.metadataURL(),
          let encryptedURL = SharedAutofillPaths.encryptedCacheURL() else {
      throw SharedAutofillStoreError.appGroupUnavailable
    }
    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
      throw SharedAutofillStoreError.metadataUnavailable
    }
    guard FileManager.default.fileExists(atPath: encryptedURL.path) else {
      throw SharedAutofillStoreError.encryptedCacheUnavailable
    }

    do {
      let metadataData = try Data(contentsOf: metadataURL)
      let metadata = try decodeMetadataCache(from: metadataData)
      let envelopeData = try Data(contentsOf: encryptedURL)
      let envelope = try jsonDecoder.decode(AutofillEncryptedCacheEnvelope.self, from: envelopeData)

      guard envelope.version == SharedAutofillPaths.cacheVersion,
            envelope.databaseId == metadata.databaseId,
            envelope.algorithm == "AES.GCM.256" else {
        throw SharedAutofillStoreError.decryptionFailed
      }
      guard let combined = Data(base64Encoded: envelope.sealedCombined) else {
        throw SharedAutofillStoreError.decryptionFailed
      }

      let keyData = try readKeyData()
      let sealedBox = try AES.GCM.SealedBox(combined: combined)
      let plaintext = try AES.GCM.open(
        sealedBox,
        using: SymmetricKey(data: keyData),
        authenticating: metadataData
      )
      let secretCache = try jsonDecoder.decode(AutofillSecretCache.self, from: plaintext)

      guard secretCache.version == SharedAutofillPaths.cacheVersion,
            secretCache.databaseId == metadata.databaseId else {
        throw SharedAutofillStoreError.decryptionFailed
      }
      guard let secret = secretCache.entries.first(where: { $0.id == id }) else {
        throw SharedAutofillStoreError.credentialNotFound
      }
      return secret
    } catch let error as SharedAutofillStoreError {
      throw error
    } catch {
      storeLog.error("readCredentialSecret failed error=\(String(describing: type(of: error)), privacy: .public)")
      throw SharedAutofillStoreError.decryptionFailed
    }
  }

  func filteredCredentialMetadata(
    for serviceIdentifiers: [ASCredentialServiceIdentifier]
  ) -> (credentials: [AutofillCredentialMetadata], bestMatchId: String?) {
    let entries = readCredentialMetadata()
    return filteredCredentialMetadata(entries, for: serviceIdentifiers)
  }

  func filteredCredentialMetadata(
    _ entries: [AutofillCredentialMetadata],
    for serviceIdentifiers: [ASCredentialServiceIdentifier]
  ) -> (credentials: [AutofillCredentialMetadata], bestMatchId: String?) {
    let requested = SharedAutofillStoreNormalizer.normalizedRequestedIdentifiers(serviceIdentifiers)
    guard !requested.isEmpty else {
      return (entries.sortedForDisplay(), nil)
    }

    let scored = entries.compactMap { entry -> (AutofillCredentialMetadata, Int)? in
      let score = SharedAutofillStoreNormalizer.matchScore(
        entryIdentifiers: entry.serviceIdentifiers,
        requestedIdentifiers: requested
      )
      guard score > 0 else { return nil }
      return (entry, score)
    }

    let sorted = scored.sorted { lhs, rhs in
      if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
      return lhs.0.sortKey < rhs.0.sortKey
    }.map(\.0)

    return (sorted, sorted.first?.id)
  }

  func wipeLegacyPlaintextArtifacts(reason: String) {
    guard let containerURL = SharedAutofillPaths.containerURL() else {
      storeLog.error("legacy cleanup skipped: App Group not accessible reason=\(reason, privacy: .public)")
      return
    }

    for fileName in SharedAutofillPaths.legacyPlaintextFileNames {
      let url = containerURL.appendingPathComponent(fileName)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      do {
        try FileManager.default.removeItem(at: url)
        storeLog.info("legacy plaintext file removed name=\(fileName, privacy: .public) reason=\(reason, privacy: .public)")
      } catch {
        storeLog.error("legacy plaintext removal failed name=\(fileName, privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)")
      }
    }

    if let defaults = UserDefaults(suiteName: SharedAutofillPaths.appGroupId) {
      for key in SharedAutofillPaths.legacyDefaultsKeys {
        defaults.removeObject(forKey: key)
      }
    }
  }

  // MARK: - Publish pipeline

  private struct PreparedCache {
    let metadata: AutofillMetadataCache
    let metadataData: Data
    let envelopeData: Data
    let keyData: Data
    let identities: [ASCredentialIdentity]
    let skippedCount: Int
    let passkeyPublishedCount: Int
    let warnings: [String]
  }

  private func prepareCache(
    databaseId rawDatabaseId: String,
    entries rawEntries: [AutofillCredentialPublishEntry]
  ) throws -> PreparedCache {
    let databaseId = rawDatabaseId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !databaseId.isEmpty else {
      throw SharedAutofillStoreError.invalidPayload("databaseId is required")
    }
    guard rawEntries.count <= 10_000 else {
      throw SharedAutofillStoreError.invalidPayload("entries exceeds maximum")
    }

    let generatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    var seenIds = Set<String>()
    var metadataEntries: [AutofillCredentialMetadata] = []
    var secretEntries: [AutofillCredentialSecret] = []
    var skippedCount = 0
    var warnings = Set<String>()

    for entry in rawEntries {
      let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty else {
        skippedCount += 1
        warnings.insert("entry_without_id_skipped")
        continue
      }
      guard !seenIds.contains(id) else {
        skippedCount += 1
        warnings.insert("duplicate_entry_id_skipped")
        continue
      }
      // spec 023: a passkey-only record has nothing to fill but something to
      // sign with, so an empty password no longer disqualifies it. A record
      // with neither is still nothing to publish.
      let passkeys = entry.passkeys.compactMap(AutofillPasskeySecret.init(input:))
      guard !entry.password.isEmpty || !passkeys.isEmpty else {
        skippedCount += 1
        warnings.insert("entry_without_password_skipped")
        continue
      }

      let normalizedIdentifiers = SharedAutofillStoreNormalizer.normalizedServiceIdentifiers(
        url: entry.url,
        provided: entry.serviceIdentifiers
      )
      if normalizedIdentifiers.contains(where: { $0.type == .bundleId }) {
        warnings.insert("bundle_id_identifiers_not_registered_on_current_os")
      }

      let username = entry.username.trimmedForMetadata(maxLength: 512)
      let rawTitle = entry.title.trimmedForMetadata(maxLength: 512)
      let displayService = SharedAutofillStoreNormalizer.displayService(from: normalizedIdentifiers)
      let title = rawTitle.isEmpty ? (displayService.isEmpty ? "Untitled" : displayService) : rawTitle

      seenIds.insert(id)
      metadataEntries.append(AutofillCredentialMetadata(
        id: id,
        title: title,
        username: username,
        displayService: displayService,
        serviceIdentifiers: normalizedIdentifiers,
        updatedAtEpochMs: generatedAt,
        passkeys: passkeys.map {
          AutofillPasskeyMetadata(rpId: $0.rpId, credentialId: $0.credentialId)
        },
        hasPassword: !entry.password.isEmpty
      ))
      secretEntries.append(AutofillCredentialSecret(
        id: id,
        username: username,
        password: entry.password,
        passkeys: passkeys
      ))
    }

    let metadata = AutofillMetadataCache(
      version: SharedAutofillPaths.cacheVersion,
      databaseId: databaseId,
      generatedAtEpochMs: generatedAt,
      entries: metadataEntries.sortedForDisplay()
    )
    let metadataData = try jsonEncoder.encode(metadata)
    let secretCache = AutofillSecretCache(
      version: SharedAutofillPaths.cacheVersion,
      databaseId: databaseId,
      generatedAtEpochMs: generatedAt,
      entries: secretEntries
    )
    let secretData = try jsonEncoder.encode(secretCache)
    let keyData = try makeRandomKeyData()
    let sealed = try AES.GCM.seal(
      secretData,
      using: SymmetricKey(data: keyData),
      authenticating: metadataData
    )
    guard let combined = sealed.combined else {
      throw SharedAutofillStoreError.encryptionFailed
    }
    let envelope = AutofillEncryptedCacheEnvelope(
      version: SharedAutofillPaths.cacheVersion,
      algorithm: "AES.GCM.256",
      keyId: SharedAutofillPaths.keyId,
      databaseId: databaseId,
      generatedAtEpochMs: generatedAt,
      sealedCombined: combined.base64EncodedString()
    )
    let envelopeData = try jsonEncoder.encode(envelope)
    let identities = makeCredentialIdentities(for: metadata.entries)

    return PreparedCache(
      metadata: metadata,
      metadataData: metadataData,
      envelopeData: envelopeData,
      keyData: keyData,
      identities: identities,
      skippedCount: skippedCount,
      passkeyPublishedCount: metadata.entries.reduce(0) { $0 + $1.passkeys.count },
      warnings: Array(warnings).sorted()
    )
  }

  private func replaceEncryptedCache(
    metadataData: Data,
    envelopeData: Data,
    keyData: Data
  ) throws {
    guard SharedAutofillPaths.containerURL() != nil,
          let metadataURL = SharedAutofillPaths.metadataURL(),
          let encryptedURL = SharedAutofillPaths.encryptedCacheURL() else {
      throw SharedAutofillStoreError.appGroupUnavailable
    }

    try removeCacheFiles()
    try storeKeyData(keyData)

    do {
      try writeProtected(envelopeData, to: encryptedURL)
      try writeProtected(metadataData, to: metadataURL)
      storeLog.info("encrypted cache replaced metadataBytes=\(metadataData.count, privacy: .public) sealedBytes=\(envelopeData.count, privacy: .public)")
    } catch {
      removeCacheFilesBestEffort()
      _ = deleteKeyBestEffort()
      throw error
    }
  }

  /// Password identities for records that have a password, plus (spec 023) a
  /// passkey identity per stored passkey.
  ///
  /// A record that holds only a passkey registers NO password identity: it
  /// has nothing to fill, and offering it in the QuickType bar as a password
  /// would put an empty field behind a suggestion the user tapped.
  ///
  /// The passkey identity's service identifier is the relying party id the
  /// passkey itself names, not the record's URL. They are usually the same,
  /// but the passkey's own rpId is the one the system matches a request
  /// against, so a record whose URL drifted still answers.
  private func makeCredentialIdentities(
    for entries: [AutofillCredentialMetadata]
  ) -> [ASCredentialIdentity] {
    var identities: [ASCredentialIdentity] = []
    var seen = Set<String>()

    for (index, entry) in entries.enumerated() {
      let rank = max(0, 10_000 - index)

      if entry.hasPassword {
        for identifier in entry.serviceIdentifiers {
          guard identifier.type != .bundleId else { continue }
          let key = "\(identifier.type.rawValue):\(identifier.value):\(entry.id)"
          guard !seen.contains(key) else { continue }
          seen.insert(key)

          let serviceType: ASCredentialServiceIdentifier.IdentifierType =
            identifier.type == .domain ? .domain : .URL
          let service = ASCredentialServiceIdentifier(
            identifier: identifier.value,
            type: serviceType
          )
          let identity = ASPasswordCredentialIdentity(
            serviceIdentifier: service,
            user: entry.username.isEmpty ? entry.title : entry.username,
            recordIdentifier: entry.id
          )
          identity.rank = rank
          identities.append(identity)
        }
      }

      for passkey in entry.passkeys {
        guard let credentialData = Data(base64URLEncoded: passkey.credentialId) else {
          continue
        }
        let key = "passkey:\(passkey.rpId):\(passkey.credentialId)"
        guard !seen.contains(key) else { continue }
        seen.insert(key)

        // `userHandle` is required by the initializer but is account material
        // at the relying party, and the plaintext metadata deliberately does
        // not carry it. The record id stands in: the system uses it to
        // correlate the identity with the request, and the real handle is
        // read out of the sealed cache when the assertion is built.
        let identity = ASPasskeyCredentialIdentity(
          relyingPartyIdentifier: passkey.rpId,
          userName: entry.username.isEmpty ? entry.title : entry.username,
          credentialID: credentialData,
          userHandle: Data(entry.id.utf8),
          recordIdentifier: entry.id
        )
        identity.rank = rank
        identities.append(identity)
      }
    }

    return identities
  }

  private func replaceCredentialIdentities(
    _ identities: [ASCredentialIdentity],
    completion: @escaping (Bool, String?) -> Void
  ) {
    ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities) { success, error in
      if success {
        storeLog.info("identity store replaced count=\(identities.count, privacy: .public)")
        completion(true, nil)
      } else {
        storeLog.error("identity store replace failed count=\(identities.count, privacy: .public) error=\(String(describing: error.map { type(of: $0) }), privacy: .public)")
        completion(false, "identity_store_sync_failed")
      }
    }
  }

  // MARK: - Pending associations

  private func makePendingAssociation(
    for metadata: AutofillCredentialMetadata,
    requestedServiceIdentifiers: [ASCredentialServiceIdentifier]
  ) -> AutofillPendingAssociation? {
    guard let metadataCache = readMetadataCache() else { return nil }
    let databaseId = metadataCache.databaseId.trimmingCharacters(in: .whitespacesAndNewlines)
    let entryId = metadata.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !databaseId.isEmpty, !entryId.isEmpty else { return nil }

    let requested = SharedAutofillStoreNormalizer.normalizedRequestedIdentifiers(
      requestedServiceIdentifiers
    )
    guard let target = requested.first,
          !target.value.isEmpty else {
      return nil
    }

    let displayService = SharedAutofillStoreNormalizer.displayService(from: [target])
    return AutofillPendingAssociation(
      id: UUID().uuidString,
      databaseId: databaseId,
      entryId: entryId,
      serviceIdentifierType: target.type.rawValue,
      serviceIdentifierValue: target.value,
      displayService: displayService.isEmpty ? target.value : displayService,
      createdAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
      platform: currentPlatform
    )
  }

  private func readPendingAssociationsFile() -> [AutofillPendingAssociation] {
    do {
      return try loadPendingAssociations()
    } catch {
      storeLog.error("pending associations read failed error=\(String(describing: type(of: error)), privacy: .public)")
      return []
    }
  }

  private func loadPendingAssociations() throws -> [AutofillPendingAssociation] {
    guard let url = SharedAutofillPaths.pendingAssociationsURL() else {
      throw SharedAutofillStoreError.appGroupUnavailable
    }
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    return try jsonDecoder.decode([AutofillPendingAssociation].self, from: data)
  }

  private func writePendingAssociations(_ associations: [AutofillPendingAssociation]) throws {
    guard let url = SharedAutofillPaths.pendingAssociationsURL() else {
      throw SharedAutofillStoreError.appGroupUnavailable
    }
    let data = try jsonEncoder.encode(associations)
    try writeProtected(data, to: url)
  }

  private func clearPendingAssociationsBestEffort() -> Bool {
    do {
      _ = try clearPendingAssociations(ids: nil)
      return true
    } catch {
      storeLog.error("pending associations clear failed error=\(String(describing: type(of: error)), privacy: .public)")
      return false
    }
  }

  private var currentPlatform: String {
#if os(macOS)
    return "macos"
#else
    return "ios"
#endif
  }

  // MARK: - File IO

  private func readMetadataCache() -> AutofillMetadataCache? {
    wipeLegacyPlaintextArtifacts(reason: "metadata read")

    guard let url = SharedAutofillPaths.metadataURL() else {
      storeLog.error("readMetadataCache: containerURL nil")
      return nil
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
      storeLog.info("readMetadataCache: no v2 metadata cache")
      return nil
    }

    do {
      let data = try Data(contentsOf: url)
      let decoded = try decodeMetadataCache(from: data)
      storeLog.info("readMetadataCache: decoded count=\(decoded.entries.count, privacy: .public)")
      return decoded
    } catch {
      storeLog.error("readMetadataCache: read/decode failed error=\(String(describing: type(of: error)), privacy: .public)")
      return nil
    }
  }

  private func decodeMetadataCache(from data: Data) throws -> AutofillMetadataCache {
    if let cache = try? jsonDecoder.decode(AutofillMetadataCache.self, from: data) {
      return cache
    }

    // Accept the password-free v2 scaffolding array shape from pre-encrypted QA
    // builds. v1 plaintext files are never read.
    let entries = try jsonDecoder.decode([AutofillCredentialMetadata].self, from: data)
    return AutofillMetadataCache(
      version: SharedAutofillPaths.cacheVersion,
      databaseId: "",
      generatedAtEpochMs: 0,
      entries: entries
    )
  }

  private func writeProtected(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: [.atomic])
#if os(iOS)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: url.path
    )
#endif
  }

  private func removeCacheFiles() throws {
    guard let metadataURL = SharedAutofillPaths.metadataURL(),
          let encryptedURL = SharedAutofillPaths.encryptedCacheURL() else {
      throw SharedAutofillStoreError.appGroupUnavailable
    }

    for url in [metadataURL, encryptedURL] {
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      try FileManager.default.removeItem(at: url)
    }
  }

  private func removeCacheFilesBestEffort() {
    do {
      try removeCacheFiles()
    } catch {
      storeLog.error("removeCacheFilesBestEffort failed error=\(String(describing: type(of: error)), privacy: .public)")
    }
  }

  // MARK: - Keychain

  private func makeRandomKeyData() throws -> Data {
    var data = Data(count: 32)
    let status = data.withUnsafeMutableBytes { buffer -> OSStatus in
      guard let baseAddress = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
    }
    guard status == errSecSuccess else {
      throw SharedAutofillStoreError.keychain(status)
    }
    return data
  }

  private func resolveKeychainAccessGroup() -> String? {
#if os(macOS)
    guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault) else {
      return nil
    }

    var error: Unmanaged<CFError>?
    guard let value = SecTaskCopyValueForEntitlement(
      task,
      "keychain-access-groups" as CFString,
      &error
    ) else {
      return nil
    }

    let groups: [String]
    if let stringGroups = value as? [String] {
      groups = stringGroups
    } else if let anyGroups = value as? [Any] {
      groups = anyGroups.compactMap { $0 as? String }
    } else {
      groups = []
    }

    return groups.first { group in
      group == SharedAutofillPaths.keychainAccessGroupSuffix ||
        group.hasSuffix(".\(SharedAutofillPaths.keychainAccessGroupSuffix)")
    }
#else
    // SecTask entitlement introspection is not available to iOS Swift targets.
    // With a single shared keychain-access-groups entitlement, Keychain Services
    // uses that default group when kSecAttrAccessGroup is omitted.
    return nil
#endif
  }

  private func canUseKeychainCache() -> Bool {
#if os(macOS)
    return resolveKeychainAccessGroup() != nil
#else
    return true
#endif
  }

  private func keychainBaseQuery(accessGroup: String?) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: SharedAutofillPaths.keychainService,
      kSecAttrAccount as String: SharedAutofillPaths.keychainAccount,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  private func storeKeyData(_ keyData: Data) throws {
    let accessGroup = resolveKeychainAccessGroup()
    var query = keychainBaseQuery(accessGroup: accessGroup)
    SecItemDelete(query as CFDictionary)

    query[kSecValueData as String] = keyData
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw SharedAutofillStoreError.keychain(status)
    }
  }

  private func readKeyData() throws -> Data {
    let accessGroup = resolveKeychainAccessGroup()
    var query = keychainBaseQuery(accessGroup: accessGroup)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      throw SharedAutofillStoreError.keychain(status)
    }
    return data
  }

  private func deleteKeyBestEffort() -> Bool {
    let accessGroup = resolveKeychainAccessGroup()
    let status = SecItemDelete(keychainBaseQuery(accessGroup: accessGroup) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}

private enum SharedAutofillStoreNormalizer {
  static func normalizedServiceIdentifiers(
    url: String?,
    provided: [AutofillInputServiceIdentifier]
  ) -> [AutofillServiceIdentifier] {
    var identifiers: [AutofillServiceIdentifier] = []
    var seen = Set<AutofillServiceIdentifier>()

    func append(_ identifier: AutofillServiceIdentifier?) {
      guard let identifier, !seen.contains(identifier) else { return }
      seen.insert(identifier)
      identifiers.append(identifier)
    }

    if let url {
      if let origin = normalizedOrigin(from: url) {
        append(AutofillServiceIdentifier(type: .url, value: origin))
      }
      if let host = normalizedHost(from: url) {
        append(AutofillServiceIdentifier(type: .domain, value: host))
      }
    }

    for raw in provided {
      switch raw.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "domain":
        append(normalizedHost(from: raw.value).map {
          AutofillServiceIdentifier(type: .domain, value: $0)
        })
      case "url":
        if let origin = normalizedOrigin(from: raw.value) {
          append(AutofillServiceIdentifier(type: .url, value: origin))
        }
        if let host = normalizedHost(from: raw.value) {
          append(AutofillServiceIdentifier(type: .domain, value: host))
        }
      case "bundleid":
        append(normalizedBundleId(raw.value).map {
          AutofillServiceIdentifier(type: .bundleId, value: $0)
        })
      default:
        continue
      }
    }

    return identifiers
  }

  static func normalizedRequestedIdentifiers(
    _ serviceIdentifiers: [ASCredentialServiceIdentifier]
  ) -> [AutofillServiceIdentifier] {
    var identifiers: [AutofillServiceIdentifier] = []
    var seen = Set<AutofillServiceIdentifier>()

    func append(_ identifier: AutofillServiceIdentifier?) {
      guard let identifier, !seen.contains(identifier) else { return }
      seen.insert(identifier)
      identifiers.append(identifier)
    }

    for service in serviceIdentifiers {
      switch service.type {
      case .domain:
        append(normalizedHost(from: service.identifier).map {
          AutofillServiceIdentifier(type: .domain, value: $0)
        })
      case .URL:
        if let origin = normalizedOrigin(from: service.identifier) {
          append(AutofillServiceIdentifier(type: .url, value: origin))
        }
        if let host = normalizedHost(from: service.identifier) {
          append(AutofillServiceIdentifier(type: .domain, value: host))
        }
      case .app:
        append(normalizedBundleId(service.identifier).map {
          AutofillServiceIdentifier(type: .bundleId, value: $0)
        })
      @unknown default:
        continue
      }
    }

    return identifiers
  }

  static func normalizedHost(from rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    let candidate: String
    if value.contains("://") {
      candidate = value
    } else if value.hasPrefix("//") {
      candidate = "https:\(value)"
    } else {
      candidate = "https://\(value)"
    }

    let host = URLComponents(string: candidate)?.host ?? value.split(separator: "/").first.map(String.init)
    return cleanHost(host)
  }

  static func normalizedOrigin(from rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    let candidate: String
    if value.contains("://") {
      candidate = value
    } else if value.hasPrefix("//") {
      candidate = "https:\(value)"
    } else {
      candidate = "https://\(value)"
    }

    guard var components = URLComponents(string: candidate),
          let host = cleanHost(components.host) else {
      return nil
    }
    let scheme = (components.scheme?.lowercased() == "http") ? "http" : "https"
    components.scheme = scheme
    components.user = nil
    components.password = nil
    components.host = host
    components.path = ""
    components.query = nil
    components.fragment = nil

    if let port = components.port {
      return "\(scheme)://\(host):\(port)"
    }
    return "\(scheme)://\(host)"
  }

  static func normalizedBundleId(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty, value.count <= 255 else { return nil }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
    guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    return value
  }

  static func displayService(from identifiers: [AutofillServiceIdentifier]) -> String {
    if let domain = identifiers.first(where: { $0.type == .domain })?.value {
      return domain
    }
    if let url = identifiers.first(where: { $0.type == .url })?.value,
       let host = normalizedHost(from: url) {
      return host
    }
    if let bundleId = identifiers.first(where: { $0.type == .bundleId })?.value {
      return bundleId
    }
    return ""
  }

  static func displayService(from legacyURL: String?) -> String {
    normalizedHost(from: legacyURL) ?? ""
  }

  static func matchScore(
    entryIdentifiers: [AutofillServiceIdentifier],
    requestedIdentifiers: [AutofillServiceIdentifier]
  ) -> Int {
    var best = 0
    for (requestIndex, requested) in requestedIdentifiers.enumerated() {
      for entry in entryIdentifiers {
        let score = serviceMatchScore(entry: entry, requested: requested)
        guard score > 0 else { continue }
        best = max(best, score + max(0, 100 - requestIndex))
      }
    }
    return best
  }

  private static func serviceMatchScore(
    entry: AutofillServiceIdentifier,
    requested: AutofillServiceIdentifier
  ) -> Int {
    if entry.type == .bundleId || requested.type == .bundleId {
      return entry == requested ? 120 : 0
    }

    if entry.type == requested.type, entry.value == requested.value {
      return 120
    }

    guard let entryHost = hostComparableValue(for: entry),
          let requestedHost = hostComparableValue(for: requested) else {
      return 0
    }

    if entryHost == requestedHost { return 110 }
    if requestedHost.hasSuffix(".\(entryHost)") { return 90 }
    if entryHost.hasSuffix(".\(requestedHost)") { return 70 }
    return 0
  }

  private static func hostComparableValue(for identifier: AutofillServiceIdentifier) -> String? {
    switch identifier.type {
    case .domain:
      return normalizedHost(from: identifier.value)
    case .url:
      return normalizedHost(from: identifier.value)
    case .bundleId:
      return nil
    }
  }

  private static func cleanHost(_ rawHost: String?) -> String? {
    guard var host = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !host.isEmpty else {
      return nil
    }

    if host.hasPrefix("[") && host.hasSuffix("]") {
      host.removeFirst()
      host.removeLast()
    }
    while host.hasSuffix(".") { host.removeLast() }

    guard !host.isEmpty,
          host.count <= 253,
          host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
      return nil
    }
    return host
  }
}

enum AutofillMetadataSearch {
  static let possibleMatchLimit = 50
  static let defaultManualSearchLimit = 100
  static let oneCharacterManualSearchLimit = 20

  private static let genericTargetTokens: Set<String> = [
    "www",
    "com",
    "net",
    "org",
    "login",
    "auth",
    "app",
    "mobile",
    "accounts",
    "http",
    "https",
  ]

  static func possibleMatches(
    in entries: [AutofillCredentialMetadata],
    for serviceIdentifiers: [ASCredentialServiceIdentifier],
    limit: Int = possibleMatchLimit
  ) -> [AutofillCredentialMetadata] {
    let requested = SharedAutofillStoreNormalizer.normalizedRequestedIdentifiers(serviceIdentifiers)
    let tokens = targetTokens(from: requested)
    guard !tokens.isEmpty else { return [] }
    return ranked(
      entries: entries,
      tokens: tokens,
      fieldMode: .targetSuggestion,
      requireAllTokens: false,
      limit: limit
    )
  }

  static func search(
    _ entries: [AutofillCredentialMetadata],
    query: String,
    limit: Int? = nil
  ) -> [AutofillCredentialMetadata] {
    let tokens = manualSearchTokens(from: query)
    guard !tokens.isEmpty else { return entries.sortedForDisplay() }

    let normalizedQuery = normalizedSearchValue(query)
    let effectiveLimit = limit ?? (
      normalizedQuery.count == 1 ? oneCharacterManualSearchLimit : defaultManualSearchLimit
    )

    return ranked(
      entries: entries,
      tokens: tokens,
      fieldMode: .manualSearch,
      requireAllTokens: true,
      limit: effectiveLimit
    )
  }

  static func targetTokens(from identifiers: [AutofillServiceIdentifier]) -> [String] {
    var rawValues: [String] = []

    for identifier in identifiers {
      rawValues.append(identifier.value)
      switch identifier.type {
      case .domain, .url:
        if let host = SharedAutofillStoreNormalizer.normalizedHost(from: identifier.value) {
          rawValues.append(host)
        }
      case .bundleId:
        break
      }
    }

    return unique(rawValues.flatMap(targetTokens(fromRawValue:)))
  }

  private enum SearchFieldMode {
    case targetSuggestion
    case manualSearch
  }

  private struct WeightedSearchField {
    let value: String
    let weight: Int
  }

  private static func ranked(
    entries: [AutofillCredentialMetadata],
    tokens: [String],
    fieldMode: SearchFieldMode,
    requireAllTokens: Bool,
    limit: Int
  ) -> [AutofillCredentialMetadata] {
    guard limit > 0 else { return [] }

    let scored = entries.compactMap { entry -> (AutofillCredentialMetadata, Int)? in
      let fields = searchFields(for: entry, mode: fieldMode)
      let score = scoreEntry(
        fields: fields,
        tokens: tokens,
        requireAllTokens: requireAllTokens
      )
      guard score > 0 else { return nil }
      return (entry, score)
    }

    return Array(scored.sorted { lhs, rhs in
      if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
      return lhs.0.sortKey < rhs.0.sortKey
    }.map(\.0).prefix(limit))
  }

  private static func scoreEntry(
    fields: [WeightedSearchField],
    tokens: [String],
    requireAllTokens: Bool
  ) -> Int {
    var total = 0
    var matchedTokens = 0

    for token in tokens {
      let bestScore = fields.compactMap { field -> Int? in
        let value = normalizedSearchValue(field.value)
        guard value.contains(token) else { return nil }
        var score = field.weight
        if value == token {
          score += 12
        } else if value.hasPrefix(token) {
          score += 6
        } else if containsComponentPrefix(token, in: value) {
          score += 4
        }
        return score
      }.max()

      if let bestScore {
        total += bestScore
        matchedTokens += 1
      } else if requireAllTokens {
        return 0
      }
    }

    guard matchedTokens > 0 else { return 0 }
    return total + (matchedTokens * 2)
  }

  private static func searchFields(
    for entry: AutofillCredentialMetadata,
    mode: SearchFieldMode
  ) -> [WeightedSearchField] {
    var fields: [WeightedSearchField] = [
      WeightedSearchField(value: entry.title, weight: 6),
      WeightedSearchField(value: entry.displayService, weight: 8),
    ]

    if mode == .manualSearch {
      fields.append(WeightedSearchField(value: entry.username, weight: 5))
    }

    for identifier in entry.serviceIdentifiers {
      fields.append(WeightedSearchField(value: identifier.value, weight: 9))
      switch identifier.type {
      case .domain, .url:
        if let host = SharedAutofillStoreNormalizer.normalizedHost(from: identifier.value) {
          fields.append(WeightedSearchField(value: host, weight: 10))
        }
      case .bundleId:
        break
      }
    }

    return uniqueFields(fields)
  }

  private static func manualSearchTokens(from query: String) -> [String] {
    let normalized = normalizedSearchValue(query)
    guard !normalized.isEmpty else { return [] }
    let tokens = normalized
      .split(whereSeparator: { $0.isWhitespace })
      .map(String.init)
      .filter { !$0.isEmpty }
    return tokens.isEmpty ? [normalized] : unique(tokens)
  }

  private static func targetTokens(fromRawValue rawValue: String) -> [String] {
    let normalized = normalizedSearchValue(rawValue)
    guard !normalized.isEmpty else { return [] }

    let separators = CharacterSet(charactersIn: ".-_/:\\")
      .union(.whitespacesAndNewlines)
    return normalized
      .components(separatedBy: separators)
      .map { $0.trimmingCharacters(in: .punctuationCharacters) }
      .filter { token in
        token.count >= 3 && !genericTargetTokens.contains(token)
      }
  }

  private static func normalizedSearchValue(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      .lowercased()
  }

  private static func containsComponentPrefix(_ token: String, in value: String) -> Bool {
    let separators = CharacterSet(charactersIn: ".-_/:\\")
      .union(.whitespacesAndNewlines)
    return value
      .components(separatedBy: separators)
      .contains { $0.hasPrefix(token) }
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values where !seen.contains(value) {
      seen.insert(value)
      result.append(value)
    }
    return result
  }

  private static func uniqueFields(_ fields: [WeightedSearchField]) -> [WeightedSearchField] {
    var bestByValue: [String: WeightedSearchField] = [:]
    var order: [String] = []

    for field in fields {
      let key = normalizedSearchValue(field.value)
      guard !key.isEmpty else { continue }
      if let existing = bestByValue[key] {
        if field.weight > existing.weight {
          bestByValue[key] = field
        }
      } else {
        bestByValue[key] = field
        order.append(key)
      }
    }

    return order.compactMap { bestByValue[$0] }
  }
}

private extension Array where Element == AutofillCredentialMetadata {
  func sortedForDisplay() -> [AutofillCredentialMetadata] {
    sorted { lhs, rhs in lhs.sortKey < rhs.sortKey }
  }
}

private extension AutofillCredentialMetadata {
  var sortKey: String {
    "\(displayService)|\(title)|\(username)|\(id)".lowercased()
  }
}

private extension String {
  func trimmedForMetadata(maxLength: Int) -> String {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maxLength else { return trimmed }
    return String(trimmed.prefix(maxLength))
  }
}
