package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutofillAuthSessionWindowTest {
    @Test
    fun ttlZeroAlwaysRequiresAuthentication() {
        assertFalse(
            AutofillAuthSessionWindow.isWithinSession(
                nowEpochMs = 1_000L,
                lastAuthenticatedAtEpochMs = 1_000L,
                ttlMs = 0L,
            ),
        )
    }

    @Test
    fun neverAuthenticatedRequiresAuthentication() {
        assertFalse(
            AutofillAuthSessionWindow.isWithinSession(
                nowEpochMs = 1_000L,
                lastAuthenticatedAtEpochMs = null,
                ttlMs = 30_000L,
            ),
        )
    }

    @Test
    fun insideTheWindowSkipsThePrompt() {
        assertTrue(
            AutofillAuthSessionWindow.isWithinSession(
                nowEpochMs = 10_000L,
                lastAuthenticatedAtEpochMs = 5_000L,
                ttlMs = 30_000L,
            ),
        )
    }

    @Test
    fun exactlyAtTheBoundaryRequiresAuthentication() {
        assertFalse(
            AutofillAuthSessionWindow.isWithinSession(
                nowEpochMs = 35_000L,
                lastAuthenticatedAtEpochMs = 5_000L,
                ttlMs = 30_000L,
            ),
        )
    }

    @Test
    fun expiredWindowRequiresAuthentication() {
        assertFalse(
            AutofillAuthSessionWindow.isWithinSession(
                nowEpochMs = 100_000L,
                lastAuthenticatedAtEpochMs = 5_000L,
                ttlMs = 30_000L,
            ),
        )
    }

    @Test
    fun clockMovedBackwardsRequiresAuthentication() {
        assertFalse(
            AutofillAuthSessionWindow.isWithinSession(
                nowEpochMs = 1_000L,
                lastAuthenticatedAtEpochMs = 5_000L,
                ttlMs = 30_000L,
            ),
        )
    }
}
