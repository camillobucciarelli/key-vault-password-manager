import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';

void main() {
  group('SecureDataSourceImpl.masterPasswordKey (spec-011 FR-4)', () {
    test('derives distinct keys for distinct database ids', () {
      final keyA = SecureDataSourceImpl.masterPasswordKey('db-a');
      final keyB = SecureDataSourceImpl.masterPasswordKey('db-b');

      expect(keyA, isNot(keyB));
    });

    test('derives the key from the database id only', () {
      expect(
        SecureDataSourceImpl.masterPasswordKey('db-a'),
        'MASTER_PASSWORD.db-a',
      );
    });

    test('never collides with the legacy global key', () {
      expect(
        SecureDataSourceImpl.masterPasswordKey('db-a'),
        isNot(SecureDataSourceImpl.legacyMasterPasswordKey),
      );
    });

    test('rejects an empty database id', () {
      expect(
        () => SecureDataSourceImpl.masterPasswordKey('  '),
        throwsArgumentError,
      );
    });
  });
}
