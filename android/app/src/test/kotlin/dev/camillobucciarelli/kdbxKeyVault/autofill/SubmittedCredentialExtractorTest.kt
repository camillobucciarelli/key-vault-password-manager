package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SubmittedCredentialExtractorTest {
    @Test
    fun signInScreenYieldsTheSubmittedPair() {
        val credential = SubmittedCredentialExtractor.extract(
            listOf(
                CredentialFieldValue(CredentialFieldKind.Username, "alice@example.com"),
                CredentialFieldValue(CredentialFieldKind.Password, "typed-password"),
            ),
        )

        assertEquals("alice@example.com", credential?.username)
        assertEquals("typed-password", credential?.password)
    }

    @Test
    fun newPasswordAndConfirmPasswordCollapseToOneCredential() {
        val credential = SubmittedCredentialExtractor.extract(
            listOf(
                CredentialFieldValue(CredentialFieldKind.Username, "alice"),
                CredentialFieldValue(CredentialFieldKind.Password, "chosen-password"),
                CredentialFieldValue(CredentialFieldKind.Password, "chosen-password"),
            ),
        )

        assertEquals("chosen-password", credential?.password)
    }

    @Test
    fun aChangePasswordScreenKeepsTheNewPasswordNotTheOldOne() {
        val credential = SubmittedCredentialExtractor.extract(
            listOf(
                CredentialFieldValue(CredentialFieldKind.Password, "old-password"),
                CredentialFieldValue(CredentialFieldKind.Password, "new-password"),
                CredentialFieldValue(CredentialFieldKind.Password, "new-password"),
            ),
        )

        assertEquals("new-password", credential?.password)
    }

    @Test
    fun aPasswordOnlyScreenYieldsAnEmptyUsername() {
        val credential = SubmittedCredentialExtractor.extract(
            listOf(CredentialFieldValue(CredentialFieldKind.Password, "typed-password")),
        )

        assertEquals("", credential?.username)
        assertEquals("typed-password", credential?.password)
    }

    @Test
    fun aFormWithoutAPasswordCapturesNothing() {
        assertNull(
            SubmittedCredentialExtractor.extract(
                listOf(CredentialFieldValue(CredentialFieldKind.Username, "alice")),
            ),
        )
    }

    @Test
    fun aBlankPasswordCapturesNothing() {
        assertNull(
            SubmittedCredentialExtractor.extract(
                listOf(
                    CredentialFieldValue(CredentialFieldKind.Username, "alice"),
                    CredentialFieldValue(CredentialFieldKind.Password, ""),
                ),
            ),
        )
    }

    @Test
    fun theCapturedValuesNeverReachAToString() {
        val field = CredentialFieldValue(CredentialFieldKind.Password, "typed-password")
        val credential = SubmittedCredentialExtractor.extract(listOf(field))

        assertEquals(false, field.toString().contains("typed-password"))
        assertEquals(false, credential.toString().contains("typed-password"))
    }
}
