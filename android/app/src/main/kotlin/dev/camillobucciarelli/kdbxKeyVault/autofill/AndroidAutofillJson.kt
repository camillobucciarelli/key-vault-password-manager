package dev.camillobucciarelli.kdbxKeyVault.autofill

import org.json.JSONArray
import org.json.JSONObject

internal object AndroidAutofillJson {
    fun metadataCacheToJson(cache: AndroidAutofillMetadataCache): String {
        return JSONObject()
            .put("version", cache.version)
            .put("databaseId", cache.databaseId)
            .put("generatedAtEpochMs", cache.generatedAtEpochMs)
            .put("entries", JSONArray(cache.entries.map(::metadataToJson)))
            .toString()
    }

    fun metadataCacheFromJson(value: String): AndroidAutofillMetadataCache {
        val json = JSONObject(value)
        val entriesJson = json.optJSONArray("entries") ?: JSONArray()
        val entries = buildList {
            for (index in 0 until entriesJson.length()) {
                val item = entriesJson.optJSONObject(index) ?: continue
                add(metadataFromJson(item))
            }
        }
        return AndroidAutofillMetadataCache(
            version = json.optInt("version"),
            databaseId = json.optString("databaseId"),
            generatedAtEpochMs = json.optLong("generatedAtEpochMs"),
            entries = entries,
        )
    }

    fun secretsToJson(
        version: Int,
        databaseId: String,
        generatedAtEpochMs: Long,
        entries: List<AndroidAutofillCredentialSecret>,
    ): String {
        return JSONObject()
            .put("version", version)
            .put("databaseId", databaseId)
            .put("generatedAtEpochMs", generatedAtEpochMs)
            .put(
                "entries",
                JSONArray(entries.map { secret ->
                    JSONObject()
                        .put("id", secret.id)
                        .put("username", secret.username)
                        .put("password", secret.password)
                }),
            )
            .toString()
    }

    fun secretsFromJson(value: String): Triple<Int, String, List<AndroidAutofillCredentialSecret>> {
        val json = JSONObject(value)
        val entriesJson = json.optJSONArray("entries") ?: JSONArray()
        val entries = buildList {
            for (index in 0 until entriesJson.length()) {
                val item = entriesJson.optJSONObject(index) ?: continue
                add(
                    AndroidAutofillCredentialSecret(
                        id = item.optString("id"),
                        username = item.optString("username"),
                        password = item.optString("password"),
                    ),
                )
            }
        }
        return Triple(json.optInt("version"), json.optString("databaseId"), entries)
    }

    fun pendingAssociationsToJson(associations: List<AndroidAutofillPendingAssociation>): String {
        return JSONArray(associations.map(::pendingAssociationToJson)).toString()
    }

    fun pendingAssociationsFromJson(value: String): List<AndroidAutofillPendingAssociation> {
        val array = JSONArray(value)
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    AndroidAutofillPendingAssociation(
                        id = item.optString("id"),
                        databaseId = item.optString("databaseId"),
                        entryId = item.optString("entryId"),
                        serviceIdentifierType = item.optString("serviceIdentifierType"),
                        serviceIdentifierValue = item.optString("serviceIdentifierValue"),
                        displayService = item.optString("displayService"),
                        createdAtEpochMs = item.optLong("createdAtEpochMs"),
                        platform = item.optString("platform", "android"),
                    ),
                )
            }
        }
    }

    fun pendingAssociationToMap(association: AndroidAutofillPendingAssociation): Map<String, Any> {
        return mapOf(
            "id" to association.id,
            "databaseId" to association.databaseId,
            "entryId" to association.entryId,
            "serviceIdentifierType" to association.serviceIdentifierType,
            "serviceIdentifierValue" to association.serviceIdentifierValue,
            "displayService" to association.displayService,
            "createdAtEpochMs" to association.createdAtEpochMs,
            "platform" to association.platform,
        )
    }

    private fun metadataToJson(metadata: AndroidAutofillCredentialMetadata): JSONObject {
        return JSONObject()
            .put("id", metadata.id)
            .put("title", metadata.title)
            .put("username", metadata.username)
            .put("displayService", metadata.displayService)
            .put("updatedAtEpochMs", metadata.updatedAtEpochMs)
            .put("serviceIdentifiers", JSONArray(metadata.serviceIdentifiers.map(::identifierToJson)))
    }

    private fun metadataFromJson(json: JSONObject): AndroidAutofillCredentialMetadata {
        val identifiersJson = json.optJSONArray("serviceIdentifiers") ?: JSONArray()
        val identifiers = buildList {
            for (index in 0 until identifiersJson.length()) {
                val item = identifiersJson.optJSONObject(index) ?: continue
                identifierFromJson(item)?.let(::add)
            }
        }
        return AndroidAutofillCredentialMetadata(
            id = json.optString("id"),
            title = json.optString("title"),
            username = json.optString("username"),
            displayService = json.optString("displayService"),
            serviceIdentifiers = identifiers,
            updatedAtEpochMs = json.optLong("updatedAtEpochMs"),
        )
    }

    private fun identifierToJson(identifier: AndroidAutofillServiceIdentifier): JSONObject {
        return JSONObject()
            .put("type", identifier.type.rawValue)
            .put("value", identifier.value)
    }

    private fun identifierFromJson(json: JSONObject): AndroidAutofillServiceIdentifier? {
        val type = AndroidAutofillServiceIdentifierType.fromRawValue(json.optString("type"))
            ?: return null
        val value = json.optString("value").trim()
        if (value.isEmpty()) {
            return null
        }
        return AndroidAutofillServiceIdentifier(type = type, value = value)
    }

    private fun pendingAssociationToJson(association: AndroidAutofillPendingAssociation): JSONObject {
        return JSONObject()
            .put("id", association.id)
            .put("databaseId", association.databaseId)
            .put("entryId", association.entryId)
            .put("serviceIdentifierType", association.serviceIdentifierType)
            .put("serviceIdentifierValue", association.serviceIdentifierValue)
            .put("displayService", association.displayService)
            .put("createdAtEpochMs", association.createdAtEpochMs)
            .put("platform", association.platform)
    }
}
