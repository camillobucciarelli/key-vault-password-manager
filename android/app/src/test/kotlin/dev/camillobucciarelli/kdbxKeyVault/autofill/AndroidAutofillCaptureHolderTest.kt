package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidAutofillCaptureHolderTest {
    private var now = 1_000L

    private fun holder(ttlMs: Long = 60_000L) =
        AndroidAutofillCaptureHolder(now = { now }, ttlMs = ttlMs)

    private fun AndroidAutofillCaptureHolder.storeSample(
        username: String = "alice",
        password: String = "typed-password",
        packageName: String? = "com.example.app",
        webDomain: String? = null,
    ) = store(
        username = username,
        password = password,
        packageName = packageName,
        webDomain = webDomain,
    )

    @Test
    fun theSecretIsHandedOutExactlyOnce() {
        val holder = holder()
        val token = holder.storeSample().token

        assertEquals("typed-password", holder.readSecret(token)?.password)
        assertNull(holder.readSecret(token))
    }

    @Test
    fun anUnknownTokenReadsAsMissing() {
        assertNull(holder().readSecret("not-a-token"))
    }

    @Test
    fun resolveStillSeesACaptureWhoseSecretWasRead() {
        val holder = holder()
        val token = holder.storeSample().token
        holder.readSecret(token)

        assertNotNull(holder.resolve(token))
        assertEquals(0, holder.size())
    }

    @Test
    fun resolvingAnUnknownTokenIsSafe() {
        assertNull(holder().resolve("not-a-token"))
    }

    @Test
    fun resolveDropsTheCaptureWhateverTheOutcome() {
        val holder = holder()
        val token = holder.storeSample().token

        holder.resolve(token)

        assertNull(holder.readSecret(token))
    }

    @Test
    fun aCaptureExpires() {
        val holder = holder(ttlMs = 5_000L)
        val token = holder.storeSample().token

        now += 5_001L

        assertNull(holder.readSecret(token))
        assertEquals(0, holder.size())
    }

    @Test
    fun aCaptureSurvivesUpToItsTtl() {
        val holder = holder(ttlMs = 5_000L)
        val token = holder.storeSample().token

        now += 4_999L

        assertNotNull(holder.readSecret(token))
    }

    @Test
    fun tokensDifferBetweenCaptures() {
        val holder = holder()

        assertNotEquals(holder.storeSample().token, holder.storeSample().token)
    }

    @Test
    fun theCaptureRedactsBothHalvesOfTheCredential() {
        val capture = holder().storeSample(username = "alice", password = "typed-password")

        val rendered = capture.toString()

        assertFalse(rendered.contains("typed-password"))
        assertFalse(rendered.contains("alice"))
        assertTrue(rendered.contains(capture.token))
    }

    @Test
    fun theAssociationPrefersTheSiteOverTheApp() {
        val holder = holder()
        val browser = holder.storeSample(
            packageName = "com.android.chrome",
            webDomain = "example.com",
        )
        val app = holder.storeSample(packageName = "com.example.app", webDomain = null)

        assertEquals("example.com", browser.association)
        assertEquals("com.example.app", app.association)
    }

    @Test
    fun aDeclineIsRememberedCaseInsensitively() {
        assertEquals(
            AndroidAutofillDeclinedSave.keyOf("Example.com", "Alice"),
            AndroidAutofillDeclinedSave.keyOf("example.com", "alice"),
        )
        assertNotEquals(
            AndroidAutofillDeclinedSave.keyOf("example.com", "alice"),
            AndroidAutofillDeclinedSave.keyOf("example.com", "bob"),
        )
    }

    @Test
    fun clearDropsEverything() {
        val holder = holder()
        holder.storeSample()
        holder.storeSample()

        holder.clear()

        assertEquals(0, holder.size())
    }
}
