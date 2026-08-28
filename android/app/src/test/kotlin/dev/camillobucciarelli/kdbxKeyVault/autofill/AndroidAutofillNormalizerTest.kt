package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AndroidAutofillNormalizerTest {
    @Test
    fun normalizesWebTargetsWithoutPathQueryOrFragment() {
        val targets = AndroidAutofillNormalizer.normalizedRequestTargets(
            packageName = "com.android.chrome",
            webDomains = listOf("https://www.Example.com/login?token=ignored#fragment"),
        )

        assertEquals(
            listOf(AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "example.com")),
            targets,
        )
    }

    @Test
    fun ignoresBrowserPackageWhenWebDomainPresent() {
        val targets = AndroidAutofillNormalizer.normalizedRequestTargets(
            packageName = "com.android.chrome",
            webDomains = listOf("example.com"),
        )

        assertEquals(1, targets.size)
        assertEquals(AndroidAutofillServiceIdentifierType.Domain, targets.single().type)
    }

    @Test
    fun usesPackageForNativeAppTarget() {
        val targets = AndroidAutofillNormalizer.normalizedRequestTargets(
            packageName = "Com.Example.App",
            webDomains = emptyList(),
        )

        assertEquals(
            listOf(
                AndroidAutofillServiceIdentifier(
                    AndroidAutofillServiceIdentifierType.AndroidPackage,
                    "com.example.app",
                ),
            ),
            targets,
        )
    }

    @Test
    fun normalizesAndroidAppUrlToPackageName() {
        assertEquals(
            "com.example.app",
            AndroidAutofillNormalizer.normalizedAndroidPackage(
                "androidapp://Com.Example.App/path?ignored=1",
            ),
        )
        assertNull(AndroidAutofillNormalizer.normalizedAndroidPackage("androidapp://bad package"))
    }

    // spec-016 FR-013 (T602): a browser request carries both the browser's own
    // package and the page's domain. The package must never become a match
    // target, or every site in a browser would match one "Chrome" entry.
    @Test
    fun browserRequestWithWebDomainDropsTheBrowserPackage() {
        for (browser in listOf("com.android.chrome", "org.mozilla.firefox")) {
            val targets = AndroidAutofillNormalizer.normalizedRequestTargets(
                packageName = browser,
                webDomains = listOf("https://accounts.example.com/login"),
            )

            assertEquals(
                listOf(
                    AndroidAutofillServiceIdentifier(
                        AndroidAutofillServiceIdentifierType.Domain,
                        "accounts.example.com",
                    ),
                ),
                targets,
            )
        }
    }

    // FR-013: with no readable domain there is nothing to match a browser
    // request against, so it yields the browser package and matching against it
    // is the matcher's problem, not the normalizer's. See
    // AndroidAutofillCredentialMatcherTest.browserPackageAloneIsNeverAStrongMatch.
    @Test
    fun browserRequestWithoutAReadableDomainKeepsOnlyThePackage() {
        val targets = AndroidAutofillNormalizer.normalizedRequestTargets(
            packageName = "com.android.chrome",
            webDomains = listOf("   ", "about:blank"),
        )

        assertEquals(
            listOf(
                AndroidAutofillServiceIdentifier(
                    AndroidAutofillServiceIdentifierType.AndroidPackage,
                    "com.android.chrome",
                ),
            ),
            targets,
        )
    }

    @Test
    fun nonWebSchemesAreNotHosts() {
        assertNull(AndroidAutofillNormalizer.normalizedHost("about:blank"))
        assertNull(AndroidAutofillNormalizer.normalizedHost("chrome://newtab"))
        assertNull(AndroidAutofillNormalizer.normalizedHost("content://downloads"))
        // A colon before a port is not a scheme.
        assertEquals("example.com", AndroidAutofillNormalizer.normalizedHost("example.com:8080"))
        assertEquals("example.com", AndroidAutofillNormalizer.normalizedHost("https://example.com"))
    }
}
