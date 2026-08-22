// spec-008 — the registry of the merge domain module.
//
// This exists because the first version of the Phase 2 gates hardcoded two
// literal file lists, so a *new* file in `domain/` was inspected by nothing: a
// model carrying a canonical path, a master password, a `toJson` and a
// `dart:io` import passed the whole suite. The lists are no longer written by
// hand at the point of use — both gates read this registry, and
// `sync_merge_domain_architecture_test.dart` fails if any file in `lib/`
// participates in the merge contract without being registered here.
//
// **Membership rule.** A file is part of the merge module when it mentions a
// spec-008 merge identifier (`SyncMerge*`, `Merge<Capital>*`,
// `RedactedMergeDecision`) — because a type can only reach the frozen port
// surface by naming one, extensions included. Registering it is therefore not
// optional bookkeeping: it is what selects the rules the file is judged by.
//
// **This is the only place to update.** Adding a merge file and forgetting this
// registry is a test failure, not a silent pass.

/// Bucket 1 — safe domain models. Everything here crosses the port and may
/// reach a coordinator, a BLoC state or a log line.
///
/// Rules: `Equatable` with `props`; every field, getter and static has a type
/// from the safe set; `String` only at a listed shape-validated id; no
/// serializer.
const mergeSafeModelFiles = <String>[
  'lib/features/password_manager/domain/models/sync_merge_models.dart',
];

/// Bucket 2 — the transient plaintext response. The one place plaintext is
/// allowed to exist in the domain layer, so the field/type/name rules of
/// bucket 1 deliberately do NOT apply.
///
/// Rules: not `Equatable`, no supertype, no `props`, no serializer, `toString`
/// redacted with a constant literal, and an importer allowlist.
const mergeTransientFiles = <String>[
  'lib/features/password_manager/domain/models/merge_field_display.dart',
];

/// Bucket 3 — the port, its use cases and the policy. Not `Equatable` models,
/// but they still cross the boundary and still carry state
/// (`SyncMergeFailure` is the object that reaches logs and crash telemetry), so
/// the field/getter/static and serializer rules apply here too.
const mergeContractFiles = <String>[
  'lib/features/password_manager/domain/repositories/sync_merge_repository.dart',
  'lib/features/password_manager/domain/usecases/sync_merge_usecases.dart',
  'lib/features/password_manager/domain/usecases/load_sync_merge_field_display_usecase.dart',
  'lib/features/password_manager/domain/services/sync_merge_policy.dart',
];

/// Bucket 4 — the data-layer merge implementation (Phase 3).
///
/// These files legitimately own what buckets 1-3 forbid: `KdbxFile`,
/// `Credentials`, decrypted values, attachment bytes, object UUIDs, canonical
/// paths and checksums. They are registered here **not** so the redaction rules
/// apply to them — those rules would be nonsense for a data file — but so that
/// the completeness check keeps working: a file naming a merge identifier must
/// be accounted for somewhere, and "somewhere" must be an explicit decision.
///
/// The rules that DO apply to this bucket are the boundary ones, in
/// `sync_merge_domain_architecture_test.dart`: nothing in `domain/` or
/// `presentation/` may import these files, and these files may not import
/// `presentation/`. That is the T303 secret boundary stated in the direction a
/// test can check today, before the repository implementation exists.
const mergeDataImplementationFiles = <String>[
  'lib/features/password_manager/data/services/kdbx_merge_adapter.dart',
];

/// The merge **domain** module. Both domain gates derive their scope from this,
/// so it stays domain-only: every entry must live under [mergeModuleDirectory].
const mergeModuleFiles = <String>[
  ...mergeSafeModelFiles,
  ...mergeTransientFiles,
  ...mergeContractFiles,
];

/// Every file accounted for by the registry, in any layer. The completeness
/// check uses this; the redaction and layering gates use [mergeModuleFiles].
const mergeRegisteredFiles = <String>[
  ...mergeModuleFiles,
  ...mergeDataImplementationFiles,
];

/// Files judged by the strict field/getter/static/serializer rules.
const mergeStrictlyRedactedFiles = <String>[
  ...mergeSafeModelFiles,
  ...mergeContractFiles,
];

/// The only files allowed to import a transient plaintext library.
///
/// The gate derives the *targets* from [mergeTransientFiles] rather than
/// matching a literal filename, so a second transient file cannot arrive
/// without import restrictions (N5).
///
/// Phase 6 adds the field widget here — deliberately one reviewed line, and per
/// F6 it must arrive with the retention test named in `tasks.md` T603, because
/// an import allowlist alone does not stop an allowlisted file from copying
/// `.value` into a durable `String`.
const mergeFieldDisplayImporters = <String>[
  'lib/features/password_manager/domain/models/merge_field_display.dart',
  'lib/features/password_manager/domain/repositories/sync_merge_repository.dart',
  'lib/features/password_manager/domain/usecases/load_sync_merge_field_display_usecase.dart',
];

/// What makes a file part of the merge module.
final mergeIdentifierPattern = RegExp(
  r'\b(SyncMerge[A-Za-z0-9_]*|Merge[A-Z][A-Za-z0-9_]*|RedactedMergeDecision)\b',
);

/// Merge-shaped identifiers that are NOT spec-008.
///
/// Scoped to `(identifier, owning file)` pairs, never to a bare name (N6). A
/// bare-name exemption left four identifiers globally free: a brand-new file
/// declaring a class called exactly `MergePreview` was invisible to the
/// completeness check and could carry anything. Under the pair rule the
/// exemption only holds in the files that legitimately use the identifier
/// today, so a new file naming one is still caught.
const nonSpec008MergeIdentifiers = <String, Set<String>>{
  // Flutter framework widget.
  'MergeSemantics': {
    'lib/features/password_manager/presentation/screens/vault/vault_entries_details.part.dart',
  },
  // spec-005 import duplicate preview, predates 008.
  'MergePreview': {
    'lib/features/password_manager/domain/models/merge_preview.dart',
    'lib/features/password_manager/data/services/vault_duplicate_service.dart',
    'lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart',
  },
  'MergePreviewSurface': {
    'lib/features/password_manager/presentation/navigation/vault_shell_router.dart',
    'lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart',
  },
  // spec-005 duplicate resolution event.
  'MergeDuplicateEntries': {
    'lib/features/password_manager/presentation/bloc/vault/vault_event.dart',
    'lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart',
    'lib/features/password_manager/presentation/screens/vault/vault_duplicates.part.dart',
  },
};

/// Phase 3 types that have not been implemented yet. Kept separate from the
/// identifier pattern because these names do not match it.
///
/// `KdbxMergeAdapter` was removed on 2026-08-22: Gate 2 exited with PR #89 and
/// T301/T304/T305/T306 landed the adapter, so the name is now expected to exist
/// — in exactly one registered file, which
/// `sync_merge_domain_architecture_test.dart` still checks. The list is not
/// emptied: `SyncMergeRepositoryImpl` (T302) has not started, and a DI binding
/// or a coordinator naming it early is still the failure this guard catches.
const phase3TypeNames = <String>['SyncMergeRepositoryImpl'];

/// Every registered file must live here. Registering a `presentation/` or
/// `data/` file into a merge bucket would otherwise pass the layering gate,
/// which judges a registered file's imports but never its location (N7).
const mergeModuleDirectory = 'lib/features/password_manager/domain/';
