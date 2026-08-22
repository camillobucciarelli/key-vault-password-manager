// Platform prerequisite: this suite uses `Link.create` to build symlink
// aliases. On Windows that requires Developer Mode or an elevated shell;
// without it these tests fail for environment reasons only. Deliberately not
// skipped — CI Flutter jobs run on `ubuntu-latest`, and macOS is unaffected.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/database_path_mutex.dart';
import 'package:path/path.dart' as p;

// =============================================================================
// spec 008 Gate 1 T104/T107 — mutex serialization, alias coalescing, global
// fallback and deadlock freedom. A deadlock here shows up as a test timeout.
// =============================================================================

void main() {
  late Directory root;
  late String base;
  late DatabasePathMutex mutex;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('path_mutex_');
    base = root.resolveSymbolicLinksSync();
    mutex = DatabasePathMutex();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<String> vault(String name) async =>
      (await File(p.join(base, name)).writeAsBytes([1, 2, 3])).path;

  /// Starts a lock holder and waits until it is INSIDE the critical section.
  /// Returns the completer that lets it out and the pending future.
  Future<(Completer<void>, Future<void>)> hold(
    List<String> paths,
    List<String> order,
    String tag,
  ) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final done = mutex.withDatabaseLock(paths, () async {
      order.add('$tag-in');
      entered.complete();
      await release.future;
      order.add('$tag-out');
    });
    await entered.future;
    return (release, done);
  }

  /// Asserts [paths2] cannot enter while [paths1] is held, then that it runs
  /// after release.
  Future<void> expectSerialized(
    List<String> paths1,
    List<String> paths2,
  ) async {
    final order = <String>[];
    final (release, first) = await hold(paths1, order, 'a');
    final second = mutex.withDatabaseLock(paths2, () async {
      order.add('b-in');
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(order, ['a-in'], reason: 'second acquisition entered while held');
    release.complete();
    await Future.wait([first, second]);
    expect(order, ['a-in', 'a-out', 'b-in']);
  }

  group('T104 serialization and coalescing', () {
    test('two acquisitions on the same path serialize', () async {
      final path = await vault('v.kdbx');
      await expectSerialized([path], [path]);
    });

    test('a symlink alias serializes with its target', () async {
      final real = await vault('v.kdbx');
      final link = Link(p.join(base, 'alias.kdbx'));
      await link.create(real);
      await expectSerialized([real], [link.path]);
    });

    test('a relative spelling serializes with the absolute one', () async {
      final path = await vault('v.kdbx');
      final previous = Directory.current;
      Directory.current = base;
      addTearDown(() => Directory.current = previous);
      await expectSerialized([path], ['v.kdbx']);
    });

    test('hard links serialize where the platform supports them', () async {
      final original = await vault('v.kdbx');
      final linked = p.join(base, 'hard.kdbx');
      final result = Platform.isWindows
          ? await Process.run('fsutil', [
              'hardlink',
              'create',
              linked,
              original,
            ])
          : await Process.run('ln', [original, linked]);
      expect(
        result.exitCode,
        0,
        reason: 'hard-link creation failed: ${result.stderr}',
      );

      // Different canonical strings, one inode: only the pairwise entity
      // probe inside the mutex can coalesce these.
      await expectSerialized([original], [linked]);
    });

    test('proven-distinct databases proceed in parallel', () async {
      final a = await vault('a.kdbx');
      final b = await vault('b.kdbx');
      final order = <String>[];
      final (release, first) = await hold([a], order, 'a');

      await mutex
          .withDatabaseLock([b], () async => order.add('b-in'))
          .timeout(const Duration(seconds: 5));
      expect(order, [
        'a-in',
        'b-in',
      ], reason: 'a distinct database must not wait behind an unrelated one');
      release.complete();
      await first;
    });

    test(
      'duplicate and aliased paths in one call never self-deadlock',
      () async {
        final real = await vault('v.kdbx');
        final link = Link(p.join(base, 'alias.kdbx'));
        await link.create(real);

        final result = await mutex
            .withDatabaseLock([
              real,
              real,
              link.path,
              p.join(base, '.', 'v.kdbx'),
            ], () async => 'done')
            .timeout(const Duration(seconds: 5));
        expect(result, 'done');
      },
    );

    test(
      'inverse concurrent renames do not deadlock and stay exclusive',
      () async {
        final a = await vault('a.kdbx');
        final b = await vault('b.kdbx');
        var active = 0;
        var maxActive = 0;

        Future<void> renameLike(List<String> paths) =>
            mutex.withDatabaseLock(paths, () async {
              active++;
              maxActive = active > maxActive ? active : maxActive;
              await Future<void>.delayed(const Duration(milliseconds: 10));
              active--;
            });

        // A→B and B→A dispatched together: without dedupe+deterministic
        // ordering (or the atomic reservation) this is the textbook deadlock.
        await Future.wait([
          renameLike([a, b]),
          renameLike([b, a]),
        ]).timeout(const Duration(seconds: 5));
        expect(maxActive, 1, reason: 'overlapping path sets must be exclusive');
      },
    );

    test(
      'a multi-path holder excludes a single-path acquisition on a member',
      () async {
        final a = await vault('a.kdbx');
        final b = await vault('b.kdbx');
        await expectSerialized([a, b], [b]);
      },
    );

    test('the lock is released when the action throws', () async {
      final path = await vault('v.kdbx');
      await expectLater(
        mutex.withDatabaseLock<void>([path], () async => throw StateError('x')),
        throwsStateError,
      );
      // A leaked lock would hang this second acquisition.
      await mutex
          .withDatabaseLock([path], () async {})
          .timeout(const Duration(seconds: 5));
    });

    test(
      'PINNED: nested acquisition on the same lock does not run while held',
      () async {
        // MEDIUM-2 (tester): reentrancy is documented as unsupported — a
        // writer that awaits a nested `withDatabaseLock` on a lock it already
        // holds deadlocks. This pins that behaviour so a silent change to
        // reentrant semantics (or an accidental pass-through) fails loudly.
        // T105 review must audit routed writers for exactly this nesting.
        final path = await vault('v.kdbx');
        var innerRan = false;
        late Future<void> inner;
        await mutex.withDatabaseLock([path], () async {
          inner = mutex.withDatabaseLock([path], () async {
            innerRan = true;
          });
          await Future.any<void>([
            inner,
            Future<void>.delayed(const Duration(milliseconds: 200)),
          ]);
          expect(
            innerRan,
            isFalse,
            reason:
                'the nested acquisition entered while the outer holder was '
                'inside the critical section — reentrancy silently became '
                'supported, update the mutex contract and the T105 audit note',
          );
        });
        // The deadlock is only for an outer that AWAITS the inner: once the
        // outer releases, the queued inner proceeds normally.
        await inner.timeout(const Duration(seconds: 5));
        expect(innerRan, isTrue);
      },
    );

    test('an empty path set is rejected', () async {
      await expectLater(
        mutex.withDatabaseLock(const <String>[], () async {}),
        throwsArgumentError,
      );
    });
  });

  group('T104 global fallback for unproven identity', () {
    // A target whose parent directory does not exist is the resolver's
    // unproven case: its future case semantics cannot be probed.
    String unprovenPath() => p.join(base, 'no-such-dir', 'deep', 'v.kdbx');

    test('an unproven acquisition waits for every per-path holder', () async {
      final a = await vault('a.kdbx');
      await expectSerialized([a], [unprovenPath()]);
    });

    test(
      'a per-path acquisition waits for an unproven (global) holder',
      () async {
        final a = await vault('a.kdbx');
        await expectSerialized([unprovenPath()], [a]);
      },
    );

    test('two unproven acquisitions serialize with each other', () async {
      // Distinct spellings, both unproven: they might alias, so they must
      // never run concurrently.
      await expectSerialized(
        [p.join(base, 'ghost-a', 'v.kdbx')],
        [p.join(base, 'ghost-b', 'v.kdbx')],
      );
    });

    test(
      'one unproven path in a set drags the whole set to the global lock',
      () async {
        final a = await vault('a.kdbx');
        final b = await vault('b.kdbx');
        await expectSerialized([a, unprovenPath()], [b]);
      },
    );
  });
}
