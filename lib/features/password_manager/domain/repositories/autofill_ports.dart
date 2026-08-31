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

  /// [authSessionTtlMs] is Android-only: how long a device authentication may
  /// be reused before the next release of a secret prompts again. `0` prompts
  /// every time. The Apple side ignores it.
  Future<AppleAutofillV2PublishResult> publishCredentials({
    required String databaseId,
    required List<AppleAutofillV2Credential> credentials,
    int authSessionTtlMs = 0,
  });

  Future<AppleAutofillV2ClearResult> clearCredentials({String? databaseId});

  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations();

  Future<AppleAutofillV2ClearPendingAssociationsResult>
  clearPendingAssociations({List<String>? ids});

  Future<AppleAutofillV2Status> getStatus();

  /// Apple platforms only: whether the Credential Provider extension is
  /// enabled in system settings (`ASCredentialIdentityStore.getState`).
  /// `null` where the question does not apply (Android, unsupported).
  Future<bool?> getExtensionEnabled();

  /// Android only: the token of a save capture the app was launched for, or
  /// `null`. Returns the token once; a second call yields `null`.
  Future<String?> takePendingCaptureToken();

  /// Android only: the captured credential behind [token].
  ///
  /// Returns `null` when the capture is gone — process death, expiry, or a
  /// second read of the same token. That is an expected outcome, not a failure.
  /// Throws [UnsupportedError] on platforms with no capture support.
  Future<AndroidAutofillCapture?> readPendingCapture(String token);

  /// Android only: drops [token] whatever the outcome, and remembers a
  /// `declined` so the same submission is not offered again.
  ///
  /// Throws [UnsupportedError] on platforms with no capture support.
  Future<AppleAutofillV2ClearPendingAssociationsResult> resolvePendingCapture({
    required String token,
    required AndroidAutofillCaptureOutcome outcome,
  });
}
