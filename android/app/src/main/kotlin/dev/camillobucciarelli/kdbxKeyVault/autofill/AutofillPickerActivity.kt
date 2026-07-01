package dev.camillobucciarelli.kdbxKeyVault.autofill

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.Gravity
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.AdapterView
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.RemoteViews
import android.widget.TextView
import android.widget.Toast
import dev.camillobucciarelli.kdbxKeyVault.R

class AutofillPickerActivity : Activity() {
    private lateinit var store: AndroidAutofillStore
    private lateinit var usernameIds: ArrayList<AutofillId>
    private lateinit var passwordIds: ArrayList<AutofillId>
    private lateinit var targets: List<AndroidAutofillServiceIdentifier>
    private lateinit var allEntries: List<AndroidAutofillCredentialMetadata>
    private lateinit var visibleEntries: List<AndroidAutofillCredentialMetadata>
    private var isGlobalSearch: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = AndroidAutofillStore(applicationContext)
        usernameIds = intent.autofillIdsExtra(EXTRA_USERNAME_IDS)
        passwordIds = intent.autofillIdsExtra(EXTRA_PASSWORD_IDS)
        if (usernameIds.isEmpty() && passwordIds.isEmpty()) {
            finishCanceled()
            return
        }

        val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME)
        val webDomains = intent.getStringArrayListExtra(EXTRA_WEB_DOMAINS).orEmpty()
        targets = AndroidAutofillNormalizer.normalizedRequestTargets(
            packageName = packageName,
            webDomains = webDomains,
        )
        if (targets.isEmpty()) {
            finishCanceled()
            return
        }
        allEntries = store.readCredentialMetadata()
        if (allEntries.isEmpty()) {
            finishCanceled()
            return
        }

        val strongMatches = AndroidAutofillCredentialMatcher.strongMatches(allEntries, targets)
        isGlobalSearch = targets.isNotEmpty() && strongMatches.isEmpty()
        visibleEntries = if (isGlobalSearch) {
            AndroidAutofillCredentialMatcher.possibleMatches(allEntries, targets).ifEmpty {
                allEntries.sortedBy { it.sortKey }
            }
        } else {
            strongMatches.ifEmpty { allEntries.sortedBy { it.sortKey } }
        }

        setContentView(buildContentView())
    }

    private fun buildContentView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 16)
        }

        val title = TextView(this).apply {
            text = if (isGlobalSearch) {
                getString(R.string.autofill_picker_no_exact_match_title)
            } else {
                getString(R.string.autofill_picker_exact_match_title)
            }
            textSize = 20f
            gravity = Gravity.START
        }
        root.addView(title)

        val subtitle = TextView(this).apply {
            text = if (isGlobalSearch) {
                getString(R.string.autofill_picker_no_exact_match_subtitle)
            } else {
                getString(R.string.autofill_picker_exact_match_subtitle)
            }
            textSize = 14f
            setPadding(0, 8, 0, 16)
        }
        root.addView(subtitle)

        val search = EditText(this).apply {
            hint = getString(R.string.autofill_picker_search_hint)
            isSingleLine = true
        }
        root.addView(
            search,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        val adapter = CredentialAdapter(this)
        val list = ListView(this).apply {
            this.adapter = adapter
            onItemClickListener = AdapterView.OnItemClickListener { _, _, position, _ ->
                visibleEntries.getOrNull(position)?.let(::selectCredential)
            }
        }
        root.addView(
            list,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        fun updateList(query: String = "") {
            visibleEntries = when {
                query.isNotBlank() -> AndroidAutofillCredentialMatcher.search(
                    if (isGlobalSearch) {
                        allEntries
                    } else {
                        AndroidAutofillCredentialMatcher.strongMatches(allEntries, targets).ifEmpty {
                            allEntries.sortedBy { it.sortKey }
                        }
                    },
                    query,
                )
                isGlobalSearch -> AndroidAutofillCredentialMatcher.possibleMatches(allEntries, targets).ifEmpty {
                    allEntries.sortedBy { it.sortKey }
                }
                else -> AndroidAutofillCredentialMatcher.strongMatches(allEntries, targets).ifEmpty {
                    allEntries.sortedBy { it.sortKey }
                }
            }
            adapter.replace(visibleEntries, isGlobalSearch)
        }
        search.addTextChangedListener(
            SimpleTextWatcher { text -> updateList(text) },
        )
        updateList()

        return root
    }

    private fun selectCredential(metadata: AndroidAutofillCredentialMetadata) {
        val secret = runCatching { store.readCredentialSecret(metadata.id) }
            .onFailure { Toast.makeText(this, R.string.autofill_picker_secret_error, Toast.LENGTH_SHORT).show() }
            .getOrNull()
        if (secret == null) {
            finishCanceled()
            return
        }

        val dataset = Dataset.Builder(presentation(metadata.title.ifEmpty { metadata.displayService }))
            .apply {
                val usernameValue = AutofillValue.forText(secret.username)
                val passwordValue = AutofillValue.forText(secret.password)
                for (id in usernameIds) {
                    setValue(id, usernameValue)
                }
                for (id in passwordIds) {
                    setValue(id, passwordValue)
                }
            }
            .build()

        if (isGlobalSearch && !AndroidAutofillCredentialMatcher.isStrongMatch(metadata, targets)) {
            store.savePendingAssociation(metadata = metadata, requestedTargets = targets)
        }

        val result = Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, dataset)
        setResult(RESULT_OK, result)
        finish()
    }

    private fun presentation(text: String): RemoteViews {
        return RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
            setTextViewText(android.R.id.text1, text.ifBlank { getString(R.string.autofill_dataset_selected) })
        }
    }

    private fun finishCanceled() {
        setResult(RESULT_CANCELED)
        finish()
    }

    private class CredentialAdapter(private val context: Context) : BaseAdapter() {
        private val rows = mutableListOf<CredentialRow>()

        fun replace(entries: List<AndroidAutofillCredentialMetadata>, possible: Boolean) {
            rows.clear()
            rows.addAll(entries.map { entry -> rowFor(entry, possible) })
            notifyDataSetChanged()
        }

        override fun getCount(): Int = rows.size

        override fun getItem(position: Int): Any = rows[position]

        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: android.view.ViewGroup?): View {
            val row = rows[position]
            val root = (convertView as? LinearLayout) ?: LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(8, 14, 8, 14)
                addView(TextView(context).apply { id = android.R.id.text1; textSize = 16f })
                addView(TextView(context).apply { id = android.R.id.text2; textSize = 13f })
            }
            root.findViewById<TextView>(android.R.id.text1).text = row.title
            root.findViewById<TextView>(android.R.id.text2).text = row.subtitle
            return root
        }

        private fun rowFor(
            entry: AndroidAutofillCredentialMetadata,
            possible: Boolean,
        ): CredentialRow {
            val title = entry.title.ifEmpty { "Untitled" }
            val subtitleParts = buildList {
                if (entry.username.isNotBlank()) add(entry.username)
                if (entry.displayService.isNotBlank()) add(entry.displayService)
                if (possible) add("Possible match — not linked")
            }
            return CredentialRow(
                title = title,
                subtitle = subtitleParts.joinToString(separator = " · "),
            )
        }

        private data class CredentialRow(val title: String, val subtitle: String)
    }

    private class SimpleTextWatcher(
        private val onChanged: (String) -> Unit,
    ) : android.text.TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            onChanged(s?.toString().orEmpty())
        }
        override fun afterTextChanged(s: android.text.Editable?) = Unit
    }

    private fun Intent.autofillIdsExtra(name: String): ArrayList<AutofillId> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableArrayListExtra(name, AutofillId::class.java) ?: arrayListOf()
        } else {
            @Suppress("DEPRECATION")
            getParcelableArrayListExtra(name) ?: arrayListOf()
        }
    }

    companion object {
        private const val EXTRA_USERNAME_IDS = "username_ids"
        private const val EXTRA_PASSWORD_IDS = "password_ids"
        private const val EXTRA_PACKAGE_NAME = "package_name"
        private const val EXTRA_WEB_DOMAINS = "web_domains"
        fun createIntent(
            context: Context,
            usernameIds: List<AutofillId>,
            passwordIds: List<AutofillId>,
            packageName: String?,
            webDomains: List<String>,
        ): Intent {
            return Intent(context, AutofillPickerActivity::class.java)
                .putParcelableArrayListExtra(EXTRA_USERNAME_IDS, ArrayList(usernameIds))
                .putParcelableArrayListExtra(EXTRA_PASSWORD_IDS, ArrayList(passwordIds))
                .putExtra(EXTRA_PACKAGE_NAME, packageName)
                .putStringArrayListExtra(EXTRA_WEB_DOMAINS, ArrayList(webDomains))
                .addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY)
        }
    }
}
