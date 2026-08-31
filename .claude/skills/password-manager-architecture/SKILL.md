---
name: password-manager-architecture
description: Applies project architecture when sessions change Password Manager Flutter/Dart BLoCs, coordinators, use cases, repositories, data sources, services, KDBX safety, or cloud sync providers; consults spec 010 for cloud-sync work.
---

# Password Manager architecture

Apply these decisions before planning or editing
`lib/features/password_manager`.

## Structure and flow

- Keep one `features/password_manager` feature with `data`, `domain` and
  `presentation`. Do not split cloud sync, autofill or vault operations into new
  top-level features without an approved spec.
- Use cases represent atomic business operations with policy, validation or
  transaction value.
- Coordinators sequence multi-step workflows and multiple use cases.
- BLoCs stay thin: translate events, call coordinators/use cases, emit redacted
  state. No OAuth, file transaction or multi-step sync logic in BLoCs.
- Do not create one-line pass-through use cases solely for symmetry.

## Data boundaries

- Data sources read/write one external persistence or platform boundary: secure
  storage, local metadata, registry, method channel, HTTP transport.
- Technical services implement data-layer mechanics or transactions by composing
  data sources: OAuth refresh, KDBX I/O, imports, safe writes.
- Domain repository/port defines application-required behavior. Data implements
  it. Presentation never imports data implementation or provider SDK types.
- Keep credentials, raw provider responses, KDBX objects and plaintext in data
  boundaries. Surface safe typed outcomes only.

## Cloud storage

When touching cloud sync, read
`specs/010-multi-cloud-storage/{spec,plan,tasks}.md`.

Spec 010 defines target architecture; it is planned, not current implementation:

- `DatabaseSyncRepository` must stay application-facing.
- `DatabaseSyncOrchestrator` will depend on one provider-neutral
  `CloudStorageProvider` port.
- Initial sole implementation will be Google Drive. One port may include
  auth/account plus byte/object operations; split only when real implementations
  require it.
- Mapping identity is provider-neutral and per database:
  `providerId`, `remoteFileId`, `remoteFileName`.
- Remote identity is always the tuple `(providerId, remoteFileId)`, including
  duplicate-link checks; opaque IDs may collide across providers.
- Stable Google provider ID is `google_drive`.
- Google adapter will own OAuth/token/API details and raw-to-safe error mapping.
- Provider errors use spec 010's exact exhaustive `CloudStorageErrorCode`, safe
  code/message table and deterministic `unknown` fallback. Never interpolate raw
  SDK/HTTP detail and never add retries as part of error mapping.
- A persisted mapping with no wired adapter fails before any I/O as
  `unsupportedProvider` with fixed code/message; never expose raw provider ID.
- Preserve UI behavior and static/unrelated copy exactly. Only unsafe dynamic
  provider error detail may change, and only to spec-fixed safe messages.
- Domain/presentation expose no Google SDK type, token, raw provider error or
  Drive-shaped remote model.
- No registry, factory, capability framework, provider picker, second adapter or
  simultaneous remotes until required by approved scope.

## Sync and vault safety

- `VaultKdbxService` owns semantic KDBX parsing/edits. Approved raw-byte
  replacement/import/sync writers stay in data services/orchestrator under shared
  mutex, backup and safe-writer invariants; not every vault write routes through
  `VaultKdbxService`.
- Preserve exactly one externally openable remote `.kdbx` at every instant,
  including interrupted/mid-write states; no fragments, wrappers, sidecar lock
  dependency or proprietary remote container.
- Never bypass shared singleton `DatabasePathMutex` or safe writer/backup path.
- Never change checksum, conflict, convergence, mapping or timeout semantics as a
  side effect of an architecture refactor.
- Legacy mapping migration never touches vault bytes and fails closed.
- Sync/data-loss/security changes require characterization plus targeted failure,
  concurrency and migration tests. Run `flutter analyze` and relevant/full
  `flutter test` before completion.
- Coordinate shared orchestrator/mapping/writer changes with active spec 008.
- Future adapters/capabilities remain gated by spec 010's live counter-probe,
  sanitized artifact and interrupted-write single-file evidence. These deferred
  constraints are normative even though immediate Google refactor does not build
  provider registry/evidence infrastructure.

## Decision checklist

1. Is operation atomic business policy? Use case.
2. Does flow call multiple operations or need rollback/sequencing? Coordinator.
3. Is code only event/state translation? BLoC.
4. Is dependency one persistence/platform mechanism? Data source.
5. Is it data-layer mechanics/transaction composition? Technical service.
6. Must application depend on behavior while data supplies implementation?
   Repository/port.
7. Does change touch cloud sync? Check spec 010, mapping migration and provider
   error boundary.
8. Does change write/replace `.kdbx`? Reuse shared mutex/safe writer and add
   data-loss tests.

## Forbidden patterns

- New top-level feature/refolder for provider code.
- Provider SDK/data types in domain, coordinator, BLoC or UI.
- Raw token, provider body/exception or secret in logs, state, `Equatable.props`,
  `toString` or persistence.
- Multi-step workflow in BLoC/widget.
- Private mutex or direct KDBX write bypass.
- One-implementation registry/factory/router, speculative capability flags or
  unused provider interfaces.
- Provider-name branching in sync algorithm.
- Mapping fallback that guesses provider/object or silently drops malformed data.
