package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * spec 023 T401 — a passkey survives the sealed cache round trip, and the
 * plaintext metadata never learns the key.
 */
class AndroidPasskeySerializationTest {
    private val pem = """
        -----BEGIN PRIVATE KEY-----
        ZmFrZS1maXh0dXJlLWtleQ==
        -----END PRIVATE KEY-----
    """.trimIndent()

    private fun passkey(
        rpId: String = "webauthn.io",
        credentialId: String = "AQIDBAU",
        backupEligible: Boolean = true,
        backupState: Boolean = true,
    ) = AndroidAutofillPasskey(
        rpId = rpId,
        credentialId = credentialId,
        userHandle = "CQk",
        username = "ada",
        privateKeyPem = pem,
        algorithm = AndroidPasskeyAlgorithm.Es256,
        backupEligible = backupEligible,
        backupState = backupState,
    )

    @Test
    fun sealedSecretsRoundTripEveryPasskeyField() {
        val json = AndroidAutofillJson.secretsToJson(
            version = ANDROID_AUTOFILL_CACHE_VERSION,
            databaseId = "db",
            generatedAtEpochMs = 1,
            entries = listOf(
                AndroidAutofillCredentialSecret(
                    id = "entry-1",
                    username = "ada",
                    password = "",
                    passkeys = listOf(passkey()),
                ),
            ),
        )

        val (_, _, entries) = AndroidAutofillJson.secretsFromJson(json)
        val decoded = entries.single().passkeys.single()
        assertEquals("webauthn.io", decoded.rpId)
        assertEquals("AQIDBAU", decoded.credentialId)
        assertEquals("CQk", decoded.userHandle)
        assertEquals(pem, decoded.privateKeyPem)
        assertEquals(AndroidPasskeyAlgorithm.Es256, decoded.algorithm)
        assertTrue(decoded.backupEligible)
        assertTrue(decoded.backupState)
    }

    @Test
    fun metadataCacheCarriesNoKeyAndNoUserHandle() {
        val metadata = AndroidAutofillCredentialMetadata(
            id = "entry-1",
            title = "Webauthn",
            username = "ada",
            displayService = "webauthn.io",
            serviceIdentifiers = emptyList(),
            updatedAtEpochMs = 1,
            passkeys = listOf(
                AndroidAutofillPasskeyMetadata(rpId = "webauthn.io", credentialId = "AQIDBAU"),
            ),
            hasPassword = false,
        )
        val json = AndroidAutofillJson.metadataCacheToJson(
            AndroidAutofillMetadataCache(
                version = ANDROID_AUTOFILL_CACHE_VERSION,
                databaseId = "db",
                generatedAtEpochMs = 1,
                entries = listOf(metadata),
            ),
        )

        assertFalse(json.contains("PRIVATE KEY"))
        assertFalse(json.contains("ZmFrZS1maXh0dXJlLWtleQ"))
        assertFalse(json.contains("userHandle"))
        assertTrue(json.contains("AQIDBAU"))

        val decoded = AndroidAutofillJson.metadataCacheFromJson(json).entries.single()
        assertEquals("webauthn.io", decoded.passkeys.single().rpId)
        assertFalse(decoded.hasPassword)
    }

    /** A pre-023 cache has neither field; both must read as their old meaning. */
    @Test
    fun aCacheWrittenBeforePasskeysStillDecodes() {
        val json = """
            {"version":2,"databaseId":"db","generatedAtEpochMs":1,
             "entries":[{"id":"entry-1","title":"Example","username":"ada",
                         "displayService":"example.com","serviceIdentifiers":[],
                         "updatedAtEpochMs":1}]}
        """.trimIndent()

        val decoded = AndroidAutofillJson.metadataCacheFromJson(json).entries.single()
        assertTrue(decoded.passkeys.isEmpty())
        assertTrue(decoded.hasPassword)
    }

    /** WebAuthn forbids BS without BE: a record claiming both is corrected. */
    @Test
    fun backupStateCannotOutliveBackupEligible() {
        val json = AndroidAutofillJson.secretsToJson(
            version = ANDROID_AUTOFILL_CACHE_VERSION,
            databaseId = "db",
            generatedAtEpochMs = 1,
            entries = listOf(
                AndroidAutofillCredentialSecret(
                    id = "entry-1",
                    username = "ada",
                    password = "",
                    passkeys = listOf(passkey(backupEligible = false, backupState = true)),
                ),
            ),
        )

        val decoded = AndroidAutofillJson.secretsFromJson(json).third.single().passkeys.single()
        assertFalse(decoded.backupEligible)
        assertFalse(decoded.backupState)
    }

    @Test
    fun anEntryWithAnUnreadablePasskeyDropsThatPasskeyOnly() {
        val json = """
            {"version":2,"databaseId":"db","generatedAtEpochMs":1,
             "entries":[{"id":"entry-1","username":"ada","password":"pw",
                         "passkeys":[{"rpId":"webauthn.io"},
                                     {"rpId":"example.org","credentialId":"Ynk",
                                      "privateKeyPem":"x","algorithm":"ES256"}]}]}
        """.trimIndent()

        val decoded = AndroidAutofillJson.secretsFromJson(json).third.single()
        assertEquals(1, decoded.passkeys.size)
        assertEquals("example.org", decoded.passkeys.single().rpId)
    }

    @Test
    fun toStringNeverCarriesTheKey() {
        assertFalse(passkey().toString().contains("PRIVATE KEY"))
        assertFalse(
            AndroidAutofillCredentialSecret(
                id = "entry-1",
                username = "ada",
                password = "pw",
                passkeys = listOf(passkey()),
            ).toString().contains("PRIVATE KEY"),
        )
        assertNull(AndroidPasskeyAlgorithm.fromRawValue("nope"))
    }
}
