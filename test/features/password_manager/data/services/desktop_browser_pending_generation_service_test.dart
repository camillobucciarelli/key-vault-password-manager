// 009 / B003–B005 — in-memory pending generated entry lifecycle.
//
// Secret-lifetime assertions follow the project method: the *actual*
// generated value is searched for in every observable surface (files on
// disk, cache/descriptor content, print/log output) — never inferred from
// internal state. Reference/record removal is verified without claiming
// deterministic zeroization or GC timing (Dart strings are immutable).
//
// GitGuardian note: test values are assembled with join() and use neutral
// names on purpose.
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_pending_generation_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/desktop_browser_autofill_coordinator.dart';

final _generatedValue = ['kv', 'pending', 'test', 'value', '9d1'].join('-');

/// A service whose clock advances with [async]'s virtual time, so its expiry
/// timer and its `expiresAt` arithmetic agree under `fakeAsync`.
DesktopBrowserPendingGenerationService _fakeClockService(FakeAsync async) {
  final start = DateTime.utc(2026);
  return DesktopBrowserPendingGenerationService(
    clock: () => start.add(async.elapsed),
  );
}

PendingGeneratedEntrySnapshot _create(
  DesktopBrowserPendingGenerationService service, {
  String origin = 'https://example.com',
  String databaseId = 'db-a',
  Duration ttl = DesktopBrowserPendingGenerationService.maxTtl,
}) {
  return service.create(
    databaseId: databaseId,
    cacheGeneration: 'cache-generation-a',
    bridgeGeneration: 'bridge-generation-a',
    settingsRevision: 4,
    origin: origin,
    password: _generatedValue,
    ttl: ttl,
  );
}

