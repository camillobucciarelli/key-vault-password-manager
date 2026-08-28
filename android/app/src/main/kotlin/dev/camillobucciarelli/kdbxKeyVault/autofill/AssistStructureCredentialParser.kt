package dev.camillobucciarelli.kdbxKeyVault.autofill

import android.app.assist.AssistStructure
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import java.util.Locale

internal data class ParsedAutofillStructure(
    val packageName: String?,
    val webDomains: Set<String>,
    val fields: List<ParsedAutofillField>,
) {
    val usernameFields: List<ParsedAutofillField>
        get() = fields.filter { it.kind == CredentialFieldKind.Username }

    val passwordFields: List<ParsedAutofillField>
        get() = fields.filter { it.kind == CredentialFieldKind.Password }

    val hasCredentialFields: Boolean
        get() = usernameFields.isNotEmpty() || passwordFields.isNotEmpty()

    /** The submitted values, stripped of the Android types. */
    val submittedFields: List<CredentialFieldValue>
        get() = fields.map { CredentialFieldValue(kind = it.kind, value = it.value) }
}

internal data class ParsedAutofillField(
    val autofillId: AutofillId,
    val kind: CredentialFieldKind,
    /** What the field holds. Empty on a fill request; set on a save request. */
    val value: String = "",
) {
    override fun toString(): String {
        return "ParsedAutofillField(autofillId=$autofillId, kind=$kind, value=<redacted>)"
    }
}

/** One submitted field, without the Android types, so the rules below are unit-testable. */
internal data class CredentialFieldValue(val kind: CredentialFieldKind, val value: String) {
    override fun toString(): String = "CredentialFieldValue(kind=$kind, value=<redacted>)"
}

internal data class SubmittedCredential(val username: String, val password: String) {
    override fun toString(): String = "SubmittedCredential(username=<redacted>, password=<redacted>)"
}

/**
 * Turns the fields of a submitted form into the one credential worth saving.
 *
 * A sign-up screen shows "new password" and "confirm password"; a
 * change-password screen adds "current password". Both collapse to a single
 * value by picking the password that was typed most often, latest wins on a
 * tie: on the first shape that is the confirmed password, on the second it is
 * the new one rather than the old.
 */
internal object SubmittedCredentialExtractor {
    fun extract(fields: List<CredentialFieldValue>): SubmittedCredential? {
        val passwords = fields
            .filter { it.kind == CredentialFieldKind.Password }
            .map { it.value }
            .filter { it.isNotEmpty() }
        if (passwords.isEmpty()) {
            return null
        }

        val occurrences = passwords.groupingBy { it }.eachCount()
        val mostTyped = occurrences.values.max()
        val password = passwords.last { occurrences[it] == mostTyped }

        val username = fields
            .firstOrNull { it.kind == CredentialFieldKind.Username && it.value.isNotBlank() }
            ?.value
            ?.trim()
            .orEmpty()

        return SubmittedCredential(username = username, password = password)
    }
}

internal object AssistStructureCredentialParser {
    private val relevantHtmlAttributes = setOf(
        "autocomplete",
        "type",
        "name",
        "id",
        "aria-label",
        "placeholder",
    )

    fun parse(structure: AssistStructure): ParsedAutofillStructure {
        val fields = mutableListOf<ParsedAutofillField>()
        val webDomains = linkedSetOf<String>()

        for (index in 0 until structure.windowNodeCount) {
            parseNode(
                node = structure.getWindowNodeAt(index).rootViewNode,
                fields = fields,
                webDomains = webDomains,
            )
        }

        return ParsedAutofillStructure(
            packageName = structure.activityComponent?.packageName,
            webDomains = webDomains,
            fields = fields,
        )
    }

    private fun parseNode(
        node: AssistStructure.ViewNode,
        fields: MutableList<ParsedAutofillField>,
        webDomains: MutableSet<String>,
    ) {
        normalizeWebDomain(node.webDomain)?.let(webDomains::add)
        parseField(node)?.let(fields::add)

        for (index in 0 until node.childCount) {
            parseNode(
                node = node.getChildAt(index),
                fields = fields,
                webDomains = webDomains,
            )
        }
    }

    private fun parseField(node: AssistStructure.ViewNode): ParsedAutofillField? {
        val autofillId = node.autofillId ?: return null
        if (!node.mayAcceptText()) {
            return null
        }

        val kinds = CredentialFieldHeuristics.classify(node.toCredentialSignals())
        val kind = when {
            CredentialFieldKind.Password in kinds -> CredentialFieldKind.Password
            CredentialFieldKind.Username in kinds -> CredentialFieldKind.Username
            else -> return null
        }

        return ParsedAutofillField(
            autofillId = autofillId,
            kind = kind,
            value = node.submittedValue(),
        )
    }

    /** Empty during a fill request; the typed text during a save request. */
    private fun AssistStructure.ViewNode.submittedValue(): String {
        val autofillValue = autofillValue
        if (autofillValue != null && autofillValue.isText) {
            return autofillValue.textValue?.toString().orEmpty()
        }
        return text?.toString().orEmpty()
    }

    private fun AssistStructure.ViewNode.mayAcceptText(): Boolean {
        return autofillType == View.AUTOFILL_TYPE_TEXT ||
            inputType != 0 ||
            !autofillHints.isNullOrEmpty()
    }

    private fun AssistStructure.ViewNode.toCredentialSignals(): CredentialFieldSignals {
        return CredentialFieldSignals(
            autofillHints = autofillHints.orEmpty().toList(),
            hint = hint,
            idEntry = idEntry,
            className = className?.toString(),
            htmlTag = htmlInfo?.tag,
            htmlAttributes = htmlAttributes(),
            isPasswordInputType = inputType.isPasswordInputType(),
            isEmailInputType = inputType.isEmailInputType(),
        )
    }

    private fun AssistStructure.ViewNode.htmlAttributes(): Map<String, String> {
        val attributes = htmlInfo?.attributes ?: return emptyMap()
        val result = linkedMapOf<String, String>()
        attributes.forEach { pair ->
            val key = pair.first ?: return@forEach
            val value = pair.second ?: return@forEach
            val normalizedKey = key.lowercase(Locale.ROOT)
            if (normalizedKey in relevantHtmlAttributes) {
                result[normalizedKey] = value
            }
        }
        return result
    }

    private fun Int.isPasswordInputType(): Boolean {
        val inputClass = this and InputType.TYPE_MASK_CLASS
        val variation = this and InputType.TYPE_MASK_VARIATION
        return when (inputClass) {
            InputType.TYPE_CLASS_TEXT -> variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
            InputType.TYPE_CLASS_NUMBER -> variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
            else -> false
        }
    }

    private fun Int.isEmailInputType(): Boolean {
        val inputClass = this and InputType.TYPE_MASK_CLASS
        val variation = this and InputType.TYPE_MASK_VARIATION
        return inputClass == InputType.TYPE_CLASS_TEXT &&
            (variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS)
    }

    private fun normalizeWebDomain(value: String?): String? =
        AndroidAutofillNormalizer.normalizedHost(value)
}
