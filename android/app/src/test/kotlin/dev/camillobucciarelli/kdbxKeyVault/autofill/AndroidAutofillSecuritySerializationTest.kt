package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidAutofillSecuritySerializationTest {
    @Test
    fun metadataPreparedForCacheExcludesPasswordAndFullUrlPath() {
        val secret = "plain-text-password"
        val identifiers = AndroidAutofillNormalizer.normalizedServiceIdentifiers(
            url = "https://www.Example.com/login/path?token=secret#fragment",
            provided = emptyList(),
        )
        val metadata = AndroidAutofillCredentialMetadata(
            id = "entry-1",
            title = "Example",
            username = "alice",
            displayService = AndroidAutofillNormalizer.displayService(identifiers),
            serviceIdentifiers = identifiers,
            updatedAtEpochMs = 1,
        )
        val cache = AndroidAutofillMetadataCache(
            version = ANDROID_AUTOFILL_CACHE_VERSION,
            databaseId = "database-id",
            generatedAtEpochMs = 1,
            entries = listOf(metadata),
        )
        val persistedFields = cache.entries.flatMap { entry ->
            listOf(entry.id, entry.title, entry.username, entry.displayService) +
                entry.serviceIdentifiers.flatMap { listOf(it.type.rawValue, it.value) }
        }.joinToString(separator = "|")

        assertFalse(persistedFields.contains(secret))
        assertFalse(persistedFields.contains("/login"))
        assertFalse(persistedFields.contains("token="))
        assertFalse(persistedFields.contains("fragment"))
        assertTrue(persistedFields.contains("https://example.com"))
        assertTrue(persistedFields.contains("example.com"))
    }

    @Test
    fun pendingAssociationPayloadExcludesPasswordAndFullUrlPath() {
        val secret = "plain-text-password"
        val target = AndroidAutofillNormalizer.normalizedRequestTargets(
            packageName = "com.android.chrome",
            webDomains = listOf("https://www.Example.com/login/path?token=secret#fragment"),
        ).single()
        val pending = AndroidAutofillPendingAssociation(
            id = "pending-1",
            databaseId = "database-id",
            entryId = "entry-1",
            serviceIdentifierType = target.type.rawValue,
            serviceIdentifierValue = target.value,
            displayService = AndroidAutofillNormalizer.displayService(listOf(target)),
            createdAtEpochMs = 1,
        )

        val payload = AndroidAutofillJson.pendingAssociationToMap(pending).values.joinToString(separator = "|")

        assertFalse(payload.contains(secret))
        assertFalse(payload.contains("/login"))
        assertFalse(payload.contains("token="))
        assertFalse(payload.contains("fragment"))
        assertTrue(payload.contains("example.com"))
        assertTrue(payload.contains("android"))
    }

    @Test
    fun credentialSecretToStringRedactsPassword() {
        val secret = AndroidAutofillCredentialSecret(
            id = "entry-1",
            username = "alice",
            password = "plain-text-password",
        )

        assertFalse(secret.toString().contains("plain-text-password"))
        assertTrue(secret.toString().contains("<redacted>"))
    }
}
