package dev.camillobucciarelli.kdbxKeyVault.autofill

internal object AndroidAutofillCredentialMatcher {
    private const val PossibleMatchLimit = 50
    private const val ManualSearchDefaultLimit = 100
    private const val ManualSearchOneCharacterLimit = 20

    fun strongMatches(
        entries: List<AndroidAutofillCredentialMetadata>,
        targets: List<AndroidAutofillServiceIdentifier>,
    ): List<AndroidAutofillCredentialMetadata> {
        if (targets.isEmpty()) {
            return emptyList()
        }
        return entries
            .filter { entry -> isStrongMatch(entry, targets) }
            .sortedBy { it.sortKey }
    }

    fun possibleMatches(
        entries: List<AndroidAutofillCredentialMetadata>,
        targets: List<AndroidAutofillServiceIdentifier>,
        limit: Int = PossibleMatchLimit,
    ): List<AndroidAutofillCredentialMetadata> {
        val tokens = AndroidAutofillNormalizer.targetTokens(targets)
        if (tokens.isEmpty()) {
            return emptyList()
        }
        return ranked(
            entries = entries,
            tokens = tokens,
            mode = SearchMode.TargetSuggestion,
            requireAllTokens = false,
            limit = limit,
        )
    }

    fun search(
        entries: List<AndroidAutofillCredentialMetadata>,
        query: String,
        limit: Int? = null,
    ): List<AndroidAutofillCredentialMetadata> {
        val tokens = manualSearchTokens(query)
        if (tokens.isEmpty()) {
            return entries.sortedBy { it.sortKey }
        }
        val normalizedQuery = AndroidAutofillNormalizer.normalizedSearchValue(query)
        val effectiveLimit = limit ?: if (normalizedQuery.length == 1) {
            ManualSearchOneCharacterLimit
        } else {
            ManualSearchDefaultLimit
        }
        return ranked(
            entries = entries,
            tokens = tokens,
            mode = SearchMode.ManualSearch,
            requireAllTokens = true,
            limit = effectiveLimit,
        )
    }

    fun isStrongMatch(
        entry: AndroidAutofillCredentialMetadata,
        targets: List<AndroidAutofillServiceIdentifier>,
    ): Boolean {
        for (target in targets) {
            for (identifier in entry.serviceIdentifiers) {
                if (strongIdentifierMatch(identifier, target)) {
                    return true
                }
            }
        }
        return false
    }

    private fun strongIdentifierMatch(
        entry: AndroidAutofillServiceIdentifier,
        target: AndroidAutofillServiceIdentifier,
    ): Boolean {
        if (target.type == AndroidAutofillServiceIdentifierType.AndroidPackage ||
            entry.type == AndroidAutofillServiceIdentifierType.AndroidPackage
        ) {
            return target.type == AndroidAutofillServiceIdentifierType.AndroidPackage &&
                entry.type == AndroidAutofillServiceIdentifierType.AndroidPackage &&
                entry.value == target.value
        }

        val entryHost = AndroidAutofillNormalizer.normalizedHost(entry.value) ?: return false
        val targetHost = AndroidAutofillNormalizer.normalizedHost(target.value) ?: return false
        return entryHost == targetHost
    }

    private enum class SearchMode { TargetSuggestion, ManualSearch }

    private data class WeightedSearchField(val value: String, val weight: Int)

    private fun ranked(
        entries: List<AndroidAutofillCredentialMetadata>,
        tokens: List<String>,
        mode: SearchMode,
        requireAllTokens: Boolean,
        limit: Int,
    ): List<AndroidAutofillCredentialMetadata> {
        if (limit <= 0) {
            return emptyList()
        }

        return entries
            .mapNotNull { entry ->
                val score = scoreEntry(
                    fields = searchFields(entry, mode),
                    tokens = tokens,
                    requireAllTokens = requireAllTokens,
                )
                if (score > 0) entry to score else null
            }
            .sortedWith(compareByDescending<Pair<AndroidAutofillCredentialMetadata, Int>> { it.second }
                .thenBy { it.first.sortKey })
            .take(limit)
            .map { it.first }
    }

    private fun scoreEntry(
        fields: List<WeightedSearchField>,
        tokens: List<String>,
        requireAllTokens: Boolean,
    ): Int {
        var total = 0
        var matchedTokens = 0

        for (token in tokens) {
            val bestScore = fields.mapNotNull { field ->
                val value = AndroidAutofillNormalizer.normalizedSearchValue(field.value)
                if (!value.contains(token)) {
                    null
                } else {
                    var score = field.weight
                    if (value == token) {
                        score += 12
                    } else if (value.startsWith(token)) {
                        score += 6
                    } else if (containsComponentPrefix(token, value)) {
                        score += 4
                    }
                    score
                }
            }.maxOrNull()

            if (bestScore != null) {
                total += bestScore
                matchedTokens += 1
            } else if (requireAllTokens) {
                return 0
            }
        }

        return if (matchedTokens > 0) total + (matchedTokens * 2) else 0
    }

    private fun searchFields(
        entry: AndroidAutofillCredentialMetadata,
        mode: SearchMode,
    ): List<WeightedSearchField> {
        val fields = mutableListOf(
            WeightedSearchField(entry.title, 6),
            WeightedSearchField(entry.displayService, 8),
        )
        if (mode == SearchMode.ManualSearch) {
            fields.add(WeightedSearchField(entry.username, 5))
        }
        for (identifier in entry.serviceIdentifiers) {
            fields.add(WeightedSearchField(identifier.value, 9))
            if (identifier.type == AndroidAutofillServiceIdentifierType.Domain ||
                identifier.type == AndroidAutofillServiceIdentifierType.Url
            ) {
                AndroidAutofillNormalizer.normalizedHost(identifier.value)?.let { host ->
                    fields.add(WeightedSearchField(host, 10))
                }
            }
        }
        return uniqueFields(fields)
    }

    private fun manualSearchTokens(query: String): List<String> {
        val normalized = AndroidAutofillNormalizer.normalizedSearchValue(query)
        if (normalized.isEmpty()) {
            return emptyList()
        }
        val split = normalized
            .split(Regex("\\s+"))
            .filter { it.isNotEmpty() }
        return (split.ifEmpty { listOf(normalized) }).distinct()
    }

    private fun containsComponentPrefix(token: String, value: String): Boolean {
        return value
            .split(Regex("[.\\-_/:\\\\\\s]+"))
            .any { it.startsWith(token) }
    }

    private fun uniqueFields(fields: List<WeightedSearchField>): List<WeightedSearchField> {
        val bestByValue = linkedMapOf<String, WeightedSearchField>()
        for (field in fields) {
            val key = AndroidAutofillNormalizer.normalizedSearchValue(field.value)
            if (key.isEmpty()) {
                continue
            }
            val existing = bestByValue[key]
            if (existing == null || field.weight > existing.weight) {
                bestByValue[key] = field
            }
        }
        return bestByValue.values.toList()
    }
}
