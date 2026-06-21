package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CredentialFieldHeuristicsTest {
    @Test
    fun classifiesPasswordAutofillHint() {
        val result = CredentialFieldHeuristics.classify(
            CredentialFieldSignals(autofillHints = listOf("password")),
        )

        assertTrue(CredentialFieldKind.Password in result)
        assertFalse(CredentialFieldKind.Username in result)
    }

    @Test
    fun classifiesEmailFieldAsUsername() {
        val result = CredentialFieldHeuristics.classify(
            CredentialFieldSignals(hint = "Email address"),
        )

        assertTrue(CredentialFieldKind.Username in result)
        assertFalse(CredentialFieldKind.Password in result)
    }

    @Test
    fun classifiesHtmlPasswordType() {
        val result = CredentialFieldHeuristics.classify(
            CredentialFieldSignals(htmlAttributes = mapOf("type" to "password")),
        )

        assertTrue(CredentialFieldKind.Password in result)
    }

    @Test
    fun ignoresUnrelatedSearchFields() {
        val result = CredentialFieldHeuristics.classify(
            CredentialFieldSignals(idEntry = "search_query", hint = "Search"),
        )

        assertTrue(result.isEmpty())
    }
}
