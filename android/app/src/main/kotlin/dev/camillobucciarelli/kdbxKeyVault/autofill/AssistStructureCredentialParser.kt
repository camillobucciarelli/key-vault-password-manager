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
}

internal data class ParsedAutofillField(
    val autofillId: AutofillId,
    val kind: CredentialFieldKind,
)

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

        return ParsedAutofillField(autofillId = autofillId, kind = kind)
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
