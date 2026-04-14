import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_state.dart';

void main() {
  group('VaultState background sync fields', () {
    test('isSyncing defaults to false', () {
      final state = VaultState(databasePath: '/db.kdbx');
      expect(state.isSyncing, isFalse);
    });

    test('isSyncReloadPending defaults to false', () {
      final state = VaultState(databasePath: '/db.kdbx');
      expect(state.isSyncReloadPending, isFalse);
    });

    test('copyWith sets isSyncing', () {
      final state = VaultState(databasePath: '/db.kdbx');
      expect(state.copyWith(isSyncing: true).isSyncing, isTrue);
    });

    test('copyWith sets isSyncReloadPending', () {
      final state = VaultState(databasePath: '/db.kdbx');
      expect(
        state.copyWith(isSyncReloadPending: true).isSyncReloadPending,
        isTrue,
      );
    });

    test('clearSyncReloadPending resets isSyncReloadPending to false', () {
      final state = VaultState(
        databasePath: '/db.kdbx',
        isSyncReloadPending: true,
      );
      expect(
        state.copyWith(clearSyncReloadPending: true).isSyncReloadPending,
        isFalse,
      );
    });

    test('isSyncing change makes states non-equal', () {
      final a = VaultState(databasePath: '/db.kdbx', isSyncing: true);
      final b = VaultState(databasePath: '/db.kdbx', isSyncing: false);
      expect(a, isNot(equals(b)));
    });

    test('isSyncReloadPending change makes states non-equal', () {
      final a = VaultState(databasePath: '/db.kdbx', isSyncReloadPending: true);
      final b = VaultState(
        databasePath: '/db.kdbx',
        isSyncReloadPending: false,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('BackgroundDriveSync event', () {
    test('two instances are equal', () {
      expect(
        const BackgroundDriveSync(),
        equals(const BackgroundDriveSync()),
      );
    });
  });
}
