package dev.camillobucciarelli.kdbxKeyVault.autofill

import android.app.KeyguardManager
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import dev.camillobucciarelli.kdbxKeyVault.R

/**
 * Session-window arithmetic for the autofill authentication gate.
 *
 * Kept free of Android APIs so it is covered by plain JVM unit tests.
 */
internal object AutofillAuthSessionWindow {
    fun isWithinSession(
        nowEpochMs: Long,
        lastAuthenticatedAtEpochMs: Long?,
        ttlMs: Long,
    ): Boolean {
        if (ttlMs <= 0L || lastAuthenticatedAtEpochMs == null) {
            return false
        }
        val elapsed = nowEpochMs - lastAuthenticatedAtEpochMs
        // A negative elapsed time means the clock moved backwards: re-authenticate.
        return elapsed in 0L until ttlMs
    }
}

/**
 * The single entry point that authorises releasing a credential secret.
 *
 * It never decrypts anything itself: callers must treat any outcome other than
 * [Outcome.Authenticated] as "fill nothing".
 */
internal class AutofillAuthGate(
    private val activity: FragmentActivity,
    private val store: AndroidAutofillStore,
    private val now: () -> Long = System::currentTimeMillis,
) {
    enum class Outcome {
        /** Authenticated, either within the reuse window or by a fresh prompt. */
        Authenticated,

        /** The user dismissed the prompt, or it failed. Nothing may be released. */
        Cancelled,

        /** The device has no usable biometric or device credential. */
        NoAuthenticator,
    }

    fun authenticate(onResult: (Outcome) -> Unit) {
        val session = store.readAuthSession()
        if (
            AutofillAuthSessionWindow.isWithinSession(
                nowEpochMs = now(),
                lastAuthenticatedAtEpochMs = session.lastAuthenticatedAtEpochMs,
                ttlMs = session.authSessionTtlMs,
            )
        ) {
            onResult(Outcome.Authenticated)
            return
        }

        if (!hasAuthenticator()) {
            onResult(Outcome.NoAuthenticator)
            return
        }

        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    store.recordAuthentication(now())
                    onResult(Outcome.Authenticated)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    onResult(Outcome.Cancelled)
                }
            },
        )
        prompt.authenticate(promptInfo())
    }

    private fun promptInfo(): BiometricPrompt.PromptInfo {
        val builder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(activity.getString(R.string.autofill_auth_prompt_title))
            .setSubtitle(activity.getString(R.string.autofill_auth_prompt_subtitle))
            .setConfirmationRequired(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        } else {
            // API 29 predates setAllowedAuthenticators; this is its only equivalent.
            @Suppress("DEPRECATION")
            builder.setDeviceCredentialAllowed(true)
        }
        return builder.build()
    }

    private fun hasAuthenticator(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BiometricManager.from(activity).canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            ) == BiometricManager.BIOMETRIC_SUCCESS
        } else {
            // On API 29 the device credential is always the fallback, so a secure
            // lock screen is exactly the precondition the prompt needs.
            activity.getSystemService(KeyguardManager::class.java)?.isDeviceSecure == true
        }
    }
}
