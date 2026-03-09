package dev.camillobucciarelli.kdbxKeyVault

import io.flutter.embedding.android.FlutterFragmentActivity

class AutofillActivity : FlutterFragmentActivity() {
    override fun getDartEntrypointFunctionName(): String {
        return "autofillEntryPoint"
    }
}
