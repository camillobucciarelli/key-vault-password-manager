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

internal data class AndroidAutofillPublishEntry(
    val id: String,
    val title: String,
    val username: String,
    val password: String,
    val url: String?,
    val serviceIdentifiers: List<AndroidAutofillServiceIdentifier>,
) {
    override fun toString(): String {
        return "AndroidAutofillPublishEntry(id=$id, title=$title, username=$username, password=<redacted>, url=<redacted>, serviceIdentifiers=$serviceIdentifiers)"
    }
}

internal data class AndroidAutofillCredentialMetadata(
    val id: String,
    val title: String,
    val username: String,
    val displayService: String,
    val serviceIdentifiers: List<AndroidAutofillServiceIdentifier>,
    val updatedAtEpochMs: Long,
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
) {
    override fun toString(): String {
        return "AndroidAutofillCredentialSecret(id=$id, username=$username, password=<redacted>)"
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
