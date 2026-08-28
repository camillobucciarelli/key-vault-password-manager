package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidAutofillCredentialMatcherTest {
    @Test
    fun strongMatchRequiresExactNormalizedHost() {
        val entry = credential(
            id = "entry-1",
            identifiers = listOf(
                AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "example.com"),
            ),
        )

        assertTrue(
            AndroidAutofillCredentialMatcher.isStrongMatch(
                entry,
                listOf(AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "www.example.com")),
            ),
        )
        assertFalse(
            AndroidAutofillCredentialMatcher.isStrongMatch(
                entry,
                listOf(AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "evil-example.com")),
            ),
        )
    }

    @Test
    fun phishingSubdomainDoesNotStrongMatchParentDomain() {
        val entry = credential(
            id = "entry-1",
            identifiers = listOf(
                AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "example.com"),
            ),
        )
        val phishingTarget = listOf(
            AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "example.com.evil.com"),
        )

        assertFalse(AndroidAutofillCredentialMatcher.isStrongMatch(entry, phishingTarget))
        assertEquals(emptyList<AndroidAutofillCredentialMetadata>(), AndroidAutofillCredentialMatcher.strongMatches(listOf(entry), phishingTarget))
    }

    @Test
    fun strongMatchRequiresExactAndroidPackage() {
        val entry = credential(
            id = "entry-1",
            identifiers = listOf(
                AndroidAutofillServiceIdentifier(
                    AndroidAutofillServiceIdentifierType.AndroidPackage,
                    "com.example.app",
                ),
            ),
        )

        assertTrue(
            AndroidAutofillCredentialMatcher.isStrongMatch(
                entry,
                listOf(
                    AndroidAutofillServiceIdentifier(
                        AndroidAutofillServiceIdentifierType.AndroidPackage,
                        "com.example.app",
                    ),
                ),
            ),
        )
        assertFalse(
            AndroidAutofillCredentialMatcher.isStrongMatch(
                entry,
                listOf(
                    AndroidAutofillServiceIdentifier(
                        AndroidAutofillServiceIdentifierType.AndroidPackage,
                        "com.example.app.beta",
                    ),
                ),
            ),
        )
    }

    @Test
    fun partialTargetTokenIsPossibleMatchOnly() {
        val entry = credential(
            id = "entry-1",
            title = "Example Bank",
            displayService = "examplebank.com",
            identifiers = listOf(
                AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "examplebank.com"),
            ),
        )
        val target = listOf(
            AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "bank-login.test"),
        )

        assertFalse(AndroidAutofillCredentialMatcher.isStrongMatch(entry, target))
        assertEquals(listOf(entry), AndroidAutofillCredentialMatcher.possibleMatches(listOf(entry), target))
    }

    // spec-016 FR-013 (T602): a saved site entry must not be handed to whatever
    // page the browser happens to be showing when the domain could not be read.
    @Test
    fun browserPackageAloneIsNeverAStrongMatch() {
        val siteEntry = credential(
            id = "entry-1",
            identifiers = listOf(
                AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "example.com"),
            ),
        )
        val browserTarget = listOf(
            AndroidAutofillServiceIdentifier(
                AndroidAutofillServiceIdentifierType.AndroidPackage,
                "com.android.chrome",
            ),
        )

        assertFalse(AndroidAutofillCredentialMatcher.isStrongMatch(siteEntry, browserTarget))
        assertEquals(
            emptyList<AndroidAutofillCredentialMetadata>(),
            AndroidAutofillCredentialMatcher.strongMatches(listOf(siteEntry), browserTarget),
        )
    }

    // The site entry, not the browser, is what a browser request matches.
    @Test
    fun browserRequestStrongMatchesThePageDomain() {
        val siteEntry = credential(
            id = "entry-1",
            identifiers = listOf(
                AndroidAutofillServiceIdentifier(AndroidAutofillServiceIdentifierType.Domain, "example.com"),
            ),
        )
        val targets = AndroidAutofillNormalizer.normalizedRequestTargets(
            packageName = "com.android.chrome",
            webDomains = listOf("https://www.example.com/login"),
        )

        assertEquals(
            listOf(siteEntry),
            AndroidAutofillCredentialMatcher.strongMatches(listOf(siteEntry), targets),
        )
    }

    private fun credential(
        id: String,
        title: String = "Example",
        username: String = "alice",
        displayService: String = "example.com",
        identifiers: List<AndroidAutofillServiceIdentifier>,
    ): AndroidAutofillCredentialMetadata {
        return AndroidAutofillCredentialMetadata(
            id = id,
            title = title,
            username = username,
            displayService = displayService,
            serviceIdentifiers = identifiers,
            updatedAtEpochMs = 1,
        )
    }
}
