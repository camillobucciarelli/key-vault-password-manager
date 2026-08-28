import 'package:equatable/equatable.dart';

import '../../../domain/models/apple_autofill_v2_models.dart';
import '../../../domain/models/database_sync_status.dart';
import '../../../domain/models/drive_remote_file.dart';
import '../../../domain/models/duplicate_group.dart';
import '../../../domain/models/sync_conflict.dart';
import '../../../domain/models/vault_entry.dart';
import '../../../domain/models/vault_group.dart';
import '../../../domain/models/vault_health_report.dart';
import '../../../data/services/vault_csv_import_service.dart'
    show CsvImportOutcome;

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
    this.sortBy = VaultEntrySort.usernameAsc,
    this.errorMessage,
    this.infoMessage,
    this.isDriveConnected = false,
    this.isDriveLinked = false,
    this.autoSyncEnabled = true,
    this.syncStatus = DatabaseSyncStatus.disconnected,
    this.syncError,
    this.driveReconnectRequired = false,
    this.lastSyncAt,
    this.pendingSyncConflict,
    this.remoteDriveFiles = const [],
    this.isLoadingRemoteDriveFiles = false,
    this.remoteDriveFilesError,
    this.remoteDriveFilesReconnectRequired = false,
    this.linkedDriveFileName,
    this.isSyncing = false,
    this.isSyncReloadPending = false,
    this.isOffline = false,
    this.duplicateGroups = const [],
    this.isDuplicatesLoading = false,
    this.pendingAppleAutofillAssociations = const [],
    this.healthReport = VaultHealthReport.empty,
    this.lastCsvImportOutcome,
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
  final bool driveReconnectRequired;
  final DateTime? lastSyncAt;
  final SyncConflict? pendingSyncConflict;
  final List<DriveRemoteFile> remoteDriveFiles;
  final bool isLoadingRemoteDriveFiles;
  final String? remoteDriveFilesError;
  final bool remoteDriveFilesReconnectRequired;
  final String? linkedDriveFileName;
  final bool isSyncing;
  final bool isSyncReloadPending;

  /// spec-005 T7: true only for connection-level sync failures
  /// (`SocketException`) — never for an HTTP error status. See
  /// `VaultBloc._performSync`.
  final bool isOffline;
  final List<DuplicateGroup> duplicateGroups;
  final bool isDuplicatesLoading;
  final List<AppleAutofillV2PendingAssociation>
  pendingAppleAutofillAssociations;

  /// spec-005 T3: computed on unlock and after every write (never per
  /// keystroke) — see `VaultBloc._computeHealth`.
  final VaultHealthReport healthReport;

  /// spec-005 T16: outcome of the most recent CSV import, shown once by the
  /// outcome screen then cleared via `ClearCsvImportOutcome`.
  final CsvImportOutcome? lastCsvImportOutcome;

  int get duplicateGroupCount => duplicateGroups.length;

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
    bool? driveReconnectRequired,
    DateTime? lastSyncAt,
    SyncConflict? pendingSyncConflict,
    List<DriveRemoteFile>? remoteDriveFiles,
    bool? isLoadingRemoteDriveFiles,
    String? remoteDriveFilesError,
    bool? remoteDriveFilesReconnectRequired,
    String? linkedDriveFileName,
    bool? isSyncing,
    bool? isSyncReloadPending,
    bool? isOffline,
    List<DuplicateGroup>? duplicateGroups,
    bool? isDuplicatesLoading,
    List<AppleAutofillV2PendingAssociation>? pendingAppleAutofillAssociations,
    VaultHealthReport? healthReport,
    CsvImportOutcome? lastCsvImportOutcome,
    bool clearError = false,
    bool clearInfo = false,
    bool clearSyncError = false,
    bool clearRemoteDriveFilesError = false,
    bool clearSyncConflict = false,
    bool clearSyncReloadPending = false,
    bool clearCsvImportOutcome = false,
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
      driveReconnectRequired:
          driveReconnectRequired ?? this.driveReconnectRequired,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      pendingSyncConflict: clearSyncConflict
          ? null
          : pendingSyncConflict ?? this.pendingSyncConflict,
      remoteDriveFiles: remoteDriveFiles ?? this.remoteDriveFiles,
      isLoadingRemoteDriveFiles:
          isLoadingRemoteDriveFiles ?? this.isLoadingRemoteDriveFiles,
      remoteDriveFilesError: clearRemoteDriveFilesError
          ? null
          : remoteDriveFilesError ?? this.remoteDriveFilesError,
      remoteDriveFilesReconnectRequired: clearRemoteDriveFilesError
          ? false
          : remoteDriveFilesReconnectRequired ??
                this.remoteDriveFilesReconnectRequired,
      linkedDriveFileName: linkedDriveFileName ?? this.linkedDriveFileName,
      isSyncing: isSyncing ?? this.isSyncing,
      isSyncReloadPending: clearSyncReloadPending
          ? false
          : isSyncReloadPending ?? this.isSyncReloadPending,
      isOffline: isOffline ?? this.isOffline,
      duplicateGroups: duplicateGroups ?? this.duplicateGroups,
      isDuplicatesLoading: isDuplicatesLoading ?? this.isDuplicatesLoading,
      pendingAppleAutofillAssociations:
          pendingAppleAutofillAssociations ??
          this.pendingAppleAutofillAssociations,
      healthReport: healthReport ?? this.healthReport,
      lastCsvImportOutcome: clearCsvImportOutcome
          ? null
          : lastCsvImportOutcome ?? this.lastCsvImportOutcome,
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
    driveReconnectRequired,
    lastSyncAt,
    pendingSyncConflict,
    remoteDriveFiles,
    isLoadingRemoteDriveFiles,
    remoteDriveFilesError,
    remoteDriveFilesReconnectRequired,
    linkedDriveFileName,
    isSyncing,
    isSyncReloadPending,
    isOffline,
    duplicateGroups,
    isDuplicatesLoading,
    pendingAppleAutofillAssociations,
    // Deliberately NOT `healthReport` itself (plan.md risk: "Adding
    // healthReport to VaultState triggers rebuild storms" — its
    // categories carry full entryIds lists that would make every
    // VaultState `==`/hashCode do O(entries) list comparisons). Score +
    // per-category counts are enough to detect a change worth reacting to.
    healthReport.score,
    for (final category in healthReport.categories) category.count,
    lastCsvImportOutcome,
  ];

  @override
  String toString() {
    return 'VaultState('
        'databasePath: $databasePath, '
        'rootGroupId: $rootGroupId, '
        'currentGroupId: $currentGroupId, '
        'groups: ${groups.length}, '
        'entries: ${entries.length}, '
        'allEntries: ${allEntries.length}, '
        'visibleEntries: ${visibleEntries.length}, '
        'expandedGroupIds: $expandedGroupIds, '
        'recycleBinEntries: ${recycleBinEntries.length}, '
        'isLoading: $isLoading, '
        'isSaving: $isSaving, '
        'isRecycleBinView: $isRecycleBinView, '
        'isRecycleBinLoading: $isRecycleBinLoading, '
        'searchQuery: $searchQuery, '
        'sortBy: $sortBy, '
        'errorMessage: $errorMessage, '
        'infoMessage: $infoMessage, '
        'isDriveConnected: $isDriveConnected, '
        'isDriveLinked: $isDriveLinked, '
        'autoSyncEnabled: $autoSyncEnabled, '
        'syncStatus: $syncStatus, '
        'syncError: $syncError, '
        'driveReconnectRequired: $driveReconnectRequired, '
        'lastSyncAt: $lastSyncAt, '
        'pendingSyncConflict: $pendingSyncConflict, '
        'remoteDriveFiles: ${remoteDriveFiles.length}, '
        'isLoadingRemoteDriveFiles: $isLoadingRemoteDriveFiles, '
        'remoteDriveFilesError: $remoteDriveFilesError, '
        'remoteDriveFilesReconnectRequired: '
        '$remoteDriveFilesReconnectRequired, '
        'linkedDriveFileName: $linkedDriveFileName, '
        'isSyncing: $isSyncing, '
        'isSyncReloadPending: $isSyncReloadPending, '
        'isOffline: $isOffline, '
        'duplicateGroups: ${duplicateGroups.length}, '
        'isDuplicatesLoading: $isDuplicatesLoading, '
        'pendingAppleAutofillAssociations: '
        '${pendingAppleAutofillAssociations.length}, '
        'healthReport.score: ${healthReport.score}, '
        'lastCsvImportOutcome: ${lastCsvImportOutcome != null})';
  }
}
