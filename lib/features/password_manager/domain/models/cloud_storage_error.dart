/// spec 010 §Error and security requirements — the one provider-neutral
/// failure type every cloud storage call may throw.
///
/// The exception carries the enum and nothing else: no cause, response,
/// provider exception, status text or interpolated detail. `safeCode` and
/// `safeMessage` are exhaustive constants; presentation shows `safeMessage`
/// exactly, never `toString()` with a prefix or suffix.
enum CloudStorageErrorCode {
  cancelled,
  authenticationFailed,
  authorizationRequired,
  forbidden,
  unsupportedProvider,
  notFound,
  conflict,
  rateLimited,
  timeout,
  networkUnavailable,
  malformedResponse,
  serverFailure,
  unknown,
}

final class CloudStorageException implements Exception {
  const CloudStorageException(this.code);

  final CloudStorageErrorCode code;

  String get safeCode => switch (code) {
    CloudStorageErrorCode.cancelled => 'cloud_storage.cancelled',
    CloudStorageErrorCode.authenticationFailed =>
      'cloud_storage.authentication_failed',
    CloudStorageErrorCode.authorizationRequired =>
      'cloud_storage.authorization_required',
    CloudStorageErrorCode.forbidden => 'cloud_storage.forbidden',
    CloudStorageErrorCode.unsupportedProvider =>
      'cloud_storage.unsupported_provider',
    CloudStorageErrorCode.notFound => 'cloud_storage.not_found',
    CloudStorageErrorCode.conflict => 'cloud_storage.conflict',
    CloudStorageErrorCode.rateLimited => 'cloud_storage.rate_limited',
    CloudStorageErrorCode.timeout => 'cloud_storage.timeout',
    CloudStorageErrorCode.networkUnavailable =>
      'cloud_storage.network_unavailable',
    CloudStorageErrorCode.malformedResponse =>
      'cloud_storage.malformed_response',
    CloudStorageErrorCode.serverFailure => 'cloud_storage.server_failure',
    CloudStorageErrorCode.unknown => 'cloud_storage.unknown',
  };

  String get safeMessage => switch (code) {
    CloudStorageErrorCode.cancelled => 'Cloud storage operation was cancelled.',
    CloudStorageErrorCode.authenticationFailed =>
      'Unable to authenticate with cloud storage.',
    CloudStorageErrorCode.authorizationRequired =>
      'Cloud storage authorization is required.',
    CloudStorageErrorCode.forbidden => 'Cloud storage access was denied.',
    CloudStorageErrorCode.unsupportedProvider =>
      'Cloud storage provider is not supported by this build.',
    CloudStorageErrorCode.notFound => 'Remote file was not found.',
    CloudStorageErrorCode.conflict =>
      'Remote file changed before the operation completed.',
    CloudStorageErrorCode.rateLimited =>
      'Cloud storage is temporarily busy. Try again later.',
    CloudStorageErrorCode.timeout => 'Cloud storage request timed out.',
    CloudStorageErrorCode.networkUnavailable =>
      'Cloud storage is unavailable. Check your connection.',
    CloudStorageErrorCode.malformedResponse =>
      'Cloud storage returned an invalid response.',
    CloudStorageErrorCode.serverFailure =>
      'Cloud storage service is temporarily unavailable.',
    CloudStorageErrorCode.unknown => 'Cloud storage operation failed.',
  };

  @override
  String toString() => safeCode;
}