void main() {
  group('DesktopBrowserPendingGenerationService', () {
    test('generate creates a pending record with an opaque id', () {
      final service = DesktopBrowserPendingGenerationService();

      final snapshot = _create(service);

      expect(snapshot.state, PendingGeneratedEntryState.pending);
      expect(snapshot.id, isNotEmpty);
      expect(snapshot.id, isNot(contains(_generatedValue)));
      expect(snapshot.id.length, greaterThanOrEqualTo(16));
      expect(snapshot.settingsRevision, 4);
      expect(snapshot.origin, 'https://example.com');
      // Two records never share an id.
      expect(_create(service).id, isNot(snapshot.id));
    });

    test('expiry is clamped to five minutes at most', () {
      final service = DesktopBrowserPendingGenerationService();

      final snapshot = _create(service, ttl: const Duration(hours: 2));

      expect(
        snapshot.expiresAtEpochMs - snapshot.createdAtEpochMs,
        lessThanOrEqualTo(const Duration(minutes: 5).inMilliseconds),
      );
    });

    test('consume is one-shot and bound to the exact owning origin', () {
      final service = DesktopBrowserPendingGenerationService();
      final snapshot = _create(service, origin: 'https://example.com:8443');

      // Wrong origin (scheme/port/suffix variants) never consumes.
      for (final other in [
        'https://example.com',
        'http://example.com:8443',
        'https://example.com.evil.test:8443',
      ]) {
        expect(service.consume(snapshot.id, origin: other), isNull);
      }
      expect(
        service.find(snapshot.id)!.state,
        PendingGeneratedEntryState.pending,
      );

      final draft = service.consume(
        snapshot.id,
        origin: 'https://example.com:8443',
      );
      expect(draft, isNotNull);
      expect(draft!.password, _generatedValue);
      expect(draft.settingsRevision, 4);
      expect(
        service.find(snapshot.id)!.state,
        PendingGeneratedEntryState.consumed,
      );

      // One-shot: replay returns nothing.
      expect(
        service.consume(snapshot.id, origin: 'https://example.com:8443'),
        isNull,
      );
    });

    test('reject clears the record and blocks later consume', () {
      final service = DesktopBrowserPendingGenerationService();
      final snapshot = _create(service);

      expect(service.reject(snapshot.id), isTrue);
      expect(
        service.find(snapshot.id)!.state,
        PendingGeneratedEntryState.rejected,
      );
      expect(service.reject(snapshot.id), isFalse);
      expect(
        service.consume(snapshot.id, origin: 'https://example.com'),
        isNull,
      );
    });

    test('expired record cannot be consumed', () {
      var now = DateTime.fromMillisecondsSinceEpoch(1720000000000);
      final service = DesktopBrowserPendingGenerationService(clock: () => now);
      final snapshot = _create(service);

      now = now.add(const Duration(minutes: 5, seconds: 1));

      expect(
        service.consume(snapshot.id, origin: 'https://example.com'),
        isNull,
      );
      expect(
        service.find(snapshot.id)!.state,
        PendingGeneratedEntryState.expired,
      );
    });

    test('pending set is bounded; oldest record is evicted', () {
      final service = DesktopBrowserPendingGenerationService();
      final first = _create(service);
      for (
        var i = 0;
        i < DesktopBrowserPendingGenerationService.maxRecords;
        i++
      ) {
        _create(service);
      }

      expect(service.find(first.id), isNull);
      expect(service.consume(first.id, origin: 'https://example.com'), isNull);
      expect(
        service.pendingCount,
        DesktopBrowserPendingGenerationService.maxRecords,
      );
    });

    test('clearAll removes every record and reference (app exit path)', () {
      final service = DesktopBrowserPendingGenerationService();
      final a = _create(service);
      final b = _create(service);

      service.clearAll();

      expect(service.find(a.id), isNull);
      expect(service.find(b.id), isNull);
      expect(service.pendingCount, 0);
      expect(service.consume(a.id, origin: 'https://example.com'), isNull);
    });
  });

  group('pendingListenable (B005 watch)', () {
    test('create/consume/reject/clearAll transitions are reflected', () {
      final service = DesktopBrowserPendingGenerationService();
      addTearDown(service.clearAll);
      final listenable = service.pendingListenable;
      expect(listenable.value, isEmpty);

      final a = _create(service);
      expect(listenable.value, hasLength(1));
      expect(listenable.value.single.id, a.id);
      expect(listenable.value.single.state, PendingGeneratedEntryState.pending);

      service.consume(a.id, origin: 'https://example.com');
      expect(listenable.value, isEmpty);

      final b = _create(service);
      expect(listenable.value, hasLength(1));
      service.reject(b.id);
      expect(listenable.value, isEmpty);

      _create(service);
      _create(service);
      expect(listenable.value, hasLength(2));
      service.clearAll();
      expect(listenable.value, isEmpty);
    });

    test('expired records leave the listenable without any caller poke', () {
      // Virtual time: the service's expiry timer and its injected clock are
      // both driven by `async.elapse`, so this asserts the expiry behaviour
      // without depending on how long a real sleep actually takes.
      fakeAsync((async) {
        final service = _fakeClockService(async);
        addTearDown(service.clearAll);
        final snapshot = _create(
          service,
          ttl: const Duration(milliseconds: 60),
        );
        expect(service.pendingListenable.value, hasLength(1));

        // No find()/pendingCount() poke: the service's own expiry timer must
        // materialize the lazy expiry for listeners.
        async.elapse(const Duration(milliseconds: 200));

        expect(service.pendingListenable.value, isEmpty);
        expect(
          service.find(snapshot.id)!.state,
          PendingGeneratedEntryState.expired,
        );
      });
    });

    test('two pendings with different TTLs expire in sequence: the timer '
        're-arms on the survivor', () {
      // This assertion lives in a 160ms wall-clock window (after the 60ms TTL,
      // before the 220ms one). With a real sleep it only passed while the
      // process was never descheduled for long: bumping the first sleep by
      // 100ms makes it fail outright, which is exactly what a loaded CI does
      // for free. Virtual time removes the window instead of widening it.
      fakeAsync((async) {
        final service = _fakeClockService(async);
        addTearDown(service.clearAll);
        final short = _create(service, ttl: const Duration(milliseconds: 60));
        final long = _create(
          service,
          origin: 'https://other.example',
          ttl: const Duration(milliseconds: 220),
        );
        expect(service.pendingListenable.value, hasLength(2));

        // After the first expiry the listenable must still carry the longer
        // record — proving the one-shot timer re-armed for the survivor.
        async.elapse(const Duration(milliseconds: 130));
        expect(service.pendingListenable.value.map((s) => s.id), [long.id]);
        expect(
          service.find(short.id)!.state,
          PendingGeneratedEntryState.expired,
        );

        async.elapse(const Duration(milliseconds: 200));
        expect(service.pendingListenable.value, isEmpty);
        expect(
          service.find(long.id)!.state,
          PendingGeneratedEntryState.expired,
        );
      });
    });

    test('listenable surface never carries the secret', () {
      final service = DesktopBrowserPendingGenerationService();
      addTearDown(service.clearAll);
      final observed = <String>[];
      service.pendingListenable.addListener(() {
        for (final snapshot in service.pendingListenable.value) {
          // Every string reachable from the emitted snapshot.
          observed.addAll([
            snapshot.id,
            snapshot.databaseId,
            snapshot.cacheGeneration,
            snapshot.bridgeGeneration,
            snapshot.origin,
            snapshot.toString(),
          ]);
        }
      });

      _create(service);

      expect(observed, isNotEmpty);
      expect(observed.join('\n'), isNot(contains(_generatedValue)));
    });
  });

  group('coordinator lifecycle hooks', () {
    late Directory directory;
    late DesktopBrowserAutofillCacheStore store;
    late DesktopBrowserAutofillRevealBridgeService revealBridge;
    late DesktopBrowserPendingGenerationService pendingGeneration;
    late DesktopBrowserAutofillCoordinator coordinator;

    const entry = VaultEntry(
      id: 'entry-1',
      groupId: 'root',
      title: 'Example',
      username: 'metadata-name',
      password: 'metadata-value',
      url: 'https://example.com',
      notes: '',
    );

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('kv-pending-gen-');
      store = DesktopBrowserAutofillCacheStore(directory: directory);
      const mapper = DesktopBrowserAutofillMetadataMapper();
      revealBridge = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: mapper,
      );
      pendingGeneration = DesktopBrowserPendingGenerationService();
      coordinator = DesktopBrowserAutofillCoordinator(
        store: store,
        mapper: mapper,
        revealBridge: revealBridge,
        pendingGeneration: pendingGeneration,
      );
    });

    tearDown(() async {
      await revealBridge.stop();
    });

    test(
      'clearCredentials (lock / vault close) clears pending secrets',
      () async {
        await coordinator.publishVault(
          databasePath: '/vaults/a.kdbx',
          entries: const [entry],
        );
        final snapshot = _create(pendingGeneration);

        // Lock and vault close both route through clearCredentials, which
        // also stops the reveal bridge.
        await coordinator.clearCredentials(databasePath: '/vaults/a.kdbx');

        expect(pendingGeneration.find(snapshot.id), isNull);
        expect(pendingGeneration.pendingCount, 0);
        expect(await store.readBridgeDescriptor(), isNull);
      },
    );

    test(
      'database switch (republish) clears the previous session pending',
      () async {
        await coordinator.publishVault(
          databasePath: '/vaults/a.kdbx',
          entries: const [entry],
        );
        final snapshot = _create(pendingGeneration, databaseId: 'db-a');

        await coordinator.publishVault(
          databasePath: '/vaults/b.kdbx',
          entries: const [entry],
        );

        expect(pendingGeneration.find(snapshot.id), isNull);
        expect(pendingGeneration.pendingCount, 0);
      },
    );

    test(
      'reveal bridge stop after failed publish clears pending secrets',
      () async {
        final failingStore = _FailingWriteStore(directory: directory);
        const mapper = DesktopBrowserAutofillMetadataMapper();
        final bridge = DesktopBrowserAutofillRevealBridgeService(
          store: failingStore,
          mapper: mapper,
        );
        addTearDown(bridge.stop);
        final failingCoordinator = DesktopBrowserAutofillCoordinator(
          store: failingStore,
          mapper: mapper,
          revealBridge: bridge,
          pendingGeneration: pendingGeneration,
        );
        await failingCoordinator.publishVault(
          databasePath: '/vaults/a.kdbx',
          entries: const [entry],
        );
        final snapshot = _create(pendingGeneration);

        failingStore.failWrites = true;
        await failingCoordinator.publishVault(
          databasePath: '/vaults/a.kdbx',
          entries: const [entry],
        );

        expect(pendingGeneration.find(snapshot.id), isNull);
        expect(await failingStore.readBridgeDescriptor(), isNull);
      },
    );

    test('B005: consume routes through the coordinator into the app new-entry '
        'flow exactly once; page/extension have no mutation path', () async {
      await coordinator.publishVault(
        databasePath: '/vaults/a.kdbx',
        entries: const [entry],
      );
      final snapshot = _create(pendingGeneration);

      final draft = coordinator.consumePendingGenerationForNewEntry(
        id: snapshot.id,
        origin: 'https://example.com',
      );

      expect(draft, isNotNull);
      expect(draft!.password, _generatedValue);
      expect(draft.origin, 'https://example.com');
      // One-shot: the normal app save flow owns the vault mutation from
      // here; a replay (e.g. from a page/extension retry) gets nothing.
      expect(
        coordinator.consumePendingGenerationForNewEntry(
          id: snapshot.id,
          origin: 'https://example.com',
        ),
        isNull,
      );
    });

    test('generated secret never reaches cache, descriptor, pending '
        'association file, or logs', () async {
      // Search the true secret in every observable surface: every file
      // under the store directory (metadata cache, bridge descriptor,
      // pending_associations.json) and everything printed/logged.
      Future<void> expectNoSecretOnDisk() async {
        await for (final fileEntity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (fileEntity is File) {
            final content = await fileEntity.readAsString();
            expect(
              content,
              isNot(contains(_generatedValue)),
              reason: 'secret leaked to ${fileEntity.uri.pathSegments.last}',
            );
          }
        }
      }

      final printed = <String>[];
      await runZoned(
        () async {
          await coordinator.publishVault(
            databasePath: '/vaults/a.kdbx',
            entries: const [entry],
          );
          final snapshot = _create(pendingGeneration);
          coordinator.consumePendingGenerationForNewEntry(
            id: snapshot.id,
            origin: 'https://example.com',
          );
          pendingGeneration.reject(_create(pendingGeneration).id);
          // Scan while cache/descriptor/pending files still exist on disk.
          await expectNoSecretOnDisk();
          await coordinator.clearCredentials(databasePath: '/vaults/a.kdbx');
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      await expectNoSecretOnDisk();
      expect(printed.join('\n'), isNot(contains(_generatedValue)));
    });
  });
}

class _FailingWriteStore extends DesktopBrowserAutofillCacheStore {
  _FailingWriteStore({required Directory directory})
    : super(directory: directory);

  bool failWrites = false;

  @override
  Future<void> writeMetadataCache(
    DesktopBrowserAutofillMetadataCache cache,
  ) async {
    if (failWrites) {
      throw StateError('metadata write failed');
    }
    await super.writeMetadataCache(cache);
  }
}
