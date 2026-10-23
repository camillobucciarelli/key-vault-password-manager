package dev.camillobucciarelli.kdbxKeyVault.autofill

internal const val ANDROID_AUTOFILL_CACHE_VERSION = 2

internal enum class AndroidAutofillServiceIdentifierType(val rawValue: String) {
    Domain("domain"),
    Url("url"),
    BundleId("bundleId"),
    AndroidPackage("androidPackage"),
    ;

    companion object {
        fun fromRawValue(value: String): AndroidAutofillServiceIdentifierType? {
            return entries.firstOrNull { it.rawValue.equals(value.trim(), ignoreCase = true) }
        }
    }
}

internal data class AndroidAutofillServiceIdentifier(
    val type: AndroidAutofillServiceIdentifierType,
    val value: String,
)

/** spec 023 — the COSE algorithms a stored passkey may name. */
internal enum class AndroidPasskeyAlgorithm(val rawValue: String, val coseIdentifier: Int) {
    Es256("ES256", -7),
    EdDsa("EdDSA", -8),
    Rs256("RS256", -257),
    ;

    companion object {
        fun fromRawValue(value: String): AndroidPasskeyAlgorithm? {
            return entries.firstOrNull { it.rawValue.equals(value.trim(), ignoreCase = true) }
        }
    }
}

/**
 * spec 023 — one stored passkey.
 *
 * [privateKeyPem] is the secret. It reaches the sealed cache and the signer
 * and nothing else: not the plaintext metadata, not a log, not [toString].
 */
internal data class AndroidAutofillPasskey(
    val rpId: String,
    val credentialId: String,
    val userHandle: String?,
    val username: String,
    val privateKeyPem: String,
    val algorithm: AndroidPasskeyAlgorithm,
    val backupEligible: Boolean,
    val backupState: Boolean,
) {
    override fun toString(): String {
        return "AndroidAutofillPasskey(rpId=$rpId, credentialId=$credentialId, username=$username, privateKeyPem=<redacted>, algorithm=${algorithm.rawValue})"
    }
}

/**
 * spec 023 — what the plaintext metadata may say about a passkey: the site
 * and the credential id. Never the key, and never the user handle, which is
 * account material at the relying party.
 */
internal data class AndroidAutofillPasskeyMetadata(
    val rpId: String,
    val credentialId: String,
)

internal data class AndroidAutofillPublishEntry(
    val id: String,
    val title: String,
    val username: String,
    val password: String,
    val url: String?,
    val serviceIdentifiers: List<AndroidAutofillServiceIdentifier>,
    val passkeys: List<AndroidAutofillPasskey> = emptyList(),
) {
    override fun toString(): String {
        return "AndroidAutofillPublishEntry(id=$id, title=$title, username=$username, password=<redacted>, url=<redacted>, serviceIdentifiers=$serviceIdentifiers, passkeys=${passkeys.size})"
    }
}

internal data class AndroidAutofillCredentialMetadata(
    val id: String,
    val title: String,
    val username: String,
    val displayService: String,
    val serviceIdentifiers: List<AndroidAutofillServiceIdentifier>,
    val updatedAtEpochMs: Long,
    /** spec 023 — by site and credential id only; enough to answer a
     *  `BeginGetCredentialRequest` without unsealing anything. */
    val passkeys: List<AndroidAutofillPasskeyMetadata> = emptyList(),
    /** spec 023 — whether a password exists, never what it is. A passkey-only
     *  record must not be offered as an autofill dataset: it has nothing to
     *  fill. Defaults true, which is what every pre-023 cache meant. */
    val hasPassword: Boolean = true,
) {
    val sortKey: String
        get() = listOf(displayService, title, username, id)
            .joinToString(separator = "|")
            .lowercase()
}

internal data class AndroidAutofillCredentialSecret(
    val id: String,
    val username: String,
    val password: String,
    val passkeys: List<AndroidAutofillPasskey> = emptyList(),
) {
    override fun toString(): String {
        return "AndroidAutofillCredentialSecret(id=$id, username=$username, password=<redacted>, passkeys=${passkeys.size})"
    }
}

internal data class AndroidAutofillMetadataCache(
    val version: Int,
    val databaseId: String,
    val generatedAtEpochMs: Long,
    val entries: List<AndroidAutofillCredentialMetadata>,
)

internal data class AndroidAutofillPendingAssociation(
    val id: String,
    val databaseId: String,
    val entryId: String,
    val serviceIdentifierType: String,
    val serviceIdentifierValue: String,
    val displayService: String,
    val createdAtEpochMs: Long,
    val platform: String = "android",
)

internal data class AndroidAutofillStoreStatus(
    val metadataCount: Int,
    val encryptedCacheAvailable: Boolean,
    val cacheAvailable: Boolean,
    val databaseId: String?,
    val generatedAtEpochMs: Long?,
    val authSessionTtlMs: Long,
    val lastAuthenticatedAtEpochMs: Long?,
)

/**
 * Authentication session state for the autofill picker.
 *
 * Neither field is a secret. They live in their own plaintext file rather than
 * in the metadata cache because that cache is the AEAD associated data of the
 * sealed secret file: rewriting it to stamp a timestamp would invalidate every
 * sealed credential.
 */
internal data class AndroidAutofillAuthSession(
    val authSessionTtlMs: Long,
    val lastAuthenticatedAtEpochMs: Long?,
)
