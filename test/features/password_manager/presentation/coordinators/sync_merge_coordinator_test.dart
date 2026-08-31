// spec-008 T502 / T506 / T508 — the presentation-side merge boundary.
//
// Three gates in one file:
//   * T502: the coordinator's import boundary (real analyzer, like the C-7
//     gate) and its sequencing against a recording fake port;
//   * T506: lock/switch invalidate the merge BEFORE credentials are cleared,
//     and a late port callback after invalidation is dropped;
//   * T508: nothing the coordinator, the events or the state expose renders a
//     known secret, even when the port behind them holds every one of them.
import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/database_path_mutex.dart';
import 'package:password_manager/features/password_manager/data/services/database_rename_transaction.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/models/merge_field_display.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_merge_models.dart';
import 'package:password_manager/features/password_manager/domain/repositories/sync_merge_repository.dart';
import 'package:password_manager/features/password_manager/domain/services/sync_merge_policy.dart';
import 'package:password_manager/features/password_manager/domain/usecases/sync_merge_usecases.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_state.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/sync_merge_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/vault_session_coordinator.dart';
import 'package:path/path.dart' as p;

import 'fake_database_ports.dart';

// Secrets the fake port holds. None may ever appear on the presentation side.
const _password = 'known-master-password-4c1e';
const _keyFilePath = '/secret/dir/vault.keyx';
const _keyFileBytes = 'key-file-material-9b7a';
const _protectedValue = 'protected-custom-value-7d2f';
const _attachmentBytes = 'attachment-bytes-3e8c';
const _fieldLabel = 'Custom_SecretField';
const _sentinels = [
  _password,
  _keyFilePath,
  _keyFileBytes,
  _protectedValue,
  _attachmentBytes,
  _fieldLabel,
];

final _databaseId = MergeDatabaseId('db-merge-coordinator');

