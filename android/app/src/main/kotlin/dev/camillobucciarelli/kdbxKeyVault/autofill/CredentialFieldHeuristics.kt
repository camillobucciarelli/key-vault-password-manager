package dev.camillobucciarelli.kdbxKeyVault.autofill

import java.util.Locale

internal enum class CredentialFieldKind {
    Username,
    Password,
}

internal data class CredentialFieldSignals(
    val autofillHints: List<String> = emptyList(),
    val hint: String? = null,
    val idEntry: String? = null,
    val className: String? = null,
    val htmlTag: String? = null,
    val htmlAttributes: Map<String, String> = emptyMap(),
    val isPasswordInputType: Boolean = false,
    val isEmailInputType: Boolean = false,
)

internal object CredentialFieldHeuristics {
    private val passwordMarkers = setOf(
        "password",
        "passwd",
        "pwd",
        "passcode",
        "currentpassword",
        "newpassword",
    )

    private val usernameMarkers = setOf(
        "username",
        "userid",
        "userlogin",
        "loginid",
        "login",
        "email",
        "emailaddress",
        "mail",
        "accountname",
    )

    fun classify(signals: CredentialFieldSignals): Set<CredentialFieldKind> {
        val tokens = signals.normalizedTokens()
        val isPassword = signals.isPasswordInputType || tokens.any { token ->
            passwordMarkers.any { marker -> token.contains(marker) }
        }

        val result = linkedSetOf<CredentialFieldKind>()
        if (isPassword) {
            result.add(CredentialFieldKind.Password)
        }

        val isUsername = signals.isEmailInputType || tokens.any { token ->
            usernameMarkers.any { marker -> token.contains(marker) }
        }
        if (isUsername && !isPassword) {
            result.add(CredentialFieldKind.Username)
        }

        return result
    }

    private fun CredentialFieldSignals.normalizedTokens(): List<String> {
        val values = mutableListOf<String>()
        values.addAll(autofillHints)
        values.addIfNotBlank(hint)
        values.addIfNotBlank(idEntry)
        values.addIfNotBlank(className)
        values.addIfNotBlank(htmlTag)
        htmlAttributes.forEach { (key, value) ->
            values.addIfNotBlank(key)
            values.addIfNotBlank(value)
        }

        return values
            .map { it.lowercase(Locale.ROOT).filter(Char::isLetterOrDigit) }
            .filter { it.isNotBlank() }
    }

    private fun MutableList<String>.addIfNotBlank(value: String?) {
        if (!value.isNullOrBlank()) {
            add(value)
        }
    }
}
