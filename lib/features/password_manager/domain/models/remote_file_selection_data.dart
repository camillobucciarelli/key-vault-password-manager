import 'package:equatable/equatable.dart';

import 'remote_file.dart';
import 'storage_account_summary.dart';

/// One remote file selection load: the eligible remote `.kdbx` files plus
/// the account they belong to (for the empty-state account label).
class RemoteFileSelectionData extends Equatable {
  const RemoteFileSelectionData({required this.files, required this.account});

  final List<RemoteFile> files;
  final StorageAccountSummary account;

  @override
  List<Object?> get props => [files, account];
}
