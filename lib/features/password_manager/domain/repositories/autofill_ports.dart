import '../models/autofill_models.dart';
import '../models/apple_autofill_v2_models.dart';

abstract interface class AutofillPlatformPort {
  Stream<AutofillRequest> get requests;

  Future<void> presentCandidates({
    required AutofillRequest request,
    required List<AutofillCandidate> candidates,
  });

  Future<void> provideSecret({
    required AutofillRequest request,
    required AutofillSecret secret,
  });

  Future<void> failRequest({
    required AutofillRequest request,
    required String reason,
  });
}

abstract interface class AutofillVaultPort {
  Future<List<AutofillCandidate>> findCandidates(AutofillRequest request);

  Future<AutofillSecret> revealSecret({
    required AutofillRequest request,
    required String entryId,
  });
}

abstract interface class AppleAutofillV2Client {
  bool get isSupported;

  Future<AppleAutofillV2PublishResult> publishCredentials({
    required String databaseId,
    required List<AppleAutofillV2Credential> credentials,
  });

  Future<AppleAutofillV2ClearResult> clearCredentials({String? databaseId});

  Future<AppleAutofillV2Status> getStatus();
}
