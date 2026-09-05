import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;

import '../../../domain/models/apple_autofill_v2_models.dart';
import '../../../domain/models/database_sync_status.dart';
import '../../../domain/models/drive_remote_file.dart';
import '../../../domain/models/duplicate_group.dart';
import '../../../domain/models/sync_conflict.dart';
import '../../../domain/models/sync_merge_models.dart';
import '../../../domain/models/vault_entry.dart';
import '../../../domain/models/vault_group.dart';
import '../../../domain/models/vault_health_report.dart';
import '../../coordinators/android_autofill_save_coordinator.dart';
import '../../../data/services/vault_csv_import_service.dart'
    show CsvImportOutcome;

enum VaultEntrySort { titleAsc, titleDesc, usernameAsc }

class VaultState extends Equatable {
  const VaultState({
    required this.databasePath,
    this.displayName,
    this.rootGroupId,
    this.currentGroupId,
    this.groups = const [],
    this.entries = const [],
    this.allEntries = const [],
    this.visibleEntries = const [],
    this.expandedGroupIds = const [],
    this.folderCounts = const {},
    this.folderDescendantIds = const {},
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
    this.lastSyncedLocalChecksum,
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
    this.pendingAndroidAutofillSave,
    this.healthReport = VaultHealthReport.empty,
    this.lastCsvImportOutcome,
    this.mergeReview,
    this.mergeCommitOutcome,
    this.mergeFailureCode,
    this.isMergeBusy = false,
  });

  factory VaultState.initial({required String databasePath}) {
    return VaultState(databasePath: databasePath, isLoading: true);
  }

  final String databasePath;

  /// spec 014 FR-3: the registry name. The database file rests under an
  /// opaque identifier on mobile, so the basename is not a name to show —
  /// it is only the fallback for storage that is not opaque (desktop).
  final String? displayName;

  /// What the UI shows for the open database.
  String get databaseLabel => displayName ?? p.basename(databasePath);

  final String? rootGroupId;
  final String? currentGroupId;
  final List<VaultGroup> groups;
  final List<VaultEntry> entries;
  final List<VaultEntry> allEntries;
  final List<VaultEntry> visibleEntries;
  final List<String> expandedGroupIds;

  /// spec-019 T007/T008 — records per folder, **inclusive of descendants**.
  ///
  /// Recomputed once per reload from `groups` and `allEntries`, never per row:
  /// the folder column asks for a count on every rebuild of every row, and a
  /// walk per row is a walk of the whole vault per row.
  ///
  /// Recycle-bin groups are absent from the map, so `All items` and the folder
  /// counts add up to the same vault.
  final Map<String, int> folderCounts;

  /// spec-019 T007 — every descendant of a folder, from the same walk that
  /// produced [folderCounts]. Read by the folder filter so that selecting a
  /// folder shows its subtree (FR-006h).
  final Map<String, Set<String>> folderDescendantIds;

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

  /// The local file's checksum recorded at the last successful sync
  /// (`DatabaseSyncMapping.lastSyncedLocalChecksum`) — surfaced so the Sync
  /// destination can show it instead of a hard-coded null.
  final String? lastSyncedLocalChecksum;
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

  /// spec-016 US3: a credential submitted to another app, waiting for the
  /// user to confirm whether it becomes a new entry or updates one. The
  /// captured password lives inside it and is never rendered.
  final AndroidAutofillPendingSave? pendingAndroidAutofillSave;

  /// spec-005 T3: computed on unlock and after every write (never per
  /// keystroke) — see `VaultBloc._computeHealth`.
  final VaultHealthReport healthReport;

  /// spec-005 T16: outcome of the most recent CSV import, shown once by the
  /// outcome screen then cleared via `ClearCsvImportOutcome`.
  final CsvImportOutcome? lastCsvImportOutcome;

  /// spec-008 T504: the redacted review in progress (opaque ids, choices,
  /// counts, phase). Null when no merge review is open.
  final MergeReviewSummary? mergeReview;

  /// The last commit outcome: counts and codes only.
  final MergeCommitOutcome? mergeCommitOutcome;

  /// The last merge failure, as a safe code.
  final MergeFailureCode? mergeFailureCode;

  final bool isMergeBusy;

  int get duplicateGroupCount => duplicateGroups.length;

  /// spec-019 FR-002a — the number `All items` carries.
  ///
  /// This is the root folder's own inclusive count, not a second tally: the
  /// row labelled `All items` IS the root group, so the two readings are the
  /// same number by construction rather than by coincidence.
  int get totalCount => folderCounts[rootGroupId] ?? 0;

