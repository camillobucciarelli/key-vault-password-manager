import 'package:equatable/equatable.dart';

import 'vault_entry.dart';

class MergePreview extends Equatable {
  const MergePreview({
    required this.primary,
    required this.secondary,
    required this.willCopyNotes,
    required this.willCopyOtp,
    required this.customFieldKeysToCopy,
    this.urlsToCopy = const [],
    required this.willCopyAttachments,
  });

  /// The entry that will be kept and enriched (newest by updatedAt/createdAt).
  final VaultEntry primary;

  /// The entry that will be moved to the recycle bin after merge.
  final VaultEntry secondary;

  /// True if primary.notes is empty and secondary.notes is not.
  final bool willCopyNotes;

  /// True if primary has no OTP URI but secondary does.
  final bool willCopyOtp;

  /// Non-OTP custom field keys present in secondary but absent in primary.
  final List<String> customFieldKeysToCopy;

  /// URLs the secondary carries (primary URL + URL custom fields) that the
  /// primary does not; copied as extra-URL custom fields on merge.
  final List<String> urlsToCopy;

  /// True if secondary has at least one attachment whose name is absent in primary.
  final bool willCopyAttachments;

  bool get hasAnythingToCopy =>
      willCopyNotes ||
      willCopyOtp ||
      customFieldKeysToCopy.isNotEmpty ||
      urlsToCopy.isNotEmpty ||
      willCopyAttachments;

  @override
  List<Object?> get props => [
    primary,
    secondary,
    willCopyNotes,
    willCopyOtp,
    customFieldKeysToCopy,
    urlsToCopy,
    willCopyAttachments,
  ];
}
