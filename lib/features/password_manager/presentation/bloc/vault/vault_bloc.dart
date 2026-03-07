import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loggy/loggy.dart';
import 'package:stream_transform/stream_transform.dart';

import '../../../data/datasources/secure_data_source.dart';
import '../../../data/services/vault_kdbx_service.dart';
import '../../../domain/models/vault_entry.dart';
import '../../../domain/models/vault_snapshot.dart';
import '../../../domain/usecases/get_selected_key_file_path_usecase.dart';
import 'vault_event.dart';
import 'vault_state.dart';

class VaultBloc extends Bloc<VaultEvent, VaultState> {
  VaultBloc({
    required String databasePath,
    required this.secureDataSource,
    required this.getSelectedKeyFilePathUseCase,
    required this.vaultKdbxService,
  }) : super(VaultState.initial(databasePath: databasePath)) {
    on<InitializeVault>(_onInitializeVault);
    on<RefreshVault>(_onRefreshVault);
    on<UpdateVaultSearchQuery>(
      _onUpdateVaultSearchQuery,
      transformer: (events, mapper) => events
          .debounce(const Duration(milliseconds: 300))
          .distinct((previous, next) => previous.query == next.query)
          .switchMap(mapper),
    );
    on<ClearVaultSearchQuery>(_onClearVaultSearchQuery);
    on<SetVaultSort>(_onSetVaultSort);
    on<LoadRecycleBinEntries>(_onLoadRecycleBinEntries);
    on<OpenGroup>(_onOpenGroup);
    on<OpenParentGroup>(_onOpenParentGroup);
    on<CreateVaultEntry>(_onCreateVaultEntry);
    on<UpdateVaultEntry>(_onUpdateVaultEntry);
    on<DeleteVaultEntry>(_onDeleteVaultEntry);
    on<MoveVaultEntry>(_onMoveVaultEntry);
    on<CreateVaultGroup>(_onCreateVaultGroup);
    on<RenameVaultGroup>(_onRenameVaultGroup);
    on<DeleteVaultGroup>(_onDeleteVaultGroup);
    on<MoveVaultGroup>(_onMoveVaultGroup);
    on<OpenRecycleBin>(_onOpenRecycleBin);
    on<CloseRecycleBin>(_onCloseRecycleBin);
    on<RestoreVaultEntry>(_onRestoreVaultEntry);
    on<RestoreVaultGroup>(_onRestoreVaultGroup);
    on<DeleteVaultEntryPermanently>(_onDeleteVaultEntryPermanently);
    on<DeleteVaultGroupPermanently>(_onDeleteVaultGroupPermanently);
    on<EmptyRecycleBin>(_onEmptyRecycleBin);
    on<ClearVaultError>(_onClearVaultError);
    on<AddVaultAttachment>(_onAddVaultAttachment);
    on<RemoveVaultAttachment>(_onRemoveVaultAttachment);
    on<ExportVaultAttachment>(_onExportVaultAttachment);
    on<ClearVaultInfo>(_onClearVaultInfo);
  }

  final SecureDataSource secureDataSource;
  final GetSelectedKeyFilePathUseCase getSelectedKeyFilePathUseCase;
  final VaultKdbxService vaultKdbxService;

  String _password = '';
  String? _keyFilePath;
  String? _lastRegularGroupId;

