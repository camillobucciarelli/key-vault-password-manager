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

/// Every registered merge file. Both gates derive their scope from this.
const mergeModuleFiles = <String>[
  ...mergeSafeModelFiles,
  ...mergeTransientFiles,
  ...mergeContractFiles,
];

/// Files judged by the strict field/getter/static/serializer rules.
const mergeStrictlyRedactedFiles = <String>[
  ...mergeSafeModelFiles,
  ...mergeContractFiles,
];

/// The only files allowed to import the transient plaintext response.
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

/// Merge-shaped identifiers that are NOT spec-008. Each is exempt by name, not
/// by file, so a new file using one does not false-positive and a new file
/// using a real merge type is still caught.
const nonSpec008MergeIdentifiers = <String>{
  'MergeSemantics', // Flutter framework widget
  'MergePreview', // spec-005 import duplicate preview, predates 008
  'MergePreviewSurface', // spec-005
  'MergeDuplicateEntries', // spec-005 duplicate resolution event
};

/// Phase 3+ types that must not exist yet (Gate 2 exit condition). Kept
/// separate from the identifier pattern because `KdbxMergeAdapter` does not
/// match it.
const phase3TypeNames = <String>['SyncMergeRepositoryImpl', 'KdbxMergeAdapter'];
