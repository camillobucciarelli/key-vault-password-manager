package dev.camillobucciarelli.kdbxKeyVault.autofill

import java.net.URI
import java.util.Locale

internal object AndroidAutofillNormalizer {
    fun normalizedServiceIdentifiers(
        url: String?,
        provided: List<AndroidAutofillServiceIdentifier>,
    ): List<AndroidAutofillServiceIdentifier> {
        val identifiers = mutableListOf<AndroidAutofillServiceIdentifier>()
        val seen = mutableSetOf<AndroidAutofillServiceIdentifier>()

        fun add(identifier: AndroidAutofillServiceIdentifier?) {
            if (identifier == null || identifier.value.isBlank()) {
                return
            }
            if (seen.add(identifier)) {
                identifiers.add(identifier)
            }
        }

        normalizedOrigin(url)?.let { origin ->
            add(AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Url, origin))
        }
        normalizedHost(url)?.let { host ->
            add(AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, host))
        }
        normalizedAndroidPackage(url)?.let { packageName ->
            add(
                AndroidAutofillServiceIdentifier(
                    AndroidAutofillServiceIdentifierType.AndroidPackage,
                    packageName,
                ),
            )
        }

        for (raw in provided) {
            when (raw.type) {
                AndroidAutofillServiceIdentifierType.Domain -> {
                    normalizedHost(raw.value)?.let { host ->
                        add(
                            AndroidAutofillServiceIdentifier(
                                AndroidAutofillServiceIdentifierType.Domain,
                                host,
                            ),
                        )
                    }
                }
                AndroidAutofillServiceIdentifierType.Url -> {
                    normalizedOrigin(raw.value)?.let { origin ->
                        add(
                            AndroidAutofillServiceIdentifier(
                                AndroidAutofillServiceIdentifierType.Url,
                                origin,
                            ),
                        )
                    }
                    normalizedHost(raw.value)?.let { host ->
                        add(
                            AndroidAutofillServiceIdentifier(
                                AndroidAutofillServiceIdentifierType.Domain,
                                host,
                            ),
                        )
                    }
                }
                AndroidAutofillServiceIdentifierType.AndroidPackage -> {
                    normalizedAndroidPackage(raw.value)?.let { packageName ->
                        add(
                            AndroidAutofillServiceIdentifier(
                                AndroidAutofillServiceIdentifierType.AndroidPackage,
                                packageName,
                            ),
                        )
                    }
                }
                AndroidAutofillServiceIdentifierType.BundleId -> Unit
            }
        }

        return identifiers
    }

    fun normalizedRequestTargets(
        packageName: String?,
        webDomains: Collection<String>,
    ): List<AndroidAutofillServiceIdentifier> {
        val identifiers = mutableListOf<AndroidAutofillServiceIdentifier>()
        val seen = mutableSetOf<AndroidAutofillServiceIdentifier>()

        fun add(identifier: AndroidAutofillServiceIdentifier?) {
            if (identifier == null || identifier.value.isBlank()) {
                return
            }
            if (seen.add(identifier)) {
                identifiers.add(identifier)
            }
        }

        for (domain in webDomains) {
            normalizedHost(domain)?.let { host ->
                add(AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, host))
            }
        }

        // Browser/WebView requests expose both app package and webDomain. In that
        // case package matching would bind credentials to the browser app, not the
        // site, so use package only for native app requests.
        if (identifiers.none { it.type == AndroidAutofillServiceIdentifierType.Domain }) {
            normalizedAndroidPackage(packageName)?.let { packageValue ->
                add(
                    AndroidAutofillServiceIdentifier(
                        AndroidAutofillServiceIdentifierType.AndroidPackage,
                        packageValue,
                    ),
                )
            }
        }

        return identifiers
    }

    fun displayService(identifiers: List<AndroidAutofillServiceIdentifier>): String {
        identifiers.firstOrNull { it.type == AndroidAutofillServiceIdentifierType.Domain }?.let {
            return it.value
        }
        identifiers.firstOrNull { it.type == AndroidAutofillServiceIdentifierType.Url }?.let {
            return normalizedHost(it.value).orEmpty()
        }
        identifiers.firstOrNull { it.type == AndroidAutofillServiceIdentifierType.AndroidPackage }?.let {
            return it.value
        }
        return ""
    }

    fun normalizedHost(rawValue: String?): String? {
        val value = rawValue?.trim().orEmpty()
        if (value.isEmpty() || value.startsWith("androidapp:", ignoreCase = true)) {
            return null
        }
        // spec-016 FR-013: a browser reports non-web pages too ("about:blank",
        // "chrome://newtab"). Without this, the scheme itself became the host and
        // an entry could strong-match a page that has no domain at all.
        if (hasNonWebScheme(value)) {
            return null
        }

        val candidate = valueWithDefaultScheme(value)
        val uri = runCatching { URI(candidate) }.getOrNull()
        val rawHost = uri?.host ?: value.substringBefore('/').substringBefore(':')
        return cleanHost(rawHost)
    }

    fun normalizedOrigin(rawValue: String?): String? {
        val value = rawValue?.trim().orEmpty()
        if (value.isEmpty() || value.startsWith("androidapp:", ignoreCase = true)) {
            return null
        }

        val uri = runCatching { URI(valueWithDefaultScheme(value)) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase(Locale.ROOT)
        if (scheme != "http" && scheme != "https") {
            return null
        }
        val host = cleanHost(uri.host) ?: return null
        return if (uri.port >= 0) {
            "$scheme://$host:${uri.port}"
        } else {
            "$scheme://$host"
        }
    }

    fun normalizedAndroidPackage(rawValue: String?): String? {
        var value = rawValue?.trim()?.lowercase(Locale.ROOT).orEmpty()
        if (value.isEmpty()) {
            return null
        }
        if (value.startsWith("androidapp:")) {
            value = value.removePrefix("androidapp:").replaceFirst(Regex("^/+"), "")
            val delimiter = firstDelimiterIndex(value)
            if (delimiter >= 0) {
                value = value.substring(0, delimiter)
            }
        }
        value = value.replace(Regex("^/+|/+$"), "")
        if (value.isEmpty() || value.length > 255) {
            return null
        }
        if (!Regex("^[a-z0-9._]+$").matches(value)) {
            return null
        }
        return value
    }

    fun targetTokens(identifiers: List<AndroidAutofillServiceIdentifier>): List<String> {
        val rawValues = mutableListOf<String>()
        for (identifier in identifiers) {
            rawValues.add(identifier.value)
            if (identifier.type == AndroidAutofillServiceIdentifierType.Domain ||
                identifier.type == AndroidAutofillServiceIdentifierType.Url
            ) {
                normalizedHost(identifier.value)?.let(rawValues::add)
            }
        }
        return rawValues.flatMap(::targetTokensFromRawValue).distinct()
    }

    fun normalizedSearchValue(value: String): String {
        return value.trim().lowercase(Locale.ROOT)
    }

    // True for "about:blank" or "chrome://newtab"; false for "example.com:8080",
    // where the colon introduces a port rather than a scheme.
    private fun hasNonWebScheme(value: String): Boolean {
        val colon = value.indexOf(':')
        if (colon <= 0) {
            return false
        }
        val scheme = value.substring(0, colon).lowercase(Locale.ROOT)
        if (scheme == "http" || scheme == "https") {
            return false
        }
        if (!Regex("^[a-z][a-z0-9+.\\-]*$").matches(scheme)) {
            return false
        }
        return !value.getOrNull(colon + 1).let { it != null && it.isDigit() }
    }

    private fun valueWithDefaultScheme(value: String): String {
        return when {
            value.contains("://") -> value
            value.startsWith("//") -> "https:$value"
            else -> "https://$value"
        }
    }

    private fun cleanHost(rawHost: String?): String? {
        var host = rawHost?.trim()?.lowercase(Locale.ROOT).orEmpty()
        if (host.startsWith("[") && host.endsWith("]")) {
            host = host.substring(1, host.length - 1)
        }
        while (host.endsWith('.')) {
            host = host.dropLast(1)
        }
        for (prefix in listOf("www.", "m.", "mobile.")) {
            if (host.startsWith(prefix)) {
                host = host.substring(prefix.length)
                break
            }
        }
        if (host.isEmpty() || host.length > 253 || host.any { it.isWhitespace() || it == '/' || it == '@' }) {
            return null
        }
        return host
    }

    private fun targetTokensFromRawValue(rawValue: String): List<String> {
        val normalized = normalizedSearchValue(rawValue)
        if (normalized.isEmpty()) {
            return emptyList()
        }
        return normalized
            .split(Regex("[.\\-_/:\\\\\\s]+"))
            .map { it.trim { char -> !char.isLetterOrDigit() } }
            .filter { it.length >= 3 && it !in genericTargetTokens }
    }

    private fun firstDelimiterIndex(value: String): Int {
        return listOf('/', '?', '#')
            .map(value::indexOf)
            .filter { it >= 0 }
            .minOrNull() ?: -1
    }

    private val genericTargetTokens = setOf(
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
    )
}
