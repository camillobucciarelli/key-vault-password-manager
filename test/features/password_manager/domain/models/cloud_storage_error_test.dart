import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/cloud_storage_error.dart';

// spec 010 §Error and security requirements — the exact safe code / message
// table. Every enum value has one row; a new value without a row fails here.
void main() {
  const table = <CloudStorageErrorCode, (String, String)>{
    CloudStorageErrorCode.cancelled: (
      'cloud_storage.cancelled',
      'Cloud storage operation was cancelled.',
    ),
    CloudStorageErrorCode.authenticationFailed: (
      'cloud_storage.authentication_failed',
      'Unable to authenticate with cloud storage.',
    ),
    CloudStorageErrorCode.authorizationRequired: (
      'cloud_storage.authorization_required',
      'Cloud storage authorization is required.',
    ),
    CloudStorageErrorCode.forbidden: (
      'cloud_storage.forbidden',
      'Cloud storage access was denied.',
    ),
    CloudStorageErrorCode.unsupportedProvider: (
      'cloud_storage.unsupported_provider',
      'Cloud storage provider is not supported by this build.',
    ),
    CloudStorageErrorCode.notFound: (
      'cloud_storage.not_found',
      'Remote file was not found.',
    ),
    CloudStorageErrorCode.conflict: (
      'cloud_storage.conflict',
      'Remote file changed before the operation completed.',
    ),
    CloudStorageErrorCode.rateLimited: (
      'cloud_storage.rate_limited',
      'Cloud storage is temporarily busy. Try again later.',
    ),
    CloudStorageErrorCode.timeout: (
      'cloud_storage.timeout',
      'Cloud storage request timed out.',
    ),
    CloudStorageErrorCode.networkUnavailable: (
      'cloud_storage.network_unavailable',
      'Cloud storage is unavailable. Check your connection.',
    ),
    CloudStorageErrorCode.malformedResponse: (
      'cloud_storage.malformed_response',
      'Cloud storage returned an invalid response.',
    ),
    CloudStorageErrorCode.serverFailure: (
      'cloud_storage.server_failure',
      'Cloud storage service is temporarily unavailable.',
    ),
    CloudStorageErrorCode.unknown: (
      'cloud_storage.unknown',
      'Cloud storage operation failed.',
    ),
  };

  test('every enum value has exactly one table row', () {
    expect(table.keys.toSet(), CloudStorageErrorCode.values.toSet());
  });

  for (final entry in table.entries) {
    test('${entry.key.name}: exact safe code, message and toString', () {
      final e = CloudStorageException(entry.key);
      expect(e.safeCode, entry.value.$1);
      expect(e.safeMessage, entry.value.$2);
      expect(e.toString(), entry.value.$1);
    });
  }
}
