package dev.camillobucciarelli.kdbxKeyVault.autofill

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.AdapterView
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.ListView
import android.widget.RemoteViews
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.FragmentActivity
import dev.camillobucciarelli.kdbxKeyVault.R

class AutofillPickerActivity : FragmentActivity() {
    private lateinit var store: AndroidAutofillStore
    private lateinit var authGate: AutofillAuthGate
    private var isAuthenticating: Boolean = false
    private lateinit var usernameIds: ArrayList<AutofillId>
    private lateinit var passwordIds: ArrayList<AutofillId>
    private lateinit var targets: List<AndroidAutofillServiceIdentifier>
    private lateinit var allEntries: List<AndroidAutofillCredentialMetadata>
    private lateinit var visibleEntries: List<AndroidAutofillCredentialMetadata>
    private var isGlobalSearch: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = AndroidAutofillStore(applicationContext)
        authGate = AutofillAuthGate(activity = this, store = store)
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

        bindContentView()
    }

    private fun bindContentView() {
        setContentView(R.layout.autofill_picker_activity)

        findViewById<TextView>(R.id.autofill_picker_title).text = if (isGlobalSearch) {
            getString(R.string.autofill_picker_no_exact_match_title)
        } else {
            getString(R.string.autofill_picker_exact_match_title)
        }
        findViewById<TextView>(R.id.autofill_picker_subtitle).text = if (isGlobalSearch) {
            getString(R.string.autofill_picker_no_exact_match_subtitle)
        } else {
            getString(R.string.autofill_picker_exact_match_subtitle)
        }

        val adapter = CredentialAdapter(this)
        val list = findViewById<ListView>(R.id.autofill_picker_list).apply {
            this.adapter = adapter
            contentDescription = getString(R.string.autofill_picker_list_description)
            onItemClickListener = AdapterView.OnItemClickListener { _, _, position, _ ->
                visibleEntries.getOrNull(position)?.let(::selectCredential)
            }
        }

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

        findViewById<EditText>(R.id.autofill_picker_search).addTextChangedListener(
            SimpleTextWatcher { text -> updateList(text) },
        )
        updateList()
        list.requestFocus()
    }

    private fun selectCredential(metadata: AndroidAutofillCredentialMetadata) {
        if (isAuthenticating) {
            return
        }
        isAuthenticating = true
        authGate.authenticate { outcome ->
            isAuthenticating = false
            when (outcome) {
                AutofillAuthGate.Outcome.Authenticated -> releaseCredential(metadata)
                AutofillAuthGate.Outcome.NoAuthenticator -> {
                    Toast.makeText(this, R.string.autofill_auth_required_error, Toast.LENGTH_LONG).show()
                    finishCanceled()
                }
                AutofillAuthGate.Outcome.Cancelled -> {
                    Toast.makeText(this, R.string.autofill_auth_cancelled, Toast.LENGTH_SHORT).show()
                    finishCanceled()
                }
            }
        }
    }

    /** Only ever reached after [AutofillAuthGate] reports a successful authentication. */
    private fun releaseCredential(metadata: AndroidAutofillCredentialMetadata) {
        val secret = runCatching { store.readCredentialSecret(metadata.id) }
            .onFailure { Toast.makeText(this, R.string.autofill_picker_secret_error, Toast.LENGTH_SHORT).show() }
            .getOrNull()
        if (secret == null) {
            // The cache went away, was republished for another database, or no
            // longer holds this entry between the prompt and the release.
            Toast.makeText(this, R.string.autofill_picker_secret_error, Toast.LENGTH_SHORT).show()
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
        private val inflater = LayoutInflater.from(context)

        fun replace(entries: List<AndroidAutofillCredentialMetadata>, possible: Boolean) {
            rows.clear()
            rows.addAll(entries.map { entry -> rowFor(entry, possible) })
            notifyDataSetChanged()
        }

        override fun getCount(): Int = rows.size

        override fun getItem(position: Int): Any = rows[position]

        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val row = rows[position]
            val view = convertView
                ?: inflater.inflate(R.layout.autofill_picker_row, parent, false)
            view.findViewById<TextView>(R.id.autofill_picker_row_title).text = row.title
            view.findViewById<TextView>(R.id.autofill_picker_row_subtitle).apply {
                text = row.subtitle
                visibility = if (row.subtitle.isEmpty()) View.GONE else View.VISIBLE
            }
            // One label for the whole row: TalkBack should announce the credential
            // once, not read two separate text nodes.
            view.contentDescription = context.getString(
                R.string.autofill_picker_row_content_description,
                row.title,
                row.subtitle,
            )
            return view
        }

        private fun rowFor(
            entry: AndroidAutofillCredentialMetadata,
            possible: Boolean,
        ): CredentialRow {
            val title = entry.title.ifEmpty { context.getString(R.string.autofill_picker_row_untitled) }
            val subtitleParts = buildList {
                if (entry.username.isNotBlank()) add(entry.username)
                if (entry.displayService.isNotBlank()) add(entry.displayService)
                if (possible) add(context.getString(R.string.autofill_picker_row_possible_match))
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
