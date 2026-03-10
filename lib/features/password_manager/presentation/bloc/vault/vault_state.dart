import 'package:equatable/equatable.dart';

import '../../../domain/models/database_sync_status.dart';
import '../../../domain/models/drive_remote_file.dart';
import '../../../domain/models/sync_conflict.dart';
import '../../../domain/models/vault_entry.dart';
import '../../../domain/models/vault_group.dart';

enum VaultEntrySort { titleAsc, titleDesc, usernameAsc }

class VaultState extends Equatable {
  const VaultState({
    required this.databasePath,
    this.rootGroupId,
    this.currentGroupId,
    this.groups = const [],
    this.entries = const [],
    this.allEntries = const [],
    this.visibleEntries = const [],
    this.expandedGroupIds = const [],
    this.recycleBinEntries = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.isRecycleBinView = false,
    this.isRecycleBinLoading = false,
    this.searchQuery = '',
    this.sortBy = VaultEntrySort.titleAsc,
    this.errorMessage,
    this.infoMessage,
    this.isDriveConnected = false,
    this.isDriveLinked = false,
    this.autoSyncEnabled = true,
    this.syncStatus = DatabaseSyncStatus.disconnected,
    this.syncError,
    this.lastSyncAt,
    this.pendingSyncConflict,
    this.remoteDriveFiles = const [],
    this.isLoadingRemoteDriveFiles = false,
    this.linkedDriveFileName,
  });

  factory VaultState.initial({required String databasePath}) {
    return VaultState(databasePath: databasePath, isLoading: true);
  }

  final String databasePath;
  final String? rootGroupId;
  final String? currentGroupId;
  final List<VaultGroup> groups;
  final List<VaultEntry> entries;
  final List<VaultEntry> allEntries;
  final List<VaultEntry> visibleEntries;
  final List<String> expandedGroupIds;
  final List<VaultEntry> recycleBinEntries;
  final bool isLoading;
  final bool isSaving;
  final bool isRecycleBinView;
  final bool isRecycleBinLoading;
  final String searchQuery;
  final VaultEntrySort sortBy;
  final String? errorMessage;
  final String? infoMessage;
  final bool isDriveConnected;
  final bool isDriveLinked;
  final bool autoSyncEnabled;
  final DatabaseSyncStatus syncStatus;
  final String? syncError;
  final DateTime? lastSyncAt;
  final SyncConflict? pendingSyncConflict;
  final List<DriveRemoteFile> remoteDriveFiles;
  final bool isLoadingRemoteDriveFiles;
  final String? linkedDriveFileName;

  VaultState copyWith({
    String? rootGroupId,
    String? currentGroupId,
    List<VaultGroup>? groups,
    List<VaultEntry>? entries,
    List<VaultEntry>? allEntries,
    List<VaultEntry>? visibleEntries,
    List<String>? expandedGroupIds,
    List<VaultEntry>? recycleBinEntries,
    bool? isLoading,
    bool? isSaving,
    bool? isRecycleBinView,
    bool? isRecycleBinLoading,
    String? searchQuery,
    VaultEntrySort? sortBy,
    String? errorMessage,
    String? infoMessage,
    bool? isDriveConnected,
    bool? isDriveLinked,
    bool? autoSyncEnabled,
    DatabaseSyncStatus? syncStatus,
    String? syncError,
    DateTime? lastSyncAt,
    SyncConflict? pendingSyncConflict,
    List<DriveRemoteFile>? remoteDriveFiles,
    bool? isLoadingRemoteDriveFiles,
    String? linkedDriveFileName,
    bool clearError = false,
    bool clearInfo = false,
    bool clearSyncError = false,
    bool clearSyncConflict = false,
  }) {
    return VaultState(
      databasePath: databasePath,
      rootGroupId: rootGroupId ?? this.rootGroupId,
      currentGroupId: currentGroupId ?? this.currentGroupId,
      groups: groups ?? this.groups,
      entries: entries ?? this.entries,
      allEntries: allEntries ?? this.allEntries,
      visibleEntries: visibleEntries ?? this.visibleEntries,
      expandedGroupIds: expandedGroupIds ?? this.expandedGroupIds,
      recycleBinEntries: recycleBinEntries ?? this.recycleBinEntries,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isRecycleBinView: isRecycleBinView ?? this.isRecycleBinView,
      isRecycleBinLoading: isRecycleBinLoading ?? this.isRecycleBinLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      infoMessage: clearInfo ? null : infoMessage ?? this.infoMessage,
      isDriveConnected: isDriveConnected ?? this.isDriveConnected,
      isDriveLinked: isDriveLinked ?? this.isDriveLinked,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: clearSyncError ? null : syncError ?? this.syncError,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      pendingSyncConflict: clearSyncConflict
          ? null
          : pendingSyncConflict ?? this.pendingSyncConflict,
      remoteDriveFiles: remoteDriveFiles ?? this.remoteDriveFiles,
      isLoadingRemoteDriveFiles:
          isLoadingRemoteDriveFiles ?? this.isLoadingRemoteDriveFiles,
      linkedDriveFileName: linkedDriveFileName ?? this.linkedDriveFileName,
    );
  }

  VaultGroup? get currentGroup {
    if (currentGroupId == null) {
      return null;
    }
    for (final group in groups) {
      if (group.id == currentGroupId) {
        return group;
      }
    }
    return null;
  }

  List<VaultGroup> get currentChildGroups {
    if (currentGroupId == null) {
      return const [];
    }
    return groups
        .where(
          (group) => group.parentId == currentGroupId && !group.isRecycleBin,
        )
        .toList();
  }

  List<VaultGroup> breadcrumbs() {
    final current = currentGroup;
    if (current == null) {
      return const [];
    }

    final byId = {for (final group in groups) group.id: group};
    final path = <VaultGroup>[];
    VaultGroup? cursor = current;
    while (cursor != null) {
      path.insert(0, cursor);
      cursor = cursor.parentId == null ? null : byId[cursor.parentId!];
    }

    return path;
  }

  @override
  List<Object?> get props => [
    databasePath,
    rootGroupId,
    currentGroupId,
    groups,
    entries,
    allEntries,
    visibleEntries,
    expandedGroupIds,
    recycleBinEntries,
    isLoading,
    isSaving,
    isRecycleBinView,
    isRecycleBinLoading,
    searchQuery,
    sortBy,
    errorMessage,
    infoMessage,
    isDriveConnected,
    isDriveLinked,
    autoSyncEnabled,
    syncStatus,
    syncError,
    lastSyncAt,
    pendingSyncConflict,
    remoteDriveFiles,
    isLoadingRemoteDriveFiles,
    linkedDriveFileName,
  ];
}
