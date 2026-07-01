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
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import dev.camillobucciarelli.kdbxKeyVault.R

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
            .build()

        if (!cancellationSignal.isCanceled) {
            callback.onSuccess(response)
        }
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Native save flows do not write KDBX. Associations are confirmed app-side.
        callback.onSuccess()
    }

    private fun presentation(text: String): RemoteViews {
        return RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
            setTextViewText(android.R.id.text1, text)
        }
    }
}
