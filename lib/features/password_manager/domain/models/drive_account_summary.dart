import 'package:equatable/equatable.dart';

import 'drive_remote_file.dart';

/// C-2 connected Google account summary.
///
/// Mobile obtains a real email from the current `GoogleSignInAccount`.
/// Desktop Drive-only OAuth does not guarantee identity without expanding
/// scopes (out of scope for spec-003), so desktop always returns the exact
/// fallback `displayLabel: 'Google Drive account'`, `email: null`.
class DriveAccountSummary extends Equatable {
  const DriveAccountSummary({required this.displayLabel, this.email});

  static const fallback = DriveAccountSummary(
    displayLabel: 'Google Drive account',
  );

  final String displayLabel;
  final String? email;

  @override
  List<Object?> get props => [displayLabel, email];
}

/// One Drive picker load: the remote `.kdbx` files plus which account they
/// belong to (for the empty-state account label / fallback per C-2).
class DrivePickerData extends Equatable {
  const DrivePickerData({required this.files, required this.account});

  final List<DriveRemoteFile> files;
  final DriveAccountSummary account;

  @override
  List<Object?> get props => [files, account];
}
