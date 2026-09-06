import '../../domain/errors/google_authorization_required_exception.dart';
import '../../domain/models/cloud_storage_error.dart';

/// spec 010 Phase 4: the provider port converts every remote failure into a
/// [CloudStorageException], so presentation must recognise
/// `authorizationRequired` alongside the legacy typed exception that
/// pre-port fakes and tests still throw.
/// The untyped branch matters because `driveOpenErrorMessage` still routes
/// untyped exceptions by message, so a type-only predicate let the picker's
/// heading and button ("Unable to connect" / "Retry") disagree with the body
/// they sat above ("Use Reconnect below"). One predicate now decides all three.
bool isCloudAuthorizationRequired(Object error) {
  if (error is GoogleAuthorizationRequiredException) return true;
  if (error is CloudStorageException) {
    return error.code == CloudStorageErrorCode.authorizationRequired;
  }
  final normalized = error.toString().toLowerCase();
  return normalized.contains('authorization needs to be renewed') ||
      normalized.contains('authorization is outdated') ||
      normalized.contains('google account not connected');
}