void main() {
  group('T502 import boundary', () {
    test('sync_merge_coordinator.dart imports only the merge domain '
        'contract — no data/, dart:io, Flutter or transient display', () {
      final imports = _importsOf(
        'lib/features/password_manager/presentation/coordinators/'
        'sync_merge_coordinator.dart',
      );
      expect(imports, isNotEmpty);
      for (final uri in imports) {
        expect(uri, isNot(contains('/data/')), reason: uri);
        expect(uri, isNot(contains('merge_field_display')), reason: uri);
        expect(uri, isNot(startsWith('dart:io')), reason: uri);
        expect(uri, isNot(startsWith('package:flutter')), reason: uri);
        expect(uri, isNot(startsWith('package:kdbx')), reason: uri);
        expect(uri, isNot(startsWith('package:crypto')), reason: uri);
        expect(
          uri.startsWith('dart:') ||
              uri.contains('/domain/models/sync_merge_models.dart') ||
              uri.contains('/domain/repositories/sync_merge_repository.dart') ||
              uri.contains('/domain/services/sync_merge_policy.dart') ||
              uri.contains('/domain/usecases/sync_merge_usecases.dart'),
          isTrue,
          reason: 'unexpected import $uri',
        );
      }
    });

    test('the BLoC, its events and its state never name the transient field '
        'display (T503 — it stays in the widget)', () {
      for (final file in const [
        'lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart',
        'lib/features/password_manager/presentation/bloc/vault/vault_event.dart',
        'lib/features/password_manager/presentation/bloc/vault/vault_state.dart',
        'lib/features/password_manager/presentation/coordinators/'
            'sync_merge_coordinator.dart',
        'lib/features/password_manager/presentation/coordinators/'
            'vault_session_coordinator.dart',
      ]) {
        final source = File(p.join(_root(), file)).readAsStringSync();
        expect(
          source,
          isNot(contains('MergeFieldDisplay')),
          reason: '$file names MergeFieldDisplay',
        );
        expect(
          source,
          isNot(contains('load_sync_merge_field_display_usecase')),
          reason: '$file imports the field display use case',
        );
      }
    });
  });

  group('T502 sequencing', () {
    late _RecordingPort port;
    late SyncMergeCoordinator coordinator;

    setUp(() {
      port = _RecordingPort();
      coordinator = _build(port);
    });

    test('start → update → commit(applied) clears the session', () async {
      final summary = await coordinator.startReview(_databaseId);
      expect(coordinator.currentReview, summary);

      final decision = summary.decisions.first;
      final updated = await coordinator.updateDecision(
        decisionId: decision.decisionId,
        choice: MergeChoice.remote,
      );
      expect(coordinator.currentReview, updated);
      expect(updated.decisions.first.choice, MergeChoice.remote);

      port.commitOutcome = const MergeApplied(
        entryCount: 3,
        backupCreated: true,
        uploadState: MergeUploadState.uploaded,
      );
      final outcome = await coordinator.commit();
      expect(outcome, isA<MergeApplied>());
      expect(coordinator.currentReview, isNull);
      expect(port.calls, ['startReview', 'updateDecision', 'commit']);
    });

    test(
      'a needs-review outcome keeps the session with the new summary',
      () async {
        await coordinator.startReview(_databaseId);
        final reReview = port.summary(
          phase: MergeReviewPhase.needsReview,
          conflicts: 2,
        );
        port.commitOutcome = MergeNeedsReview(
          summary: reReview,
          newConflictCount: 1,
          reviewReentryCount: 1,
        );

        final outcome = await coordinator.commit();

        expect(outcome, isA<MergeNeedsReview>());
        expect(coordinator.currentReview, reReview);
        // The same session is still commit-able.
        port.commitOutcome = const MergeRejected(
          MergeFailureCode.unresolvedConflict,
          localCommitCompleted: true,
        );
        await coordinator.commit();
        expect(coordinator.currentReview, isNull);
      },
    );

    test(
      'applyShortcut issues exactly the policy commands, in order',
      () async {
        final summary = await coordinator.startReview(_databaseId);
        final expected = SyncMergePolicy.commandsFor(
          summary,
          MergeShortcut.preferRemote,
        );

        await coordinator.applyShortcut(MergeShortcut.preferRemote);

        expect(
          port.updates.map((u) => u.$1),
          expected.map((c) => c.decisionId),
        );
        expect(port.updates.map((u) => u.$2), expected.map((c) => c.choice));
      },
    );

    test('commit, update and shortcut without a session are refused with '
        'sessionInvalidated and reach the port not at all', () async {
      for (final action in [
        () => coordinator.commit(),
        () => coordinator.updateDecision(
          decisionId: _decisionId(1),
          choice: MergeChoice.local,
        ),
        () => coordinator.applyShortcut(MergeShortcut.preferLocal),
      ]) {
        await expectLater(
          action,
          throwsA(
            isA<SyncMergeFailure>().having(
              (f) => f.code,
              'code',
              MergeFailureCode.sessionInvalidated,
            ),
          ),
        );
      }
      expect(port.calls, isEmpty);
    });

    test('cancel disposes the session at the port and forgets it', () async {
      await coordinator.startReview(_databaseId);
      await coordinator.cancel();
      expect(coordinator.currentReview, isNull);
      expect(port.calls, ['startReview', 'cancel']);
      // Idempotent: a second cancel does not reach the port.
      await coordinator.cancel();
      expect(port.calls, ['startReview', 'cancel']);
    });

    test(
      'a second startReview cancels the first session before opening',
      () async {
        await coordinator.startReview(_databaseId);
        await coordinator.startReview(_databaseId);
        expect(port.calls, ['startReview', 'cancel', 'startReview']);
      },
    );

    test('recoverPending forwards and holds no session', () async {
      port.recoveryOutcome = const MergeRecoveryOutcome(
        MergeRecoveryDisposition.retriedAndFinalized,
      );
      final outcome = await coordinator.recoverPending(_databaseId);
      expect(outcome.disposition, MergeRecoveryDisposition.retriedAndFinalized);
      expect(coordinator.currentReview, isNull);
    });
  });

  group('T506 lock and late callbacks', () {
    test('invalidate drops a startReview that completes afterwards', () async {
      final port = _RecordingPort();
      final coordinator = _build(port);
      final gate = Completer<void>();
      port.startGate = gate.future;

      final pending = coordinator.startReview(_databaseId);
      await Future<void>.delayed(Duration.zero);
      await coordinator.invalidate(_databaseId);
      gate.complete();

      await expectLater(
        pending,
        throwsA(
          isA<SyncMergeFailure>().having(
            (f) => f.code,
            'code',
            MergeFailureCode.sessionInvalidated,
          ),
        ),
      );
      expect(coordinator.currentReview, isNull);
      expect(port.calls, ['startReview', 'invalidate']);
    });

    test('invalidate drops a commit that completes afterwards', () async {
      final port = _RecordingPort();
      final coordinator = _build(port);
      await coordinator.startReview(_databaseId);
      final gate = Completer<void>();
      port.commitGate = gate.future;
      port.commitOutcome = const MergeApplied(
        entryCount: 1,
        backupCreated: true,
        uploadState: MergeUploadState.uploaded,
      );

      final pending = coordinator.commit();
      await Future<void>.delayed(Duration.zero);
      await coordinator.invalidate(_databaseId);
      gate.complete();

      await expectLater(pending, throwsA(isA<SyncMergeFailure>()));
      expect(coordinator.currentReview, isNull);
    });

    for (final (name, run)
        in <(String, Future<void> Function(VaultSessionCoordinator, String))>[
          ('lockVault', (c, path) => c.lockVault(currentDatabasePath: path)),
          (
            'changeDatabase',
            (c, path) => c.changeDatabase(currentDatabasePath: path),
          ),
        ]) {
      test(
        '$name invalidates the merge BEFORE clearing the session secret',
        () async {
          final port = _RecordingPort();
          final holder = SessionSecretHolder()..set(_password);
          port.onInvalidate = () {
            // Observed from inside the port: the credential is still there.
            expect(holder.hasSecret, isTrue);
          };
          final registry = FakeDatabaseRegistryRepository()
            ..records = [
              DatabaseRecord(
                databaseId: _databaseId.value,
                canonicalPath: '/vault/db.kdbx',
                displayName: 'db',
                sourceType: DatabaseSourceType.local,
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
              ),
            ];
          final coordinator = VaultSessionCoordinator(
            databaseFileRepository: FakeDatabaseFileRepository(),
            databaseRenameTransaction: DatabaseRenameTransaction(
              mutex: DatabasePathMutex(),
              syncRepository: FakeDatabaseSyncRepository(),
            ),
            localDataSource: _NoopLocalDataSource(),
            databaseRegistryRepository: registry,
            databaseSecurityRepository: FakeDatabaseSecurityRepository(),
            secureDataSource: _NoopSecureDataSource(),
            databaseSyncRepository: FakeDatabaseSyncRepository(),
            vaultKdbxService: _NoopVaultKdbxService(),
            sessionSecretHolder: holder,
            syncMergeCoordinator: _build(port),
          );

          await run(coordinator, '/vault/db.kdbx');

          expect(port.calls, ['invalidate']);
          expect(port.invalidatedIds, [_databaseId]);
          expect(holder.hasSecret, isFalse);
        },
      );
    }

    test(
      'a failing invalidate never stops the lock from clearing the secret',
      () async {
        final port = _RecordingPort()..invalidateError = StateError('boom');
        final holder = SessionSecretHolder()..set(_password);
        final registry = FakeDatabaseRegistryRepository()
          ..records = [
            DatabaseRecord(
              databaseId: _databaseId.value,
              canonicalPath: '/vault/db.kdbx',
              displayName: 'db',
              sourceType: DatabaseSourceType.local,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ];
        final coordinator = VaultSessionCoordinator(
          databaseFileRepository: FakeDatabaseFileRepository(),
          databaseRenameTransaction: DatabaseRenameTransaction(
            mutex: DatabasePathMutex(),
            syncRepository: FakeDatabaseSyncRepository(),
          ),
          localDataSource: _NoopLocalDataSource(),
          databaseRegistryRepository: registry,
          databaseSecurityRepository: FakeDatabaseSecurityRepository(),
          secureDataSource: _NoopSecureDataSource(),
          databaseSyncRepository: FakeDatabaseSyncRepository(),
          vaultKdbxService: _NoopVaultKdbxService(),
          sessionSecretHolder: holder,
          syncMergeCoordinator: _build(port),
        );

        await coordinator.lockVault(currentDatabasePath: '/vault/db.kdbx');

        expect(holder.hasSecret, isFalse);
      },
    );
  });

  group('T508 secrets', () {
    test('coordinator, events and state render no known secret while the '
        'port holds every one of them', () async {
      final port = _RecordingPort();
      final coordinator = _build(port);
      final summary = await coordinator.startReview(_databaseId);
      port.commitOutcome = MergeNeedsReview(
        summary: port.summary(
          phase: MergeReviewPhase.needsReview,
          conflicts: 1,
        ),
        newConflictCount: 1,
        reviewReentryCount: 1,
      );
      final outcome = await coordinator.commit();
      final state = VaultState(
        databasePath: '/vault/db.kdbx',
        mergeReview: coordinator.currentReview,
        mergeCommitOutcome: outcome,
        mergeFailureCode: MergeFailureCode.credentialsRevoked,
      );
      final events = <Object>[
        const StartSyncMergeReview(),
        UpdateSyncMergeDecision(
          decisionId: summary.decisions.first.decisionId,
          choice: MergeChoice.local,
        ),
        const ApplySyncMergeShortcut(MergeShortcut.preferLocal),
        const CommitSyncMerge(),
        const CancelSyncMerge(),
      ];

      final rendered = [
        _renderDeeply(coordinator),
        _renderDeeply(coordinator.currentReview),
        _renderDeeply(summary),
        _renderDeeply(outcome),
        _renderDeeply(state),
        state.props.map(_renderDeeply).join(),
        for (final event in events) _renderDeeply(event),
        for (final event in events)
          if (event is VaultEvent) event.props.map(_renderDeeply).join(),
      ].join('\n');

      for (final secret in _sentinels) {
        expect(rendered, isNot(contains(secret)), reason: secret);
      }
      // And the port really did hold them, so the test is not vacuous.
      expect(port.secretsHeld, containsAll(_sentinels));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SyncMergeCoordinator _build(SyncMergeRepository port) => SyncMergeCoordinator(
  startReview: StartSyncMergeReviewUseCase(port),
  updateDecision: UpdateSyncMergeDecisionUseCase(port),
  commit: CommitSyncMergeUseCase(port),
  cancel: CancelSyncMergeUseCase(port),
  invalidate: InvalidateSyncMergeUseCase(port),
  recoverPending: RecoverPendingSyncMergeUploadUseCase(port),
);

MergeSessionId _sessionId(int n) =>
    MergeSessionId('ms-${n.toRadixString(16).padLeft(32, '0')}');
MergeDecisionId _decisionId(int n) =>
    MergeDecisionId('md-${n.toRadixString(16).padLeft(32, '0')}');

/// A port that holds every secret privately and answers with redacted
/// summaries only, recording each call it receives.
class _RecordingPort implements SyncMergeRepository {
  final List<String> calls = [];
  final List<(MergeDecisionId, MergeChoice)> updates = [];
  final List<MergeDatabaseId> invalidatedIds = [];
  final Set<String> secretsHeld = {..._sentinels};

  MergeCommitOutcome commitOutcome = const MergeRejected(
    MergeFailureCode.unresolvedConflict,
    localCommitCompleted: false,
  );
  MergeRecoveryOutcome recoveryOutcome = const MergeRecoveryOutcome(
    MergeRecoveryDisposition.none,
  );
  Future<void>? startGate;
  Future<void>? commitGate;
  Object? invalidateError;
  void Function()? onInvalidate;

  MergeReviewSummary? _current;
  int _sessions = 0;

  MergeReviewSummary summary({
    required MergeReviewPhase phase,
    int conflicts = 2,
    List<MergeChoice>? choices,
  }) => MergeReviewSummary(
    sessionId: _sessionId(++_sessions),
    databaseId: _databaseId,
    phase: phase,
    decisions: [
      for (var i = 0; i < conflicts; i++)
        RedactedMergeDecision(
          decisionId: _decisionId(i + 1),
          ordinal: i,
          kind: MergeDecisionKind.fieldConflict,
          category: MergeFieldCategory.password,
          presence: MergePresence.presentBoth,
          choice: choices?[i] ?? MergeChoice.local,
          isDefault: true,
          timestampRelation: TimestampRelation.localNewer,
        ),
    ],
    localOnlyRecordCount: 1,
    remoteOnlyRecordCount: 1,
    oneSidedFieldCount: 1,
  );

  @override
  Future<MergeReviewSummary> startReview(MergeDatabaseId databaseId) async {
    calls.add('startReview');
    await startGate;
    return _current = summary(phase: MergeReviewPhase.reviewing);
  }

  @override
  Future<MergeReviewSummary> updateDecision({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
    required MergeChoice choice,
  }) async {
    calls.add('updateDecision');
    updates.add((decisionId, choice));
    final current = _current!;
    return _current = MergeReviewSummary(
      sessionId: current.sessionId,
      databaseId: current.databaseId,
      phase: current.phase,
      decisions: [
        for (final d in current.decisions)
          d.decisionId == decisionId ? d.withChoice(choice) : d,
      ],
      localOnlyRecordCount: current.localOnlyRecordCount,
      remoteOnlyRecordCount: current.remoteOnlyRecordCount,
      oneSidedFieldCount: current.oneSidedFieldCount,
    );
  }

  @override
  Future<MergeCommitOutcome> commit(MergeSessionId sessionId) async {
    calls.add('commit');
    await commitGate;
    return commitOutcome;
  }

  @override
  Future<void> cancel(MergeSessionId sessionId) async {
    calls.add('cancel');
    _current = null;
  }

  @override
  Future<void> invalidate(MergeDatabaseId databaseId) async {
    calls.add('invalidate');
    invalidatedIds.add(databaseId);
    onInvalidate?.call();
    final error = invalidateError;
    if (error != null) throw error;
    _current = null;
  }

  @override
  Future<MergeRecoveryOutcome> recoverPending(
    MergeDatabaseId databaseId,
  ) async {
    calls.add('recoverPending');
    return recoveryOutcome;
  }

  @override
  Future<MergeFieldDisplay> loadFieldDisplay({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
  }) async => MergeFieldDisplay(
    label: _fieldLabel,
    local: MergeDisplaySide.present(_protectedValue),
    remote: MergeDisplaySide.present(_attachmentBytes),
    protected: true,
  );
}

class _NoopLocalDataSource implements LocalDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _NoopSecureDataSource implements SecureDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _NoopVaultKdbxService implements VaultKdbxService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

String _root() {
  var dir = Directory.current;
  while (!File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('no pubspec.yaml found');
    dir = parent;
  }
  return dir.path;
}

List<String> _importsOf(String relative) {
  final path = p.join(_root(), relative);
  final unit = parseString(
    content: File(path).readAsStringSync(),
    path: path,
  ).unit;
  return [
    for (final directive in unit.directives)
      if (directive is ImportDirective) directive.uri.stringValue!,
  ];
}

/// `toString` plus every `props` element, recursively.
String _renderDeeply(Object? value) {
  final buffer = StringBuffer(value.toString());
  if (value is Iterable) {
    for (final element in value) {
      buffer.write(_renderDeeply(element));
    }
  }
  final props = _propsOf(value);
  for (final element in props) {
    buffer.write(_renderDeeply(element));
  }
  return buffer.toString();
}

List<Object?> _propsOf(Object? value) {
  try {
    return (value as dynamic).props as List<Object?>;
  } on Object {
    return const [];
  }
}
