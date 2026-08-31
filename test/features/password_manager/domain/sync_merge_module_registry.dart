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
  'lib/features/password_manager/data/services/kdbx_semantic_manifest.dart',
  'lib/features/password_manager/data/services/merge_decision_ledger.dart',
  'lib/features/password_manager/data/repositories/sync_merge_repository_impl.dart',
];

/// Bucket 5 — the composition root.
///
/// **Why this bucket has to exist, and why it is not a loophole.** The T303
/// boundary check below asks whether a `domain/` or `presentation/` file can
/// *reach* the data implementation through any chain of imports or exports.
/// Dependency injection makes that question degenerate: the composition root
/// must name `SyncMergeRepositoryImpl` to construct it, presentation screens
/// import `injection_container.dart` to resolve services, and the chain
/// `presentation -> injection_container -> di -> impl -> adapter` therefore
/// exists in every app that has DI at all. Without a barrier the check would
/// report six presentation files as offenders for doing the one thing DI is
/// for.
///
/// The barrier is sound for a specific reason rather than for convenience:
/// **Dart imports are not transitive for name resolution.** A file that imports
/// the DI module cannot name `SyncMergeRepositoryImpl`, let alone
/// `KdbxFieldPresent.semanticValue` — it would have to add its own import,
/// which the check still catches. The one construct that *would* republish
/// those names through the barrier is `export`, so
/// `sync_merge_domain_architecture_test.dart` asserts these files contain no
/// export directive at all. That assertion is what keeps the barrier from
/// becoming the laundering path it is exempting.
const mergeCompositionRootFiles = <String>[
  'lib/features/password_manager/di/password_manager_data_di.dart',
  'lib/features/password_manager/di/password_manager_domain_di.dart',
];

/// Where a composition-root file may live.
const mergeCompositionRootDirectory = 'lib/features/password_manager/di/';

/// The **only** public top-level names a barrier file may declare.
///
/// Round 5 finding (HIGH-1): checking a barrier for `export` checks one member
/// of a family. `typedef QaLeaked = KdbxFieldPresent;`, a public function
/// returning `KdbxMergeAdapter`, and a public top-level variable of an adapter
/// type all re-publish the same names through the same hole, with `analyze`
/// clean. So the exemption is bounded by construction instead: a barrier
/// declares these two functions, private declarations, and nothing else at all
/// — including constructs that do not exist yet.
const mergeCompositionRootPublicNames = <String>[
  'registerPasswordManagerDataDependencies',
  'registerPasswordManagerDomainDependencies',
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
/// spec-008 Gate 5 (T501-T507): the presentation files that name merge
/// types. They may import the safe models, the port's failure type, the
/// policy and the command use cases — never the data implementation. Their
/// own redaction/boundary gates live in
/// `presentation/coordinators/sync_merge_coordinator_test.dart`.
const mergePresentationFiles = <String>[
  'lib/features/password_manager/presentation/coordinators/sync_merge_coordinator.dart',
  'lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart',
  'lib/features/password_manager/presentation/widgets/sync_merge_field_display_view.dart',
  'lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart',
  'lib/features/password_manager/presentation/bloc/vault/vault_event.dart',
  'lib/features/password_manager/presentation/bloc/vault/vault_state.dart',
  'lib/features/password_manager/di/password_manager_presentation_di.dart',
  // Gate 6 (T601-T605): the review UI and its two entry points.
  'lib/features/password_manager/presentation/widgets/sync/sync_merge_screen.dart',
  'lib/features/password_manager/presentation/screens/vault_screen.dart',
  'lib/features/password_manager/presentation/screens/vault/vault_sync.part.dart',
  'lib/features/password_manager/presentation/navigation/vault_shell_router.dart',
];

const mergeRegisteredFiles = <String>[
  ...mergeModuleFiles,
  ...mergeDataImplementationFiles,
  ...mergeCompositionRootFiles,
  ...mergePresentationFiles,
];

/// Files whose declared top-level names make a file elsewhere a merge-module
/// participant.
///
/// The composition root is deliberately **excluded**. Its declarations are
/// generic DI entry points (`registerPasswordManagerDataDependencies`), not
/// merge types, and feeding them into the completeness pattern would classify
/// `injection_container.dart` — and, one hop further, every screen that
/// resolves a service — as an unregistered merge file. The rule is about who
/// can name a merge TYPE; a DI function is not one.
const mergeSymbolSourceFiles = <String>[
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
  // spec-008 T503: the one field widget that may hold the transient display.
  'lib/features/password_manager/presentation/widgets/sync_merge_field_display_view.dart',
  'lib/features/password_manager/domain/repositories/sync_merge_repository.dart',
  'lib/features/password_manager/domain/usecases/load_sync_merge_field_display_usecase.dart',
  // T302: the port declares `Future<MergeFieldDisplay> loadFieldDisplay(...)`,
  // so its implementation cannot avoid naming the type — and it is the one
  // place the plaintext legitimately originates. This is not the F6 hole: F6 is
  // about a CONSUMER copying `.value` into a durable `String`, and the producer
  // already holds the decrypted values by construction. The retention test
  // T603 owes still applies to every consumer added later.
  'lib/features/password_manager/data/repositories/sync_merge_repository_impl.dart',
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

/// Types belonging to a phase that has not started yet. Kept separate from the
/// identifier pattern because such a name need not match it.
///
/// `KdbxMergeAdapter` was removed on 2026-08-22 when T301's read half landed.
/// `SyncMergeRepositoryImpl` was removed in Phase 3 slice 2 (T302/T310) for the
/// same reason: the type now exists, in exactly one registered file, and
/// `sync_merge_domain_architecture_test.dart` checks where that file lives and
/// who can reach it.
///
/// The list is deliberately kept rather than deleted with its test. It is empty
/// because nothing is currently owed — every remaining unbuilt type
/// (`SyncMergeCoordinator`, T501) already matches [mergeIdentifierPattern], so
/// the completeness check catches it without help. A future type that does not
/// match the pattern goes here.
const phase3TypeNames = <String>[];

/// Every registered file must live here. Registering a `presentation/` or
/// `data/` file into a merge bucket would otherwise pass the layering gate,
/// which judges a registered file's imports but never its location (N7).
const mergeModuleDirectory = 'lib/features/password_manager/domain/';
