package dev.camillobucciarelli.kdbxKeyVault.autofill

import android.app.PendingIntent
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.Dataset
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import dev.camillobucciarelli.kdbxKeyVault.MainActivity
import dev.camillobucciarelli.kdbxKeyVault.R

/** Launch action and extra carrying a save capture into the app. */
internal const val ACTION_SAVE_CAPTURE = "dev.camillobucciarelli.kdbxKeyVault.SAVE_CAPTURE"
internal const val EXTRA_CAPTURE_TOKEN = "keyvault_autofill_capture_token"

/**
 * Native Android Autofill v2 service.
 *
 * It reads only the app-published Android encrypted cache. It never opens or
 * writes KDBX files. The fill response exposes only an authenticated picker;
 * secrets are decrypted after explicit user selection.
 */
class KeyVaultAutofillService : AutofillService() {
    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        if (cancellationSignal.isCanceled) {
            return
        }

        val parsed = request.fillContexts.lastOrNull()?.structure?.let { structure ->
            AssistStructureCredentialParser.parse(structure)
        }
        if (parsed == null || !parsed.hasCredentialFields) {
            callback.onSuccess(null)
            return
        }

        val store = AndroidAutofillStore(applicationContext)
        if (store.readCredentialMetadata().isEmpty()) {
            callback.onSuccess(null)
            return
        }
        val targets = AndroidAutofillNormalizer.normalizedRequestTargets(
            packageName = parsed.packageName,
            webDomains = parsed.webDomains,
        )
        if (targets.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val intent = AutofillPickerActivity.createIntent(
            context = this,
            usernameIds = parsed.usernameFields.map { it.autofillId },
            passwordIds = parsed.passwordFields.map { it.autofillId },
            packageName = parsed.packageName,
            webDomains = parsed.webDomains.toList(),
        )
        val pendingIntent = PendingIntent.getActivity(
            this,
            request.id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val presentation = presentation(
            if (parsed.webDomains.isNotEmpty()) {
                getString(R.string.autofill_dataset_select_for_site)
            } else {
                getString(R.string.autofill_dataset_select_for_app)
            },
        )
        val dataset = Dataset.Builder(presentation)
            .setAuthentication(pendingIntent.intentSender)
            .apply {
                for (field in parsed.fields) {
                    setValue(field.autofillId, null as AutofillValue?)
                }
            }
            .build()
        val response = FillResponse.Builder()
            .addDataset(dataset)
            .apply { saveInfo(parsed)?.let(::setSaveInfo) }
            .build()

        if (!cancellationSignal.isCanceled) {
            callback.onSuccess(response)
        }
    }

    /**
     * Declares what the response is able to save. A screen with no password
     * field has nothing worth capturing, so it gets no save bar at all.
     */
    private fun saveInfo(parsed: ParsedAutofillStructure): SaveInfo? {
        val passwordIds = parsed.passwordFields.map { it.autofillId }
        if (passwordIds.isEmpty()) {
            return null
        }
        val usernameIds = parsed.usernameFields.map { it.autofillId }
        val type = if (usernameIds.isEmpty()) {
            SaveInfo.SAVE_DATA_TYPE_PASSWORD
        } else {
            SaveInfo.SAVE_DATA_TYPE_PASSWORD or SaveInfo.SAVE_DATA_TYPE_USERNAME
        }
        return SaveInfo.Builder(type, passwordIds.toTypedArray())
            .apply {
                if (usernameIds.isNotEmpty()) {
                    setOptionalIds(usernameIds.toTypedArray())
                }
            }
            .build()
    }

    /**
     * Captures the submitted credential and hands the app a token for it. The
     * password stays in this process's memory: it never reaches an `Intent`
     * extra, which would pass through the system server (research R4, D5).
     */
    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val parsed = request.fillContexts.lastOrNull()?.structure?.let { structure ->
            AssistStructureCredentialParser.parse(structure)
        }
        val submitted = parsed?.let { SubmittedCredentialExtractor.extract(it.submittedFields) }
        if (parsed == null || submitted == null) {
            callback.onSuccess()
            return
        }

        val webDomain = parsed.webDomains.firstOrNull()
        val association = webDomain ?: parsed.packageName
        val store = AndroidAutofillStore(applicationContext)
        if (store.isDeclinedSave(association, submitted.username)) {
            // The user already said no to this submission (FR-011).
            callback.onSuccess()
            return
        }

        val capture = AndroidAutofillCaptureHolder.shared.store(
            username = submitted.username,
            password = submitted.password,
            packageName = parsed.packageName,
            webDomain = webDomain,
        )
        val intent = Intent(this, MainActivity::class.java)
            .setAction(ACTION_SAVE_CAPTURE)
            .putExtra(EXTRA_CAPTURE_TOKEN, capture.token)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val pendingIntent = PendingIntent.getActivity(
            this,
            capture.token.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        callback.onSuccess(pendingIntent.intentSender)
    }

    private fun presentation(text: String): RemoteViews {
        return RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
            setTextViewText(android.R.id.text1, text)
        }
    }
}
