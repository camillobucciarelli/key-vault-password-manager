package dev.camillobucciarelli.kdbxKeyVault.autofill

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class AndroidAutofillV2Channel(context: Context) {
    private val store = AndroidAutofillStore(context)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "publishCredentials" -> handlePublishCredentials(call.arguments, result)
                "clearCredentials" -> handleClearCredentials(call.arguments, result)
                "readPendingAssociations" -> result.success(
                    store.readPendingAssociations().map(AndroidAutofillJson::pendingAssociationToMap),
                )
                "clearPendingAssociations" -> handleClearPendingAssociations(call.arguments, result)
                "getStatus" -> result.success(statusMap())
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            Log.w(TAG, "Android Autofill channel failed: ${error.javaClass.simpleName}")
            result.error("android_autofill_v2_failed", error.message, null)
        }
    }

    private fun handlePublishCredentials(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *> ?: throw IllegalArgumentException("arguments must be a map")
        val databaseId = args["databaseId"] as? String
            ?: throw IllegalArgumentException("databaseId must be a string")
        val rawEntries = args["entries"] as? List<*>
            ?: throw IllegalArgumentException("entries must be a list")
        val entries = rawEntries.map(::parsePublishEntry)
        val authSessionTtlMs = parseAuthSessionTtlMs(args["authSessionTtlMs"])
        Log.i(TAG, "publishCredentials received entryCount=${entries.size}")
        result.success(
            store.publishCredentials(
                databaseId = databaseId,
                entries = entries,
                authSessionTtlMs = authSessionTtlMs,
            ),
        )
    }

    private fun handleClearCredentials(arguments: Any?, result: MethodChannel.Result) {
        val databaseId = (arguments as? Map<*, *>)?.get("databaseId") as? String
        Log.i(TAG, "clearCredentials received hasDatabaseId=${databaseId != null}")
        result.success(store.clearCredentials(databaseId = databaseId))
    }

    private fun handleClearPendingAssociations(arguments: Any?, result: MethodChannel.Result) {
        val ids = ((arguments as? Map<*, *>)?.get("ids") as? List<*>)
            ?.mapNotNull { it as? String }
        val clearedCount = store.clearPendingAssociations(ids = ids)
        result.success(mapOf("clearedCount" to clearedCount, "warnings" to emptyList<String>()))
    }

    private fun parseAuthSessionTtlMs(rawValue: Any?): Long {
        val value = when (rawValue) {
            null -> 0L
            is Int -> rawValue.toLong()
            is Long -> rawValue
            else -> throw IllegalArgumentException("authSessionTtlMs must be an integer")
        }
        require(value >= 0L) { "authSessionTtlMs must not be negative" }
        return value
    }

    private fun statusMap(): Map<String, Any?> {
        val status = store.status()
        return mapOf(
            "version" to ANDROID_AUTOFILL_CACHE_VERSION,
            "appGroupAvailable" to true,
            "keychainAccessGroupAvailable" to true,
            "metadataCount" to status.metadataCount,
            "encryptedCacheAvailable" to status.encryptedCacheAvailable,
            "cacheAvailable" to status.cacheAvailable,
            "databaseId" to status.databaseId,
            "generatedAtEpochMs" to status.generatedAtEpochMs,
            "authSessionTtlMs" to status.authSessionTtlMs,
            "lastAuthenticatedAtEpochMs" to status.lastAuthenticatedAtEpochMs,
        )
    }

    private fun parsePublishEntry(rawValue: Any?): AndroidAutofillPublishEntry {
        val map = rawValue as? Map<*, *> ?: throw IllegalArgumentException("entry must be a map")
        return AndroidAutofillPublishEntry(
            id = map["id"] as? String ?: throw IllegalArgumentException("entry.id must be a string"),
            title = map["title"] as? String ?: "",
            username = map["username"] as? String ?: "",
            password = map["password"] as? String
                ?: throw IllegalArgumentException("entry.password must be a string"),
            url = map["url"] as? String,
            serviceIdentifiers = parseServiceIdentifiers(map["serviceIdentifiers"]),
        )
    }

    private fun parseServiceIdentifiers(rawValue: Any?): List<AndroidAutofillServiceIdentifier> {
        val rawList = rawValue as? List<*> ?: return emptyList()
        return rawList.mapNotNull { rawIdentifier ->
            val map = rawIdentifier as? Map<*, *> ?: return@mapNotNull null
            val rawType = map["type"] as? String ?: return@mapNotNull null
            val type = AndroidAutofillServiceIdentifierType.fromRawValue(rawType) ?: return@mapNotNull null
            val value = (map["value"] as? String)?.trim().orEmpty()
            if (value.isEmpty()) {
                null
            } else {
                AndroidAutofillServiceIdentifier(type = type, value = value)
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "dev.camillobucciarelli.keyvault/apple_autofill_v2"
        private const val TAG = "KeyVaultAutofill"
    }
}
