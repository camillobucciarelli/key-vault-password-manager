import 'package:equatable/equatable.dart';

enum AutofillTargetKind { androidPackage, appleBundleId, webDomain }

class AutofillTarget extends Equatable {
  const AutofillTarget._({required this.kind, required this.value});

  const AutofillTarget.androidPackage(String packageName)
    : this._(kind: AutofillTargetKind.androidPackage, value: packageName);

  const AutofillTarget.appleBundleId(String bundleId)
    : this._(kind: AutofillTargetKind.appleBundleId, value: bundleId);

  const AutofillTarget.webDomain(String domainOrUrl)
    : this._(kind: AutofillTargetKind.webDomain, value: domainOrUrl);

  final AutofillTargetKind kind;
  final String value;

  @override
  List<Object?> get props => [kind, value];
}

enum AutofillRequestIntent { fill, save }

class AutofillRequest extends Equatable {
  const AutofillRequest({
    required this.id,
    required this.intent,
    required this.targets,
    this.policy = const AutofillPolicy.defaults(),
  });

  final String id;
  final AutofillRequestIntent intent;
  final List<AutofillTarget> targets;
  final AutofillPolicy policy;

  @override
  List<Object?> get props => [id, intent, targets, policy];
}

class AutofillCandidate extends Equatable {
  const AutofillCandidate({
    required this.entryId,
    required this.title,
    required this.username,
    required this.hasPassword,
    required this.matchedTargets,
    this.webDomain,
  });

  final String entryId;
  final String title;
  final String username;
  final bool hasPassword;
  final String? webDomain;
  final List<AutofillTarget> matchedTargets;

  @override
  List<Object?> get props => [
    entryId,
    title,
    username,
    hasPassword,
    webDomain,
    matchedTargets,
  ];
}

class AutofillSecret {
  const AutofillSecret({
    required this.entryId,
    required this.username,
    required this.password,
  });

  final String entryId;
  final String username;
  final String password;

  @override
  String toString() =>
      'AutofillSecret(entryId: $entryId, username: $username, password: <redacted>)';
}

class AutofillPolicy extends Equatable {
  const AutofillPolicy({
    this.maxCandidates = 10,
    this.allowUnscopedSuggestions = false,
    this.requireUserPresenceForReveal = true,
  });

  const AutofillPolicy.defaults() : this();

  final int maxCandidates;
  final bool allowUnscopedSuggestions;
  final bool requireUserPresenceForReveal;

  @override
  List<Object?> get props => [
    maxCandidates,
    allowUnscopedSuggestions,
    requireUserPresenceForReveal,
  ];
}
