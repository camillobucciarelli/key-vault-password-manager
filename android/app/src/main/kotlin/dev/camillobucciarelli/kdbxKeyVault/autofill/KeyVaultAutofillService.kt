package dev.camillobucciarelli.kdbxKeyVault.autofill

import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest

/**
 * Native Android Autofill v2 shell.
 *
 * This service intentionally returns no datasets until the Flutter/domain v2
 * vault bridge is designed. It never reads KDBX data, master passwords, or
 * credentials from native Android code.
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

        request.fillContexts.lastOrNull()?.structure?.let { structure ->
            AssistStructureCredentialParser.parse(structure)
                .takeIf { it.hasCredentialFields }
                ?.let {
                    // Future hook: hand off a sanitized request target to Flutter
                    // Autofill v2. Do not create credential datasets here yet.
                    Unit
                }
        }

        if (!cancellationSignal.isCanceled) {
            callback.onSuccess(null)
        }
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Save flows are disabled until the v2 vault bridge exists.
        callback.onSuccess()
    }
}
