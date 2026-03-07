import 'package:equatable/equatable.dart';

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
    this.visibleEntries = const [],
    this.recycleBinEntries = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.isRecycleBinView = false,
    this.isRecycleBinLoading = false,
    this.searchQuery = '',
    this.sortBy = VaultEntrySort.titleAsc,
    this.errorMessage,
    this.infoMessage,
  });

  factory VaultState.initial({required String databasePath}) {
    return VaultState(databasePath: databasePath, isLoading: true);
  }

  final String databasePath;
  final String? rootGroupId;
  final String? currentGroupId;
  final List<VaultGroup> groups;
  final List<VaultEntry> entries;
  final List<VaultEntry> visibleEntries;
  final List<VaultEntry> recycleBinEntries;
  final bool isLoading;
  final bool isSaving;
  final bool isRecycleBinView;
  final bool isRecycleBinLoading;
  final String searchQuery;
  final VaultEntrySort sortBy;
  final String? errorMessage;
  final String? infoMessage;

  VaultState copyWith({
    String? rootGroupId,
    String? currentGroupId,
    List<VaultGroup>? groups,
    List<VaultEntry>? entries,
    List<VaultEntry>? visibleEntries,
    List<VaultEntry>? recycleBinEntries,
    bool? isLoading,
    bool? isSaving,
    bool? isRecycleBinView,
    bool? isRecycleBinLoading,
    String? searchQuery,
    VaultEntrySort? sortBy,
    String? errorMessage,
    String? infoMessage,
    bool clearError = false,
    bool clearInfo = false,
  }) {
    return VaultState(
      databasePath: databasePath,
      rootGroupId: rootGroupId ?? this.rootGroupId,
      currentGroupId: currentGroupId ?? this.currentGroupId,
      groups: groups ?? this.groups,
      entries: entries ?? this.entries,
      visibleEntries: visibleEntries ?? this.visibleEntries,
      recycleBinEntries: recycleBinEntries ?? this.recycleBinEntries,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isRecycleBinView: isRecycleBinView ?? this.isRecycleBinView,
      isRecycleBinLoading: isRecycleBinLoading ?? this.isRecycleBinLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      infoMessage: clearInfo ? null : infoMessage ?? this.infoMessage,
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
    visibleEntries,
    recycleBinEntries,
    isLoading,
    isSaving,
    isRecycleBinView,
    isRecycleBinLoading,
    searchQuery,
    sortBy,
    errorMessage,
    infoMessage,
  ];
}
