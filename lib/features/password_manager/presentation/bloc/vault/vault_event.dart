import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

import '../../../domain/models/vault_custom_field.dart';
import '../../../domain/models/sync_conflict.dart';
import '../../../domain/models/drive_remote_file.dart';
import 'vault_state.dart';

abstract class VaultEvent extends Equatable {
  const VaultEvent();

  @override
  List<Object?> get props => [];
}

class InitializeVault extends VaultEvent {
  const InitializeVault();
}

class OpenGroup extends VaultEvent {
  const OpenGroup(this.groupId);

  final String groupId;

  @override
  List<Object?> get props => [groupId];
}

class OpenParentGroup extends VaultEvent {
  const OpenParentGroup();
}

class ToggleVaultGroupExpanded extends VaultEvent {
  const ToggleVaultGroupExpanded(this.groupId);

  final String groupId;

  @override
  List<Object?> get props => [groupId];
}

class RefreshVault extends VaultEvent {
  const RefreshVault();
}

class UpdateVaultSearchQuery extends VaultEvent {
  const UpdateVaultSearchQuery(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

class ClearVaultSearchQuery extends VaultEvent {
  const ClearVaultSearchQuery();
}

class SetVaultSort extends VaultEvent {
  const SetVaultSort(this.sortBy);

  final VaultEntrySort sortBy;

  @override
  List<Object?> get props => [sortBy];
}

class LoadRecycleBinEntries extends VaultEvent {
  const LoadRecycleBinEntries();
}

class CreateVaultEntry extends VaultEvent {
  const CreateVaultEntry({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    this.customFields = const [],
    this.attachmentPaths = const [],
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final List<VaultCustomField> customFields;
  final List<String> attachmentPaths;

  @override
  List<Object?> get props => [
    title,
    username,
    RedactedValue(password),
    url,
    RedactedValue(notes, redaction: '<redacted notes>'),
    customFields,
    attachmentPaths,
  ];

  @override
  String toString() {
    return 'CreateVaultEntry('
        'title: $title, '
        'username: $username, '
        'password: <redacted>, '
        'url: $url, '
        'notes: <redacted>, '
        'customFields: ${customFields.length}, '
        'attachmentPaths: ${attachmentPaths.length})';
  }
}

class UpdateVaultEntry extends VaultEvent {
  const UpdateVaultEntry({
    required this.entryId,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    this.customFields = const [],
  });

  final String entryId;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final List<VaultCustomField> customFields;

  @override
  List<Object?> get props => [
    entryId,
    title,
    username,
    RedactedValue(password),
    url,
    RedactedValue(notes, redaction: '<redacted notes>'),
    customFields,
  ];

  @override
  String toString() {
    return 'UpdateVaultEntry('
        'entryId: $entryId, '
        'title: $title, '
        'username: $username, '
        'password: <redacted>, '
        'url: $url, '
        'notes: <redacted>, '
        'customFields: ${customFields.length})';
  }
}

class DeleteVaultEntry extends VaultEvent {
  const DeleteVaultEntry(this.entryId);

  final String entryId;

  @override
  List<Object?> get props => [entryId];
}

class MoveVaultEntry extends VaultEvent {
  const MoveVaultEntry({required this.entryId, required this.targetGroupId});

  final String entryId;
  final String targetGroupId;

  @override
  List<Object?> get props => [entryId, targetGroupId];
}

class CreateVaultGroup extends VaultEvent {
  const CreateVaultGroup(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

class RenameVaultGroup extends VaultEvent {
  const RenameVaultGroup({required this.groupId, required this.newName});

  final String groupId;
  final String newName;

  @override
  List<Object?> get props => [groupId, newName];
}

class DeleteVaultGroup extends VaultEvent {
  const DeleteVaultGroup(this.groupId);

  final String groupId;

  @override
  List<Object?> get props => [groupId];
}

class MoveVaultGroup extends VaultEvent {
  const MoveVaultGroup({required this.groupId, required this.targetGroupId});

  final String groupId;
  final String targetGroupId;

  @override
  List<Object?> get props => [groupId, targetGroupId];
}

class OpenRecycleBin extends VaultEvent {
  const OpenRecycleBin();
}

class CloseRecycleBin extends VaultEvent {
  const CloseRecycleBin();
}

class RestoreVaultEntry extends VaultEvent {
  const RestoreVaultEntry(this.entryId);

  final String entryId;

  @override
  List<Object?> get props => [entryId];
}

class RestoreVaultGroup extends VaultEvent {
  const RestoreVaultGroup(this.groupId);

  final String groupId;

  @override
  List<Object?> get props => [groupId];
}

class DeleteVaultEntryPermanently extends VaultEvent {
  const DeleteVaultEntryPermanently(this.entryId);

  final String entryId;

  @override
  List<Object?> get props => [entryId];
}

class DeleteVaultGroupPermanently extends VaultEvent {
  const DeleteVaultGroupPermanently(this.groupId);

  final String groupId;

  @override
  List<Object?> get props => [groupId];
}

class EmptyRecycleBin extends VaultEvent {
  const EmptyRecycleBin();
}

class AddVaultAttachment extends VaultEvent {
  const AddVaultAttachment({required this.entryId, required this.filePath});

  final String entryId;
  final String filePath;

  @override
  List<Object?> get props => [entryId, filePath];
}

class RemoveVaultAttachment extends VaultEvent {
  const RemoveVaultAttachment({
    required this.entryId,
    required this.attachmentKey,
  });

  final String entryId;
  final String attachmentKey;

  @override
  List<Object?> get props => [entryId, attachmentKey];
}

class ExportVaultAttachment extends VaultEvent {
  const ExportVaultAttachment({
    required this.entryId,
    required this.attachmentKey,
    required this.destinationDirectory,
  });

  final String entryId;
  final String attachmentKey;
  final String destinationDirectory;

  @override
  List<Object?> get props => [entryId, attachmentKey, destinationDirectory];
}

class ImportVaultEntriesFromCsv extends VaultEvent {
  const ImportVaultEntriesFromCsv({
    required this.filePath,
    this.avoidDuplicates = true,
  });

  final String filePath;
  final bool avoidDuplicates;

  @override
  List<Object?> get props => [filePath, avoidDuplicates];
}

class ClearVaultError extends VaultEvent {
  const ClearVaultError();
}

class ClearVaultInfo extends VaultEvent {
  const ClearVaultInfo();
}

class ConnectGoogleDrive extends VaultEvent {
  const ConnectGoogleDrive();
}

class GoogleDriveReconnectSucceeded extends VaultEvent {
  const GoogleDriveReconnectSucceeded({this.remoteFiles});

  final List<DriveRemoteFile>? remoteFiles;

  @override
  List<Object?> get props => [remoteFiles];
}

class GoogleDriveReconnectFailed extends VaultEvent {
  const GoogleDriveReconnectFailed({
    required this.error,
    required this.stackTrace,
    required this.remoteFiles,
    this.duringRemoteLoad = false,
  });

  final Object error;
  final StackTrace stackTrace;
  final bool remoteFiles;
  final bool duringRemoteLoad;

  // Do not expose provider exception text through Equatable/toString.
  @override
  List<Object?> get props => [remoteFiles, duringRemoteLoad];
}

class DisconnectGoogleDrive extends VaultEvent {
  const DisconnectGoogleDrive();
}

class LinkCurrentDatabaseToDrive extends VaultEvent {
  const LinkCurrentDatabaseToDrive({this.remoteFileId, this.remoteFileName});

  final String? remoteFileId;
  final String? remoteFileName;

  @override
  List<Object?> get props => [remoteFileId, remoteFileName];
}

class SyncCurrentDatabaseNow extends VaultEvent {
  const SyncCurrentDatabaseNow({
    this.resolution,
    this.silentIfConflict = false,
  });

  final SyncConflictResolution? resolution;
  final bool silentIfConflict;

  @override
  List<Object?> get props => [resolution, silentIfConflict];
}

class ToggleCurrentDatabaseAutoSync extends VaultEvent {
  const ToggleCurrentDatabaseAutoSync(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

class ClearVaultSyncFeedback extends VaultEvent {
  const ClearVaultSyncFeedback();
}

class LoadDriveRemoteFiles extends VaultEvent {
  const LoadDriveRemoteFiles({this.query});

  final String? query;

  @override
  List<Object?> get props => [query];
}

class BackgroundDriveSync extends VaultEvent {
  const BackgroundDriveSync();
}

class LoadDuplicates extends VaultEvent {
  const LoadDuplicates();
}

class DeleteDuplicateEntry extends VaultEvent {
  const DeleteDuplicateEntry(this.entryId);

  final String entryId;

  @override
  List<Object?> get props => [entryId];
}

class MergeDuplicateEntries extends VaultEvent {
  const MergeDuplicateEntries({
    required this.primaryId,
    required this.secondaryId,
  });

  final String primaryId;
  final String secondaryId;

  @override
  List<Object?> get props => [primaryId, secondaryId];
}

class RefreshAppleAutofillPendingAssociations extends VaultEvent {
  const RefreshAppleAutofillPendingAssociations();
}

class ConfirmAppleAutofillPendingAssociation extends VaultEvent {
  const ConfirmAppleAutofillPendingAssociation(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

class RejectAppleAutofillPendingAssociation extends VaultEvent {
  const RejectAppleAutofillPendingAssociation(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

class ClearCsvImportOutcome extends VaultEvent {
  const ClearCsvImportOutcome();
}

/// spec-005 T5 ("success" hero, Unlink pill): removes the current
/// database's `DatabaseSyncMapping` without disconnecting the Google
/// account. Distinct from `DisconnectGoogleDrive`, which also revokes the
/// account connection.
class UnlinkCurrentDatabaseFromDrive extends VaultEvent {
  const UnlinkCurrentDatabaseFromDrive();
}