  Future<void> _onInitializeVault(
    InitializeVault event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      _password = await secureDataSource.getMasterPassword() ?? '';
      _keyFilePath = await getSelectedKeyFilePathUseCase();
      await _reload(emit);
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed to initialize vault.', e, st);
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Unable to load vault credentials.',
        ),
      );
    }
  }

  Future<void> _onRefreshVault(
    RefreshVault event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    await _reload(
      emit,
      currentGroupId: state.currentGroupId,
      keepLoadingFlag: false,
    );
    await _loadRecycleBinEntries(emit, isInitialLoad: true);
  }

  Future<void> _onOpenRecycleBin(
    OpenRecycleBin event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      if (!state.isRecycleBinView) {
        _lastRegularGroupId = state.currentGroupId ?? state.rootGroupId;
      }

      final recycleBinGroupId = await vaultKdbxService.getRecycleBinGroupId(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
      );

      if (recycleBinGroupId == null) {
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage: 'Recycle bin is empty and not created yet.',
          ),
        );
        return;
      }

      await _reload(
        emit,
        currentGroupId: recycleBinGroupId,
        keepLoadingFlag: false,
      );
      emit(state.copyWith(isRecycleBinView: true, clearError: true));
    } catch (e, st) {
      logError('Failed opening recycle bin.', e, st);
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Unable to open recycle bin.',
        ),
      );
    }
  }

  void _onUpdateVaultSearchQuery(
    UpdateVaultSearchQuery event,
    Emitter<VaultState> emit,
  ) {
    final query = event.query;
    emit(
      state.copyWith(
        searchQuery: query,
        visibleEntries: _computeVisibleEntries(
          entries: state.entries,
          searchQuery: query,
          sortBy: state.sortBy,
        ),
      ),
    );
  }

  void _onClearVaultSearchQuery(
    ClearVaultSearchQuery event,
    Emitter<VaultState> emit,
  ) {
    emit(
      state.copyWith(
        searchQuery: '',
        visibleEntries: _computeVisibleEntries(
          entries: state.entries,
          searchQuery: '',
          sortBy: state.sortBy,
        ),
      ),
    );
  }

  void _onSetVaultSort(SetVaultSort event, Emitter<VaultState> emit) {
    emit(
      state.copyWith(
        sortBy: event.sortBy,
        visibleEntries: _computeVisibleEntries(
          entries: state.entries,
          searchQuery: state.searchQuery,
          sortBy: event.sortBy,
        ),
      ),
    );
  }

  Future<void> _onLoadRecycleBinEntries(
    LoadRecycleBinEntries event,
    Emitter<VaultState> emit,
  ) async {
    await _loadRecycleBinEntries(emit);
  }

  Future<void> _onCloseRecycleBin(
    CloseRecycleBin event,
    Emitter<VaultState> emit,
  ) async {
    final fallback = _lastRegularGroupId ?? state.rootGroupId;
    emit(state.copyWith(isLoading: true, clearError: true));
    await _reload(emit, currentGroupId: fallback, keepLoadingFlag: false);
    emit(state.copyWith(isRecycleBinView: false, clearError: true));
  }

  Future<void> _onOpenGroup(OpenGroup event, Emitter<VaultState> emit) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    await _reload(emit, currentGroupId: event.groupId);
  }

  Future<void> _onOpenParentGroup(
    OpenParentGroup event,
    Emitter<VaultState> emit,
  ) async {
    final current = state.currentGroup;
    if (current?.parentId == null) {
      return;
    }

    emit(state.copyWith(isLoading: true, clearError: true));
    await _reload(emit, currentGroupId: current!.parentId);
  }

  Future<void> _onCreateVaultEntry(
    CreateVaultEntry event,
    Emitter<VaultState> emit,
  ) async {
    final currentGroupId = state.currentGroupId;
    if (currentGroupId == null) {
      return;
    }

    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.createEntry(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        groupId: currentGroupId,
        title: event.title,
        username: event.username,
        entryPassword: event.password,
        url: event.url,
        notes: event.notes,
        customFields: event.customFields,
      );
      await _reload(
        emit,
        currentGroupId: currentGroupId,
        keepLoadingFlag: false,
      );
    } catch (e, st) {
      logError('Failed creating vault entry.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to create entry.',
        ),
      );
    }
  }

  Future<void> _onUpdateVaultEntry(
    UpdateVaultEntry event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.updateEntry(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
        title: event.title,
        username: event.username,
        entryPassword: event.password,
        url: event.url,
        notes: event.notes,
        customFields: event.customFields,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed updating vault entry.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to update entry.',
        ),
      );
    }
  }

  Future<void> _onDeleteVaultEntry(
    DeleteVaultEntry event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.deleteEntry(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed deleting vault entry.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to delete entry.',
        ),
      );
    }
  }

  Future<void> _onMoveVaultEntry(
    MoveVaultEntry event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.moveEntry(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
        targetGroupId: event.targetGroupId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
    } catch (e, st) {
      logError('Failed moving vault entry.', e, st);
      emit(
        state.copyWith(isSaving: false, errorMessage: 'Unable to move entry.'),
      );
    }
  }

  Future<void> _onCreateVaultGroup(
    CreateVaultGroup event,
    Emitter<VaultState> emit,
  ) async {
    final parentGroupId = state.currentGroupId;
    if (parentGroupId == null) {
      return;
    }

    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.createGroup(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        parentGroupId: parentGroupId,
        name: event.name,
      );
      await _reload(
        emit,
        currentGroupId: parentGroupId,
        keepLoadingFlag: false,
      );
    } catch (e, st) {
      logError('Failed creating vault group.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to create group.',
        ),
      );
    }
  }

  Future<void> _onRenameVaultGroup(
    RenameVaultGroup event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.renameGroup(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        groupId: event.groupId,
        newName: event.newName,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
    } catch (e, st) {
      logError('Failed renaming vault group.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to rename group.',
        ),
      );
    }
  }

  Future<void> _onDeleteVaultGroup(
    DeleteVaultGroup event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      final deletedGroup = state.groups
          .where((group) => group.id == event.groupId)
          .firstOrNull;

      final isGroupEmpty = await vaultKdbxService.isGroupEmpty(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        groupId: event.groupId,
      );

      if (!isGroupEmpty) {
        emit(
          state.copyWith(
            isSaving: false,
            errorMessage: 'Unable to delete: folder is not empty.',
          ),
        );
        return;
      }

      await vaultKdbxService.deleteGroup(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        groupId: event.groupId,
        permanently: true,
      );

      final fallbackGroupId = state.currentGroupId == event.groupId
          ? deletedGroup?.parentId ?? state.rootGroupId
          : state.currentGroupId;

      await _reload(
        emit,
        currentGroupId: fallbackGroupId,
        keepLoadingFlag: false,
      );
    } catch (e, st) {
      logError('Failed deleting vault group.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to delete group.',
        ),
      );
    }
  }

  Future<void> _onMoveVaultGroup(
    MoveVaultGroup event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.moveGroup(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        groupId: event.groupId,
        targetGroupId: event.targetGroupId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed moving vault group.', e, st);
      emit(
        state.copyWith(isSaving: false, errorMessage: 'Unable to move group.'),
      );
    }
  }

  Future<void> _onRestoreVaultEntry(
    RestoreVaultEntry event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.restoreEntryFromRecycleBin(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed restoring vault entry from recycle bin.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to restore record.',
        ),
      );
    }
  }

  Future<void> _onRestoreVaultGroup(
    RestoreVaultGroup event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.restoreGroupFromRecycleBin(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        groupId: event.groupId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed restoring vault group from recycle bin.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to restore folder.',
        ),
      );
    }
  }

  Future<void> _onDeleteVaultEntryPermanently(
    DeleteVaultEntryPermanently event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.deleteEntryPermanently(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed permanently deleting vault entry.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to permanently delete record.',
        ),
      );
    }
  }

  Future<void> _onDeleteVaultGroupPermanently(
    DeleteVaultGroupPermanently event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.deleteGroupPermanently(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        groupId: event.groupId,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed permanently deleting vault group.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to permanently delete folder.',
        ),
      );
    }
  }

  Future<void> _onEmptyRecycleBin(
    EmptyRecycleBin event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await vaultKdbxService.emptyRecycleBin(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed emptying recycle bin.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to empty recycle bin.',
        ),
      );
    }
  }

  Future<void> _reload(
    Emitter<VaultState> emit, {
    String? currentGroupId,
    bool keepLoadingFlag = true,
  }) async {
    try {
      final VaultSnapshot snapshot = await vaultKdbxService.loadVault(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        currentGroupId: currentGroupId ?? state.currentGroupId,
      );

      emit(
        state.copyWith(
          isLoading: false,
          isSaving: false,
          rootGroupId: snapshot.rootGroupId,
          currentGroupId: snapshot.currentGroupId,
          groups: snapshot.groups,
          entries: snapshot.entries,
          visibleEntries: _computeVisibleEntries(
            entries: snapshot.entries,
            searchQuery: state.searchQuery,
            sortBy: state.sortBy,
          ),
          clearError: true,
          clearInfo: true,
        ),
      );
    } catch (e, st) {
      logError('Failed loading vault data.', e, st);
      emit(
        state.copyWith(
          isLoading: false,
          isSaving: false,
          errorMessage: 'Unable to load vault content.',
        ),
      );
    }

    if (!keepLoadingFlag && state.isLoading) {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _loadRecycleBinEntries(
    Emitter<VaultState> emit, {
    bool isInitialLoad = false,
  }) async {
    if (!isInitialLoad) {
      emit(state.copyWith(isRecycleBinLoading: true, clearError: true));
    }

    try {
      final recycleBinEntries = await vaultKdbxService.loadRecycleBinEntries(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
      );
      emit(
        state.copyWith(
          recycleBinEntries: recycleBinEntries,
          isRecycleBinLoading: false,
          clearError: true,
        ),
      );
    } catch (e, st) {
      logError('Failed loading recycle bin entries.', e, st);
      emit(
        state.copyWith(
          isRecycleBinLoading: false,
          errorMessage: 'Unable to load recycle bin.',
        ),
      );
    }
  }

  void _onClearVaultError(ClearVaultError event, Emitter<VaultState> emit) {
    emit(state.copyWith(clearError: true));
  }

  Future<void> _onAddVaultAttachment(
    AddVaultAttachment event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true, clearInfo: true));
    try {
      await vaultKdbxService.addAttachment(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
        filePath: event.filePath,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      emit(state.copyWith(infoMessage: 'Attachment added.'));
    } catch (e, st) {
      logError('Failed adding attachment.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to add attachment. $e',
        ),
      );
    }
  }

  Future<void> _onRemoveVaultAttachment(
    RemoveVaultAttachment event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true, clearInfo: true));
    try {
      await vaultKdbxService.removeAttachment(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
        attachmentKey: event.attachmentKey,
      );
      await _reload(
        emit,
        currentGroupId: state.currentGroupId,
        keepLoadingFlag: false,
      );
      emit(state.copyWith(infoMessage: 'Attachment removed.'));
    } catch (e, st) {
      logError('Failed removing attachment.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to remove attachment.',
        ),
      );
    }
  }

  Future<void> _onExportVaultAttachment(
    ExportVaultAttachment event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true, clearInfo: true));
    try {
      final exportedPath = await vaultKdbxService.exportAttachment(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
        attachmentKey: event.attachmentKey,
        destinationDirectory: event.destinationDirectory,
      );

      emit(
        state.copyWith(
          isSaving: false,
          infoMessage: 'Attachment exported: $exportedPath',
        ),
      );
    } catch (e, st) {
      logError('Failed exporting attachment.', e, st);
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to export attachment.',
        ),
      );
    }
  }

  void _onClearVaultInfo(ClearVaultInfo event, Emitter<VaultState> emit) {
    emit(state.copyWith(clearInfo: true));
  }

  List<VaultEntry> _computeVisibleEntries({
    required List<VaultEntry> entries,
    required String searchQuery,
    required VaultEntrySort sortBy,
  }) {
    final normalizedQuery = searchQuery.trim().toLowerCase();

    var filtered = entries
        .where((entry) {
          if (normalizedQuery.isNotEmpty) {
            final inTitle = entry.title.toLowerCase().contains(normalizedQuery);
            final inUser = entry.username.toLowerCase().contains(
              normalizedQuery,
            );
            final inUrl = entry.url.toLowerCase().contains(normalizedQuery);
            final inNotes = entry.notes.toLowerCase().contains(normalizedQuery);
            final inCustom = entry.customFields.any(
              (field) =>
                  field.key.toLowerCase().contains(normalizedQuery) ||
                  field.value.toLowerCase().contains(normalizedQuery),
            );
            if (!(inTitle || inUser || inUrl || inNotes || inCustom)) {
              return false;
            }
          }

          return true;
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      switch (sortBy) {
        case VaultEntrySort.titleAsc:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case VaultEntrySort.titleDesc:
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case VaultEntrySort.usernameAsc:
          return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      }
    });

    return filtered;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }
}
