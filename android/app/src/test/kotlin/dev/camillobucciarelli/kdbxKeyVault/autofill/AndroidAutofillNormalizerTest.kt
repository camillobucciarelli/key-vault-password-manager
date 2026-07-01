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
}
