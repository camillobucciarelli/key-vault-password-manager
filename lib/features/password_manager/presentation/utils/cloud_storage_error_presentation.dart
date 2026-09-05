import '../../domain/errors/google_authorization_required_exception.dart';
import '../../domain/models/cloud_storage_error.dart';

/// spec 010 Phase 4: the provider port converts every remote failure into a
/// [CloudStorageException], so presentation must recognise
/// `authorizationRequired` alongside the legacy typed exception that
/// pre-port fakes and tests still throw.
bool isCloudAuthorizationRequired(Object error) =>
    error is GoogleAuthorizationRequiredException ||
    (error is CloudStorageException &&
        error.code == CloudStorageErrorCode.authorizationRequired);
