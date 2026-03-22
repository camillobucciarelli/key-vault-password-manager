import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loggy/loggy.dart';
import 'package:stream_transform/stream_transform.dart';

import '../../../data/datasources/secure_data_source.dart';
import '../../../data/services/vault_csv_import_service.dart';
import '../../../data/services/vault_kdbx_service.dart';
import '../../../domain/models/database_sync_status.dart';
import '../../../domain/models/sync_conflict.dart';
import '../../../domain/repositories/database_sync_repository.dart';
import '../../../domain/usecases/connect_google_account_usecase.dart';
import '../../../domain/usecases/disconnect_google_account_usecase.dart';
import '../../../domain/usecases/get_drive_connection_status_usecase.dart';
import '../../../domain/models/vault_entry.dart';
import '../../../domain/models/vault_group.dart';
import '../../../domain/models/vault_snapshot.dart';
import '../../../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../../../domain/usecases/link_database_to_drive_usecase.dart';
import '../../../domain/usecases/list_drive_remote_files_usecase.dart';
import '../../../domain/usecases/set_database_auto_sync_usecase.dart';
import '../../../domain/usecases/sync_database_now_usecase.dart';
import 'vault_event.dart';
import 'vault_state.dart';

class VaultBloc extends Bloc<VaultEvent, VaultState> {
  VaultBloc({
    required String databasePath,
    required this.secureDataSource,
    required this.getSelectedKeyFilePathUseCase,
    required this.vaultKdbxService,
    required this.vaultCsvImportService,
    required this.getDriveConnectionStatusUseCase,
    required this.connectGoogleAccountUseCase,
    required this.disconnectGoogleAccountUseCase,
    required this.linkDatabaseToDriveUseCase,
    required this.listDriveRemoteFilesUseCase,
    required this.syncDatabaseNowUseCase,
    required this.setDatabaseAutoSyncUseCase,
    required this.databaseSyncRepository,
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
    on<ToggleVaultGroupExpanded>(_onToggleVaultGroupExpanded);
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
    on<ImportVaultEntriesFromCsv>(_onImportVaultEntriesFromCsv);
    on<ClearVaultInfo>(_onClearVaultInfo);
    on<ConnectGoogleDrive>(_onConnectGoogleDrive);
    on<DisconnectGoogleDrive>(_onDisconnectGoogleDrive);
    on<LinkCurrentDatabaseToDrive>(_onLinkCurrentDatabaseToDrive);
    on<SyncCurrentDatabaseNow>(_onSyncCurrentDatabaseNow);
    on<ToggleCurrentDatabaseAutoSync>(_onToggleCurrentDatabaseAutoSync);
    on<ClearVaultSyncFeedback>(_onClearVaultSyncFeedback);
    on<LoadDriveRemoteFiles>(
      _onLoadDriveRemoteFiles,
      transformer: (events, mapper) => events
          .debounce(const Duration(milliseconds: 300))
          .distinct(
            (previous, next) => previous.query?.trim() == next.query?.trim(),
          )
          .switchMap(mapper),
    );
  }

  final SecureDataSource secureDataSource;
  final GetSelectedKeyFilePathUseCase getSelectedKeyFilePathUseCase;
  final VaultKdbxService vaultKdbxService;
  final VaultCsvImportService vaultCsvImportService;
  final GetDriveConnectionStatusUseCase getDriveConnectionStatusUseCase;
  final ConnectGoogleAccountUseCase connectGoogleAccountUseCase;
  final DisconnectGoogleAccountUseCase disconnectGoogleAccountUseCase;
  final LinkDatabaseToDriveUseCase linkDatabaseToDriveUseCase;
  final ListDriveRemoteFilesUseCase listDriveRemoteFilesUseCase;
  final SyncDatabaseNowUseCase syncDatabaseNowUseCase;
  final SetDatabaseAutoSyncUseCase setDatabaseAutoSyncUseCase;
  final DatabaseSyncRepository databaseSyncRepository;

  String _password = '';
  String? _keyFilePath;
  String? _lastRegularGroupId;
  Timer? _autoSyncDebounce;

  Future<void> _onInitializeVault(
    InitializeVault event,
    Emitter<VaultState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
    try {
      _password = await secureDataSource.getMasterPassword() ?? '';
      _keyFilePath = await getSelectedKeyFilePathUseCase();
      await _refreshSyncState(emit);
      if (state.isDriveConnected && state.isDriveLinked) {
        await _performSync(emit, silentIfConflict: true);
      }
      await _reload(emit);
      await _loadRecycleBinEntries(emit, isInitialLoad: true);
    } catch (e, st) {
      logError('Failed to initialize vault.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
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
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
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
        _safeEmit(
          emit,
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
      _safeEmit(emit, state.copyWith(isRecycleBinView: true, clearError: true));
    } catch (e, st) {
      logError('Failed opening recycle bin.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(
      emit,
      state.copyWith(
        searchQuery: query,
        visibleEntries: _computeVisibleEntries(
          entries: state.allEntries,
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
    _safeEmit(
      emit,
      state.copyWith(
        searchQuery: '',
        visibleEntries: _computeVisibleEntries(
          entries: state.allEntries,
          searchQuery: '',
          sortBy: state.sortBy,
        ),
      ),
    );
  }

  void _onSetVaultSort(SetVaultSort event, Emitter<VaultState> emit) {
    _safeEmit(
      emit,
      state.copyWith(
        sortBy: event.sortBy,
        visibleEntries: _computeVisibleEntries(
          entries: state.allEntries,
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
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
    await _reload(emit, currentGroupId: fallback, keepLoadingFlag: false);
    _safeEmit(emit, state.copyWith(isRecycleBinView: false, clearError: true));
  }

  Future<void> _onOpenGroup(OpenGroup event, Emitter<VaultState> emit) async {
    final normalizedExpanded = _normalizeExpandedGroupIds(
      groups: state.groups,
      rootGroupId: state.rootGroupId ?? '',
      currentGroupId: event.groupId,
      previousExpanded: state.expandedGroupIds,
    );

    _safeEmit(
      emit,
      state.copyWith(
        currentGroupId: event.groupId,
        expandedGroupIds: normalizedExpanded,
        visibleEntries: _computeVisibleEntries(
          entries: state.allEntries,
          searchQuery: state.searchQuery,
          sortBy: state.sortBy,
        ),
        clearError: true,
      ),
    );
  }

  Future<void> _onOpenParentGroup(
    OpenParentGroup event,
    Emitter<VaultState> emit,
  ) async {
    final current = state.currentGroup;
    if (current?.parentId == null) {
      return;
    }

    final normalizedExpanded = _normalizeExpandedGroupIds(
      groups: state.groups,
      rootGroupId: state.rootGroupId ?? '',
      currentGroupId: current!.parentId!,
      previousExpanded: state.expandedGroupIds,
    );

    _safeEmit(
      emit,
      state.copyWith(
        currentGroupId: current.parentId,
        expandedGroupIds: normalizedExpanded,
        visibleEntries: _computeVisibleEntries(
          entries: state.allEntries,
          searchQuery: state.searchQuery,
          sortBy: state.sortBy,
        ),
        clearError: true,
      ),
    );
  }

  void _onToggleVaultGroupExpanded(
    ToggleVaultGroupExpanded event,
    Emitter<VaultState> emit,
  ) {
    final existingIds = state.groups.map((group) => group.id).toSet();
    if (!existingIds.contains(event.groupId)) {
      return;
    }

    final expanded = state.expandedGroupIds.toSet();
    if (!expanded.add(event.groupId)) {
      expanded.remove(event.groupId);
    }

    _safeEmit(
      emit,
      state.copyWith(expandedGroupIds: expanded.toList()..sort()),
    );
  }

  Future<void> _onCreateVaultEntry(
    CreateVaultEntry event,
    Emitter<VaultState> emit,
  ) async {
    final currentGroupId = state.currentGroupId;
    if (currentGroupId == null) {
      return;
    }

    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
    try {
      final createdEntryId = await vaultKdbxService.createEntry(
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
      for (final attachmentPath in event.attachmentPaths) {
        await vaultKdbxService.addAttachment(
          databasePath: state.databasePath,
          password: _password,
          keyFilePath: _keyFilePath,
          entryId: createdEntryId,
          filePath: attachmentPath,
        );
      }
      await _reload(
        emit,
        currentGroupId: currentGroupId,
        keepLoadingFlag: false,
      );
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed creating vault entry.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed updating vault entry.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed deleting vault entry.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed moving vault entry.', e, st);
      _safeEmit(
        emit,
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

    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed creating vault group.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed renaming vault group.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
        _safeEmit(
          emit,
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed deleting vault group.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed moving vault group.', e, st);
      _safeEmit(
        emit,
        state.copyWith(isSaving: false, errorMessage: 'Unable to move group.'),
      );
    }
  }

  Future<void> _onRestoreVaultEntry(
    RestoreVaultEntry event,
    Emitter<VaultState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed restoring vault entry from recycle bin.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed restoring vault group from recycle bin.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed permanently deleting vault entry.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed permanently deleting vault group.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(emit, state.copyWith(isSaving: true, clearError: true));
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
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed emptying recycle bin.', e, st);
      _safeEmit(
        emit,
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

      final normalizedExpanded = _normalizeExpandedGroupIds(
        groups: snapshot.groups,
        rootGroupId: snapshot.rootGroupId,
        currentGroupId: snapshot.currentGroupId,
        previousExpanded: state.expandedGroupIds,
      );

      _safeEmit(
        emit,
        state.copyWith(
          isLoading: false,
          isSaving: false,
          rootGroupId: snapshot.rootGroupId,
          currentGroupId: snapshot.currentGroupId,
          groups: snapshot.groups,
          entries: snapshot.entries,
          allEntries: snapshot.allEntries,
          visibleEntries: _computeVisibleEntries(
            entries: snapshot.allEntries,
            searchQuery: state.searchQuery,
            sortBy: state.sortBy,
          ),
          expandedGroupIds: normalizedExpanded,
          clearError: true,
          clearInfo: true,
        ),
      );
    } catch (e, st) {
      logError('Failed loading vault data.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          isLoading: false,
          isSaving: false,
          errorMessage: 'Unable to load vault content.',
        ),
      );
    }

    if (!keepLoadingFlag && state.isLoading) {
      _safeEmit(emit, state.copyWith(isLoading: false));
    }
  }

  Future<void> _loadRecycleBinEntries(
    Emitter<VaultState> emit, {
    bool isInitialLoad = false,
  }) async {
    if (!isInitialLoad) {
      _safeEmit(
        emit,
        state.copyWith(isRecycleBinLoading: true, clearError: true),
      );
    }

    try {
      final recycleBinEntries = await vaultKdbxService.loadRecycleBinEntries(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
      );
      _safeEmit(
        emit,
        state.copyWith(
          recycleBinEntries: recycleBinEntries,
          isRecycleBinLoading: false,
          clearError: true,
        ),
      );
    } catch (e, st) {
      logError('Failed loading recycle bin entries.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          isRecycleBinLoading: false,
          errorMessage: 'Unable to load recycle bin.',
        ),
      );
    }
  }

  void _onClearVaultError(ClearVaultError event, Emitter<VaultState> emit) {
    _safeEmit(emit, state.copyWith(clearError: true));
  }

  Future<void> _onAddVaultAttachment(
    AddVaultAttachment event,
    Emitter<VaultState> emit,
  ) async {
    _safeEmit(
      emit,
      state.copyWith(isSaving: true, clearError: true, clearInfo: true),
    );
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
      _safeEmit(emit, state.copyWith(infoMessage: 'Attachment added.'));
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed adding attachment.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(
      emit,
      state.copyWith(isSaving: true, clearError: true, clearInfo: true),
    );
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
      _safeEmit(emit, state.copyWith(infoMessage: 'Attachment removed.'));
      await _scheduleAutoSync(emit);
    } catch (e, st) {
      logError('Failed removing attachment.', e, st);
      _safeEmit(
        emit,
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
    _safeEmit(
      emit,
      state.copyWith(isSaving: true, clearError: true, clearInfo: true),
    );
    try {
      final exportedPath = await vaultKdbxService.exportAttachment(
        databasePath: state.databasePath,
        password: _password,
        keyFilePath: _keyFilePath,
        entryId: event.entryId,
        attachmentKey: event.attachmentKey,
        destinationDirectory: event.destinationDirectory,
      );

      _safeEmit(
        emit,
        state.copyWith(
          isSaving: false,
          infoMessage: 'Attachment exported: $exportedPath',
        ),
      );
    } catch (e, st) {
      logError('Failed exporting attachment.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to export attachment.',
        ),
      );
    }
  }

  Future<void> _onImportVaultEntriesFromCsv(
    ImportVaultEntriesFromCsv event,
    Emitter<VaultState> emit,
  ) async {
    final targetGroupId = state.currentGroupId;
    if (targetGroupId == null) {
      _safeEmit(
        emit,
        state.copyWith(
          errorMessage: 'Unable to import: no target folder selected.',
        ),
      );
      return;
    }

    _safeEmit(
      emit,
      state.copyWith(isSaving: true, clearError: true, clearInfo: true),
    );

    try {
      final parsed = await vaultCsvImportService.parseFile(event.filePath);
      if (parsed.items.isEmpty) {
        _safeEmit(
          emit,
          state.copyWith(
            isSaving: false,
            errorMessage: 'No valid records found in CSV.',
          ),
        );
        return;
      }

      var importedCount = 0;
      var failedCount = 0;
      var duplicateCount = 0;
      final existingEntryKeys = event.avoidDuplicates
          ? _buildDuplicateKeys(state.allEntries)
          : <String>{};
      for (final item in parsed.items) {
        final duplicateKey = _entryDuplicateKey(
          title: item.title,
          username: item.username,
          url: item.url,
        );
        if (event.avoidDuplicates && existingEntryKeys.contains(duplicateKey)) {
          duplicateCount += 1;
          continue;
        }

        try {
          await vaultKdbxService.createEntry(
            databasePath: state.databasePath,
            password: _password,
            keyFilePath: _keyFilePath,
            groupId: targetGroupId,
            title: item.title,
            username: item.username,
            entryPassword: item.password,
            url: item.url,
            notes: item.notes,
            customFields: item.customFields,
          );
          if (event.avoidDuplicates) {
            existingEntryKeys.add(duplicateKey);
          }
          importedCount += 1;
        } catch (_) {
          failedCount += 1;
        }
      }

      await _reload(
        emit,
        currentGroupId: targetGroupId,
        keepLoadingFlag: false,
      );
      await _scheduleAutoSync(emit);

      final skippedTotal = parsed.skippedRows + failedCount + duplicateCount;
      _safeEmit(
        emit,
        state.copyWith(
          isSaving: false,
          infoMessage: _buildCsvImportMessage(
            importedCount: importedCount,
            skippedTotal: skippedTotal,
            duplicateCount: duplicateCount,
          ),
        ),
      );
    } catch (e, st) {
      logError('Failed importing CSV entries.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          isSaving: false,
          errorMessage: 'Unable to import CSV file.',
        ),
      );
    }
  }

  void _onClearVaultInfo(ClearVaultInfo event, Emitter<VaultState> emit) {
    _safeEmit(emit, state.copyWith(clearInfo: true));
  }

  Future<void> _onConnectGoogleDrive(
    ConnectGoogleDrive event,
    Emitter<VaultState> emit,
  ) async {
    _safeEmit(
      emit,
      state.copyWith(
        syncStatus: DatabaseSyncStatus.syncing,
        clearSyncError: true,
      ),
    );
    try {
      await connectGoogleAccountUseCase();
      await _refreshSyncState(emit);
      _safeEmit(
        emit,
        state.copyWith(
          syncStatus: DatabaseSyncStatus.success,
          infoMessage: 'Google Drive connected.',
        ),
      );
    } catch (e, st) {
      logError('Google Drive connect failed.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          syncStatus: DatabaseSyncStatus.error,
          syncError: _buildDriveConnectErrorMessage(e),
        ),
      );
    }
  }

  Future<void> _onDisconnectGoogleDrive(
    DisconnectGoogleDrive event,
    Emitter<VaultState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(syncStatus: DatabaseSyncStatus.syncing));
    try {
      await disconnectGoogleAccountUseCase();
      _safeEmit(
        emit,
        state.copyWith(
          isDriveConnected: false,
          isDriveLinked: false,
          linkedDriveFileName: null,
          syncStatus: DatabaseSyncStatus.disconnected,
          infoMessage: 'Google Drive disconnected.',
          clearSyncError: true,
          clearSyncConflict: true,
        ),
      );
    } catch (e, st) {
      logError('Google Drive disconnect failed.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          syncStatus: DatabaseSyncStatus.error,
          syncError: 'Unable to disconnect Google Drive.',
        ),
      );
    }
  }

  Future<void> _onLinkCurrentDatabaseToDrive(
    LinkCurrentDatabaseToDrive event,
    Emitter<VaultState> emit,
  ) async {
    if (!state.isDriveConnected) {
      _safeEmit(
        emit,
        state.copyWith(
          syncStatus: DatabaseSyncStatus.error,
          syncError: 'Connect Google Drive first.',
        ),
      );
      return;
    }

    _safeEmit(
      emit,
      state.copyWith(
        syncStatus: DatabaseSyncStatus.syncing,
        clearSyncError: true,
      ),
    );
    try {
      final mapping = await linkDatabaseToDriveUseCase(
        databasePath: state.databasePath,
        remoteFileId: event.remoteFileId,
        remoteFileName: event.remoteFileName,
      );
      _safeEmit(
        emit,
        state.copyWith(
          isDriveLinked: true,
          linkedDriveFileName: mapping.driveFileName,
          autoSyncEnabled: mapping.autoSyncEnabled,
          lastSyncAt: mapping.lastSyncAt,
          syncStatus: DatabaseSyncStatus.success,
          infoMessage: 'Database linked to ${mapping.driveFileName}.',
        ),
      );
    } catch (e, st) {
      logError('Link database to Drive failed.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          syncStatus: DatabaseSyncStatus.error,
          syncError: 'Unable to link current database.',
        ),
      );
    }
  }

  Future<void> _onSyncCurrentDatabaseNow(
    SyncCurrentDatabaseNow event,
    Emitter<VaultState> emit,
  ) async {
    await _performSync(emit, resolution: event.resolution);
    await _reload(
      emit,
      currentGroupId: state.currentGroupId,
      keepLoadingFlag: false,
    );
  }

  Future<void> _onToggleCurrentDatabaseAutoSync(
    ToggleCurrentDatabaseAutoSync event,
    Emitter<VaultState> emit,
  ) async {
    try {
      await setDatabaseAutoSyncUseCase(state.databasePath, event.enabled);
      _safeEmit(
        emit,
        state.copyWith(
          autoSyncEnabled: event.enabled,
          infoMessage: event.enabled
              ? 'Auto-sync enabled.'
              : 'Auto-sync disabled.',
        ),
      );
    } catch (e, st) {
      logError('Toggle auto-sync failed.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          syncStatus: DatabaseSyncStatus.error,
          syncError: 'Unable to update auto-sync setting.',
        ),
      );
    }
  }

  void _onClearVaultSyncFeedback(
    ClearVaultSyncFeedback event,
    Emitter<VaultState> emit,
  ) {
    _safeEmit(
      emit,
      state.copyWith(clearSyncError: true, clearSyncConflict: true),
    );
  }

  Future<void> _onLoadDriveRemoteFiles(
    LoadDriveRemoteFiles event,
    Emitter<VaultState> emit,
  ) async {
    if (!state.isDriveConnected) {
      _safeEmit(
        emit,
        state.copyWith(
          remoteDriveFiles: const [],
          isLoadingRemoteDriveFiles: false,
        ),
      );
      return;
    }

    _safeEmit(
      emit,
      state.copyWith(isLoadingRemoteDriveFiles: true, clearSyncError: true),
    );
    try {
      final files = await listDriveRemoteFilesUseCase(query: event.query);
      _safeEmit(
        emit,
        state.copyWith(
          remoteDriveFiles: files,
          isLoadingRemoteDriveFiles: false,
          clearSyncError: true,
        ),
      );
    } catch (e, st) {
      if (_requiresDrivePermissionReauth(e)) {
        _safeEmit(
          emit,
          state.copyWith(
            isLoadingRemoteDriveFiles: false,
            syncError:
                'Google authorization expired. Reconnect Google Drive to continue.',
            syncStatus: DatabaseSyncStatus.error,
          ),
        );
        return;
      }

      logError('Unable to load Drive files.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          isLoadingRemoteDriveFiles: false,
          syncError: 'Unable to load remote Drive files.',
          syncStatus: DatabaseSyncStatus.error,
        ),
      );
    }
  }

  bool _requiresDrivePermissionReauth(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('authorization is outdated') ||
        message.contains('authorization needs to be renewed') ||
        message.contains('full drive access') ||
        message.contains('google account not connected');
  }

  String _buildDriveConnectErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('google sign-in cancelled')) {
      return 'Google sign-in cancelled.';
    }
    if (message.contains('android google sign-in is not configured') ||
        message.contains('ios google sign-in is not configured')) {
      return error.toString();
    }
    if (message.contains('authorization was not granted')) {
      return 'Google Drive permission not granted.';
    }
    if (message.contains(
      'google account selected, but drive permission was not granted',
    )) {
      return 'Google account selected, but Drive permission not granted.';
    }
    if (message.contains('google account not connected')) {
      return 'Google account not connected. Reconnect Google Drive.';
    }
    return 'Unable to connect Google Drive.';
  }

  Future<void> _refreshSyncState(Emitter<VaultState> emit) async {
    final connected = await getDriveConnectionStatusUseCase();
    final mapping = await databaseSyncRepository.getMapping(state.databasePath);
    _safeEmit(
      emit,
      state.copyWith(
        isDriveConnected: connected,
        isDriveLinked: mapping != null,
        linkedDriveFileName: mapping?.driveFileName,
        autoSyncEnabled: mapping?.autoSyncEnabled ?? true,
        lastSyncAt: mapping?.lastSyncAt,
        syncStatus: connected
            ? DatabaseSyncStatus.idle
            : DatabaseSyncStatus.disconnected,
        clearSyncError: true,
      ),
    );
  }

  Future<void> _scheduleAutoSync(Emitter<VaultState> emit) async {
    if (!state.isDriveConnected ||
        !state.isDriveLinked ||
        !state.autoSyncEnabled) {
      return;
    }

    _autoSyncDebounce?.cancel();
    _autoSyncDebounce = Timer(const Duration(seconds: 2), () async {
      if (isClosed || emit.isDone) {
        return;
      }
      await _performSync(emit, silentIfConflict: true);
    });
  }

  void _safeEmit(Emitter<VaultState> emit, VaultState nextState) {
    if (isClosed || emit.isDone) {
      return;
    }
    emit(nextState);
  }

  Future<void> _performSync(
    Emitter<VaultState> emit, {
    SyncConflictResolution? resolution,
    bool silentIfConflict = false,
  }) async {
    if (!state.isDriveConnected || !state.isDriveLinked) {
      return;
    }

    _safeEmit(
      emit,
      state.copyWith(
        syncStatus: DatabaseSyncStatus.syncing,
        clearSyncError: true,
      ),
    );

    try {
      final result = await syncDatabaseNowUseCase(
        state.databasePath,
        resolution: resolution,
      );

      if (result is SyncNowConflict) {
        _safeEmit(
          emit,
          state.copyWith(
            syncStatus: DatabaseSyncStatus.conflict,
            pendingSyncConflict: result.conflict,
          ),
        );

        if (!silentIfConflict) {
          _safeEmit(
            emit,
            state.copyWith(
              syncError: 'Sync conflict detected. Choose how to proceed.',
            ),
          );
        }
        return;
      }

      final mapping = await databaseSyncRepository.getMapping(
        state.databasePath,
      );

      _safeEmit(
        emit,
        state.copyWith(
          syncStatus: DatabaseSyncStatus.success,
          linkedDriveFileName: mapping?.driveFileName,
          lastSyncAt: mapping?.lastSyncAt ?? DateTime.now(),
          clearSyncError: true,
          clearSyncConflict: true,
        ),
      );
    } catch (e, st) {
      logError('Drive sync failed.', e, st);
      _safeEmit(
        emit,
        state.copyWith(
          syncStatus: DatabaseSyncStatus.error,
          syncError: 'Unable to sync with Google Drive.',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _autoSyncDebounce?.cancel();
    return super.close();
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

  Set<String> _buildDuplicateKeys(List<VaultEntry> entries) {
    return entries
        .map(
          (entry) => _entryDuplicateKey(
            title: entry.title,
            username: entry.username,
            url: entry.url,
          ),
        )
        .toSet();
  }

  String _entryDuplicateKey({
    required String title,
    required String username,
    required String url,
  }) {
    String normalize(String value) {
      return value.trim().toLowerCase();
    }

    return '${normalize(title)}|${normalize(username)}|${normalize(url)}';
  }

  String _buildCsvImportMessage({
    required int importedCount,
    required int skippedTotal,
    required int duplicateCount,
  }) {
    if (skippedTotal == 0) {
      return 'Imported $importedCount records from CSV.';
    }
    if (duplicateCount == 0) {
      return 'Imported $importedCount records from CSV. Skipped $skippedTotal.';
    }
    return 'Imported $importedCount records from CSV. Skipped $skippedTotal ($duplicateCount duplicates).';
  }

  List<String> _normalizeExpandedGroupIds({
    required List<VaultGroup> groups,
    required String rootGroupId,
    required String currentGroupId,
    required List<String> previousExpanded,
  }) {
    final existingIds = groups.map((group) => group.id).toSet();
    final byId = {for (final group in groups) group.id: group};

    final expanded = <String>{
      for (final id in previousExpanded)
        if (existingIds.contains(id)) id,
      rootGroupId,
    };

    VaultGroup? cursor = byId[currentGroupId];
    while (cursor != null) {
      expanded.add(cursor.id);
      final parentId = cursor.parentId;
      cursor = parentId == null ? null : byId[parentId];
    }

    return expanded.toList()..sort();
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
