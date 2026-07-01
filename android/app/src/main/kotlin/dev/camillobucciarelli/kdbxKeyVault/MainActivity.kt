package dev.camillobucciarelli.kdbxKeyVault

import dev.camillobucciarelli.kdbxKeyVault.autofill.AndroidAutofillV2Channel
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channelHandler = AndroidAutofillV2Channel(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AndroidAutofillV2Channel.CHANNEL_NAME,
        ).setMethodCallHandler(channelHandler::handle)
    }
}
