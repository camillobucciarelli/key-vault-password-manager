// spec-005 T18: fixed fixture -> fixed score (AC6); reuse detection works on
// hashes, never plaintext; injected `now` drives the "old" category.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/duplicate_group.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_health_report.dart';
import 'package:password_manager/features/password_manager/domain/services/vault_health_service.dart';

VaultEntry _entry({
  required String id,
  String url = 'example.com',
  String username = 'user',
  String password = 'Qx7#mPz9Lk2\$Vw8', // ~97 bits, never weak/reused here.
  DateTime? lastPasswordChangedAt,
}) {
  return VaultEntry(
    id: id,
    groupId: 'root',
    title: id,
    username: username,
    password: password,
    url: url,
    notes: '',
    lastPasswordChangedAt: lastPasswordChangedAt,
  );
}

void main() {
  final service = const VaultHealthService();
  final now = DateTime(2026, 1, 1);

  // 10 entries: 2 weak, 2 reused (same password), 1 old, 1 unmatchable,
  // 4 otherwise-healthy. A separate DuplicateGroup fixture (independent of
  // the entries list, matching the service's signature) supplies 1 group.
  // Every entry below gets its own unique password (except the deliberate
  // reused-1/reused-2 pair) — the `_entry()` default is intentionally not
  // reused here, or every entry would collide into the "reused" category.
  List<VaultEntry> fixtureEntries() => [
    _entry(id: 'weak-1', password: 'abc'), // 3*log2(26) ~= 14.1 bits
    _entry(id: 'weak-2', password: '123'), // 3*log2(10) ~= 10.0 bits
    _entry(id: 'reused-1', password: 'Tr0ub4dor&Zx9!Qp'),
    _entry(id: 'reused-2', password: 'Tr0ub4dor&Zx9!Qp'),
    _entry(
      id: 'old-1',
      password: 'Zn5!qLp8Rk3@Tx6a',
      lastPasswordChangedAt: now.subtract(const Duration(days: 800)),
    ),
    _entry(
      id: 'unmatchable-1',
      password: 'Un8#Mk3\$Rp7@Xz2q',
      url: '',
      username: '',
    ),
    _entry(
      id: 'healthy-1',
      password: 'Hl1!Nb6\$Wq4@Zt9c',
      lastPasswordChangedAt: now.subtract(const Duration(days: 10)),
    ),
    _entry(
      id: 'healthy-2',
      password: 'Hl2!Nb7\$Wq5@Zt0c',
      lastPasswordChangedAt: now.subtract(const Duration(days: 10)),
    ),
    _entry(id: 'healthy-3', password: 'Hl3!Nb8\$Wq6@Zt1c'),
    _entry(id: 'healthy-4', password: 'Hl4!Nb9\$Wq7@Zt2c'),
  ];

  final fixtureDuplicateGroups = [
    DuplicateGroup(
      sharedUrl: 'dup.example.com',
      sharedUsername: 'dup-user',
      entries: [
        _entry(id: 'dup-a', url: 'dup.example.com', username: 'dup-user'),
        _entry(id: 'dup-b', url: 'dup.example.com', username: 'dup-user'),
      ],
    ),
  ];

  test('exact category counts and score for the fixed fixture (AC6)', () {
    final report = service.buildReport(
      activeEntries: fixtureEntries(),
      duplicateGroups: fixtureDuplicateGroups,
      now: now,
    );

    expect(
      report.category(HealthCategoryKind.weak).count,
      2,
      reason: 'weak-1, weak-2',
    );
    expect(
      report.category(HealthCategoryKind.reused).count,
      2,
      reason: 'reused-1, reused-2 share a password hash',
    );
    expect(report.category(HealthCategoryKind.old).count, 1);
    expect(report.category(HealthCategoryKind.duplicates).count, 1);
    expect(report.category(HealthCategoryKind.unmatchable).count, 1);

    // score = round(100 * (1 - (.35*2/10 + .25*2/10 + .15*1/10 + .15*1/10
    //   + .10*1/10))) = round(100 * (1 - 0.16)) = 84
    expect(report.score, 84);
  });

  test('same vault + same now => same report every time (determinism)', () {
    final first = service.buildReport(
      activeEntries: fixtureEntries(),
      duplicateGroups: fixtureDuplicateGroups,
      now: now,
    );
    final second = service.buildReport(
      activeEntries: fixtureEntries(),
      duplicateGroups: fixtureDuplicateGroups,
      now: now,
    );

    expect(first, second);
    expect(first.score, second.score);
  });

  test('reused detection never leaks a plaintext password into the report', () {
    final report = service.buildReport(
      activeEntries: fixtureEntries(),
      duplicateGroups: fixtureDuplicateGroups,
      now: now,
    );

    final serialized = report.toString();
    for (final entry in fixtureEntries()) {
      if (entry.password.isEmpty) continue;
      expect(
        serialized.contains(entry.password),
        isFalse,
        reason: 'plaintext password must never appear in VaultHealthReport',
      );
    }
    // Category entryIds are entry ids only.
    for (final category in report.categories) {
      for (final id in category.entryIds) {
        expect(id, isNot(contains(' '))); // ids, not passwords/values
      }
    }
  });

  test('injected now drives the "old" category, not DateTime.now()', () {
    final entries = [
      _entry(
        id: 'borderline',
        lastPasswordChangedAt: DateTime(2024, 1, 2), // just under 2y before
      ),
    ];

    final notOldYet = service.buildReport(
      activeEntries: entries,
      duplicateGroups: const [],
      now: DateTime(2026, 1, 1),
    );
    expect(notOldYet.category(HealthCategoryKind.old).count, 0);

    final nowOld = service.buildReport(
      activeEntries: entries,
      duplicateGroups: const [],
      now: DateTime(2026, 1, 3),
    );
    expect(nowOld.category(HealthCategoryKind.old).count, 1);
  });

  test('empty vault scores 100, no division by zero', () {
    final report = service.buildReport(
      activeEntries: const [],
      duplicateGroups: const [],
      now: now,
    );
    expect(report.score, 100);
  });
}
