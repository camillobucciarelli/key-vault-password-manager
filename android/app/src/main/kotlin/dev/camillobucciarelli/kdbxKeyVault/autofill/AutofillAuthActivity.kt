package dev.camillobucciarelli.kdbxKeyVault.autofill

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.Toast
import androidx.fragment.app.FragmentActivity
import dev.camillobucciarelli.kdbxKeyVault.R

/**
 * spec-016 T402: authenticates one already-chosen credential and returns it.
 *
 * This is what an inline suggestion points at. The user picked the entry on the
 * keyboard strip, so there is nothing left to choose: the activity shows no list
 * and reveals no vault content — only the authentication prompt, and then the
 * one entry's values, straight back to the requesting app.
 *
 * It has no layout at all. Its window is transparent so the prompt appears over
 * whatever the user was looking at.
 */
class AutofillAuthActivity : FragmentActivity() {
    private var isAuthenticating = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val entryId = intent.getStringExtra(EXTRA_ENTRY_ID)
        val usernameIds = intent.autofillIdsExtra(EXTRA_USERNAME_IDS)
        val passwordIds = intent.autofillIdsExtra(EXTRA_PASSWORD_IDS)
        if (entryId.isNullOrBlank() || (usernameIds.isEmpty() && passwordIds.isEmpty())) {
            finishCanceled()
            return
        }
        if (isAuthenticating) {
            return
        }
        isAuthenticating = true

        val store = AndroidAutofillStore(applicationContext)
        AutofillAuthGate(activity = this, store = store).authenticate { outcome ->
            when (outcome) {
                AutofillAuthGate.Outcome.Authenticated ->
                    release(store, entryId, usernameIds, passwordIds)
                AutofillAuthGate.Outcome.NoAuthenticator -> {
                    Toast.makeText(this, R.string.autofill_auth_required_error, Toast.LENGTH_LONG).show()
                    finishCanceled()
                }
                AutofillAuthGate.Outcome.Cancelled -> {
                    Toast.makeText(this, R.string.autofill_auth_cancelled, Toast.LENGTH_SHORT).show()
                    finishCanceled()
                }
            }
        }
    }

    /** Only ever reached after [AutofillAuthGate] reports a successful authentication. */
    private fun release(
        store: AndroidAutofillStore,
        entryId: String,
        usernameIds: List<AutofillId>,
        passwordIds: List<AutofillId>,
    ) {
        val secret = runCatching { store.readCredentialSecret(entryId) }.getOrNull()
        if (secret == null) {
            // The cache was republished, or no longer holds this entry, between
            // the suggestion being drawn and the user tapping it.
            Toast.makeText(this, R.string.autofill_picker_secret_error, Toast.LENGTH_SHORT).show()
            finishCanceled()
            return
        }

        val metadata = store.readCredentialMetadata().firstOrNull { it.id == entryId }
        val dataset = Dataset.Builder(
            datasetPresentation(
                packageName = packageName,
                title = metadata?.title?.ifBlank { metadata.displayService }
                    ?: getString(R.string.autofill_dataset_selected),
                subtitle = secret.username,
            ),
        )
            .apply {
                val usernameValue = AutofillValue.forText(secret.username)
                val passwordValue = AutofillValue.forText(secret.password)
                for (id in usernameIds) {
                    setValue(id, usernameValue)
                }
                for (id in passwordIds) {
                    setValue(id, passwordValue)
                }
            }
            .build()

        setResult(
            RESULT_OK,
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, dataset),
        )
        finish()
    }

    private fun finishCanceled() {
        setResult(RESULT_CANCELED)
        finish()
    }

    private fun Intent.autofillIdsExtra(name: String): ArrayList<AutofillId> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableArrayListExtra(name, AutofillId::class.java) ?: arrayListOf()
        } else {
            @Suppress("DEPRECATION")
            getParcelableArrayListExtra(name) ?: arrayListOf()
        }
    }

    companion object {
        private const val EXTRA_ENTRY_ID = "entry_id"
        private const val EXTRA_USERNAME_IDS = "username_ids"
        private const val EXTRA_PASSWORD_IDS = "password_ids"

        fun createIntent(
            context: Context,
            entryId: String,
            usernameIds: List<AutofillId>,
            passwordIds: List<AutofillId>,
        ): Intent {
            return Intent(context, AutofillAuthActivity::class.java)
                .putExtra(EXTRA_ENTRY_ID, entryId)
                .putParcelableArrayListExtra(EXTRA_USERNAME_IDS, ArrayList(usernameIds))
                .putParcelableArrayListExtra(EXTRA_PASSWORD_IDS, ArrayList(passwordIds))
                .addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY)
        }
    }
}