  /// spec-019 FR-006h — [groupId] and everything beneath it.
  ///
  /// Returns just [groupId] for a leaf, and for an unknown id — the filter
  /// then matches only entries filed directly under it, which is the safe
  /// answer while a reload is in flight.
  Set<String> descendantIds(String groupId) => {
    groupId,
    ...?folderDescendantIds[groupId],
  };

  VaultState copyWith({
    String? displayName,
    String? rootGroupId,
    String? currentGroupId,
    List<VaultGroup>? groups,
    List<VaultEntry>? entries,
    List<VaultEntry>? allEntries,
    List<VaultEntry>? visibleEntries,
    List<String>? expandedGroupIds,
    Map<String, int>? folderCounts,
    Map<String, Set<String>>? folderDescendantIds,
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
    String? lastSyncedLocalChecksum,
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
    AndroidAutofillPendingSave? pendingAndroidAutofillSave,
    VaultHealthReport? healthReport,
    CsvImportOutcome? lastCsvImportOutcome,
    MergeReviewSummary? mergeReview,
    MergeCommitOutcome? mergeCommitOutcome,
    MergeFailureCode? mergeFailureCode,
    bool? isMergeBusy,
    bool clearError = false,
    bool clearInfo = false,
    bool clearSyncError = false,
    bool clearRemoteDriveFilesError = false,
    bool clearSyncConflict = false,
    bool clearSyncReloadPending = false,
    bool clearCsvImportOutcome = false,
    bool clearPendingAndroidAutofillSave = false,
    bool clearMergeReview = false,
    bool clearMergeCommitOutcome = false,
    bool clearMergeFailureCode = false,
  }) {
    return VaultState(
      databasePath: databasePath,
      displayName: displayName ?? this.displayName,
      rootGroupId: rootGroupId ?? this.rootGroupId,
      currentGroupId: currentGroupId ?? this.currentGroupId,
      groups: groups ?? this.groups,
      entries: entries ?? this.entries,
      allEntries: allEntries ?? this.allEntries,
      visibleEntries: visibleEntries ?? this.visibleEntries,
      expandedGroupIds: expandedGroupIds ?? this.expandedGroupIds,
      folderCounts: folderCounts ?? this.folderCounts,
      folderDescendantIds: folderDescendantIds ?? this.folderDescendantIds,
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
      lastSyncedLocalChecksum:
          lastSyncedLocalChecksum ?? this.lastSyncedLocalChecksum,
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
      pendingAndroidAutofillSave: clearPendingAndroidAutofillSave
          ? null
          : pendingAndroidAutofillSave ?? this.pendingAndroidAutofillSave,
      healthReport: healthReport ?? this.healthReport,
      lastCsvImportOutcome: clearCsvImportOutcome
          ? null
          : lastCsvImportOutcome ?? this.lastCsvImportOutcome,
      mergeReview: clearMergeReview ? null : mergeReview ?? this.mergeReview,
      mergeCommitOutcome: clearMergeCommitOutcome
          ? null
          : mergeCommitOutcome ?? this.mergeCommitOutcome,
      mergeFailureCode: clearMergeFailureCode
          ? null
          : mergeFailureCode ?? this.mergeFailureCode,
      isMergeBusy: isMergeBusy ?? this.isMergeBusy,
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
    displayName,
    rootGroupId,
    currentGroupId,
    groups,
    entries,
    allEntries,
    visibleEntries,
    expandedGroupIds,
    folderCounts,
    folderDescendantIds,
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
    lastSyncedLocalChecksum,
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
    pendingAndroidAutofillSave,
    // Deliberately NOT `healthReport` itself (plan.md risk: "Adding
    // healthReport to VaultState triggers rebuild storms" — its
    // categories carry full entryIds lists that would make every
    // VaultState `==`/hashCode do O(entries) list comparisons). Score +
    // per-category counts are enough to detect a change worth reacting to.
    healthReport.score,
    for (final category in healthReport.categories) category.count,
    lastCsvImportOutcome,
    mergeReview,
    mergeCommitOutcome,
    mergeFailureCode,
    isMergeBusy,
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
        'pendingAndroidAutofillSave: '
        '${pendingAndroidAutofillSave != null}, '
        'healthReport.score: ${healthReport.score}, '
        'lastCsvImportOutcome: ${lastCsvImportOutcome != null}, '
        'mergeReview: ${mergeReview?.phase}, '
        'mergeCommitOutcome: ${mergeCommitOutcome?.runtimeType}, '
        'mergeFailureCode: $mergeFailureCode, '
        'isMergeBusy: $isMergeBusy)';
  }
}
