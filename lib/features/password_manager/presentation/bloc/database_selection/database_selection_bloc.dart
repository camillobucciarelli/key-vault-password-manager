import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kdbx/kdbx.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/mobile_file_storage.dart';
import '../../../data/datasources/secure_data_source.dart';
import '../../../domain/usecases/add_recent_database_path_usecase.dart';
import '../../../domain/usecases/get_recent_database_paths_usecase.dart';
import '../../../domain/usecases/link_database_to_drive_usecase.dart';
import '../../../domain/usecases/remove_recent_database_path_usecase.dart';
import '../../../domain/usecases/save_selected_key_file_path_usecase.dart';
import '../../../domain/usecases/get_selected_database_path_usecase.dart';
import '../../../domain/usecases/set_biometric_protection_enabled_usecase.dart';
import '../../../domain/usecases/save_selected_database_path_usecase.dart';
import '../../../domain/usecases/validate_database_usecase.dart';
import '../../../domain/repositories/database_sync_repository.dart';
import 'database_selection_event.dart';
import 'database_selection_state.dart';

class DatabaseSelectionBloc
    extends Bloc<DatabaseSelectionEvent, DatabaseSelectionState> {
  final GetSelectedDatabasePathUseCase getSelectedDatabasePathUseCase;
  final SaveSelectedDatabasePathUseCase saveSelectedDatabasePathUseCase;
  final SaveSelectedKeyFilePathUseCase saveSelectedKeyFilePathUseCase;
  final GetRecentDatabasePathsUseCase getRecentDatabasePathsUseCase;
  final AddRecentDatabasePathUseCase addRecentDatabasePathUseCase;
  final RemoveRecentDatabasePathUseCase removeRecentDatabasePathUseCase;
  final SetBiometricProtectionEnabledUseCase
  setBiometricProtectionEnabledUseCase;
  final SecureDataSource secureDataSource;
  final ValidateDatabaseUseCase validateDatabaseUseCase;
  final LinkDatabaseToDriveUseCase linkDatabaseToDriveUseCase;
  final DatabaseSyncRepository databaseSyncRepository;

  DatabaseSelectionBloc({
    required this.getSelectedDatabasePathUseCase,
    required this.saveSelectedDatabasePathUseCase,
    required this.saveSelectedKeyFilePathUseCase,
    required this.getRecentDatabasePathsUseCase,
    required this.addRecentDatabasePathUseCase,
    required this.removeRecentDatabasePathUseCase,
    required this.setBiometricProtectionEnabledUseCase,
    required this.secureDataSource,
    required this.validateDatabaseUseCase,
    required this.linkDatabaseToDriveUseCase,
    required this.databaseSyncRepository,
  }) : super(const DatabaseSelectionInitial()) {
    on<CheckInitialDatabase>(_onCheckInitialDatabase);
    on<SelectExistingDatabase>(_onSelectExistingDatabase);
    on<OpenRecentDatabase>(_onOpenRecentDatabase);
    on<CreateNewDatabase>(_onCreateNewDatabase);
    on<SelectDriveDatabaseLocalCopy>(_onSelectDriveDatabaseLocalCopy);
    on<RemoveRecentDatabase>(_onRemoveRecentDatabase);
  }

  Future<void> _onCheckInitialDatabase(
    CheckInitialDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    final recent = await _loadRecentDatabasePaths();
    _safeEmit(emit, DatabaseSelectionLoading(recentDatabasePaths: recent));
    try {
      if (recent.length > 1) {
        _safeEmit(
          emit,
          DatabaseSelectionUnselected(recentDatabasePaths: recent),
        );
        return;
      }

      final selectedPath = (await getSelectedDatabasePathUseCase())?.trim();
      final path = (selectedPath != null && selectedPath.isNotEmpty)
          ? selectedPath
          : (recent.length == 1 ? recent.first : null);

      if (path != null && path.isNotEmpty) {
        final isValid = await validateDatabaseUseCase(path);
        if (isValid) {
          await saveSelectedDatabasePathUseCase(path);
          await addRecentDatabasePathUseCase(path);
          final updatedRecent = await _loadRecentDatabasePaths();
          _safeEmit(
            emit,
            DatabaseSelectionSuccess(path, recentDatabasePaths: updatedRecent),
          );
        } else {
          await removeRecentDatabasePathUseCase(path);
          _safeEmit(
            emit,
            DatabaseSelectionError(
              'Database file not found or corrupted.',
              recentDatabasePaths: await _loadRecentDatabasePaths(),
            ),
          );
          _safeEmit(
            emit,
            DatabaseSelectionUnselected(
              recentDatabasePaths: await _loadRecentDatabasePaths(),
            ),
          );
        }
      } else {
        _safeEmit(
          emit,
          DatabaseSelectionUnselected(recentDatabasePaths: recent),
        );
      }
    } catch (e, st) {
      logError('Failed to check initial database selection state.', e, st);
      _safeEmit(
        emit,
        DatabaseSelectionError(e.toString(), recentDatabasePaths: recent),
      );
      _safeEmit(emit, DatabaseSelectionUnselected(recentDatabasePaths: recent));
    }
  }

  Future<void> _onSelectExistingDatabase(
    SelectExistingDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kdbx'],
        withData: kIsWeb || _isMobilePlatform,
      );

      if (result != null) {
        final recent = await _loadRecentDatabasePaths();
        _safeEmit(emit, DatabaseSelectionLoading(recentDatabasePaths: recent));

        final path = await _resolveSelectedDatabasePath(result);
        if (path == null) {
          _safeEmit(
            emit,
            const DatabaseSelectionError('Could not resolve file path.'),
          );
          _safeEmit(
            emit,
            DatabaseSelectionUnselected(recentDatabasePaths: recent),
          );
          return;
        }

        final isValid = await validateDatabaseUseCase(path);
        if (isValid) {
          await saveSelectedDatabasePathUseCase(path);
          await addRecentDatabasePathUseCase(path);
          await saveSelectedKeyFilePathUseCase(null);
          await secureDataSource.clearMasterPassword();
          await setBiometricProtectionEnabledUseCase(false);
          final updatedRecent = await _loadRecentDatabasePaths();
          _safeEmit(
            emit,
            DatabaseSelectionSuccess(
              path,
              userMessage: _isMobilePlatform
                  ? 'Database imported to app internal storage for reliable access.'
                  : null,
              recentDatabasePaths: updatedRecent,
            ),
          );
        } else {
          _safeEmit(
            emit,
            const DatabaseSelectionError(
              'The selected file is not a valid KDBX file.',
            ),
          );
          _safeEmit(
            emit,
            DatabaseSelectionUnselected(recentDatabasePaths: recent),
          );
        }
      }
    } catch (e, st) {
      logError('Failed while selecting an existing database file.', e, st);
      final recent = await _loadRecentDatabasePaths();
      _safeEmit(
        emit,
        DatabaseSelectionError(e.toString(), recentDatabasePaths: recent),
      );
      _safeEmit(emit, DatabaseSelectionUnselected(recentDatabasePaths: recent));
    }
  }

  Future<void> _onOpenRecentDatabase(
    OpenRecentDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    final path = event.path.trim();
    final recent = await _loadRecentDatabasePaths();
    if (path.isEmpty) {
      _safeEmit(emit, DatabaseSelectionUnselected(recentDatabasePaths: recent));
      return;
    }

    _safeEmit(emit, DatabaseSelectionLoading(recentDatabasePaths: recent));
    try {
      final isValid = await validateDatabaseUseCase(path);
      if (!isValid) {
        await removeRecentDatabasePathUseCase(path);
        final updatedRecent = await _loadRecentDatabasePaths();
        _safeEmit(
          emit,
          DatabaseSelectionError(
            'The selected recent database is no longer available or is invalid.',
            recentDatabasePaths: updatedRecent,
          ),
        );
        _safeEmit(
          emit,
          DatabaseSelectionUnselected(recentDatabasePaths: updatedRecent),
        );
        return;
      }

      await saveSelectedDatabasePathUseCase(path);
      await addRecentDatabasePathUseCase(path);
      await saveSelectedKeyFilePathUseCase(null);
      await secureDataSource.clearMasterPassword();
      await setBiometricProtectionEnabledUseCase(false);

      final updatedRecent = await _loadRecentDatabasePaths();
      _safeEmit(
        emit,
        DatabaseSelectionSuccess(path, recentDatabasePaths: updatedRecent),
      );
    } catch (e, st) {
      logError('Failed while opening a recent database file.', e, st);
      final updatedRecent = await _loadRecentDatabasePaths();
      _safeEmit(
        emit,
        DatabaseSelectionError(
          e.toString(),
          recentDatabasePaths: updatedRecent,
        ),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(recentDatabasePaths: updatedRecent),
      );
    }
  }

  Future<void> _onCreateNewDatabase(
    CreateNewDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    try {
      var outputFile = await _resolveOutputFilePath(event.databaseFileName);
      String? selectedKeyFilePath;

      if (outputFile != null) {
        final recent = await _loadRecentDatabasePaths();
        _safeEmit(emit, DatabaseSelectionLoading(recentDatabasePaths: recent));

        if (!outputFile.toLowerCase().endsWith('.kdbx')) {
          outputFile += '.kdbx';
        }

        if (!kIsWeb) {
          selectedKeyFilePath = await _prepareKeyFilePath(event, emit);
          if (selectedKeyFilePath == null && event.generateKeyFile) {
            return;
          }

          outputFile = await _createDatabase(
            outputFile: outputFile,
            password: event.password,
            keyFilePath: selectedKeyFilePath,
            biometricProtectionEnabled: event.biometricProtectionEnabled,
          );
        }

        await saveSelectedDatabasePathUseCase(outputFile);
        await addRecentDatabasePathUseCase(outputFile);
        final updatedRecent = await _loadRecentDatabasePaths();
        _safeEmit(
          emit,
          DatabaseSelectionSuccess(
            outputFile,
            userMessage: _buildCreationMessage(
              databasePath: outputFile,
              keyFilePath: selectedKeyFilePath,
            ),
            recentDatabasePaths: updatedRecent,
          ),
        );
      }
    } catch (e, st) {
      logError('Failed while creating a new database file.', e, st);
      final recent = await _loadRecentDatabasePaths();
      _safeEmit(
        emit,
        DatabaseSelectionError(e.toString(), recentDatabasePaths: recent),
      );
      _safeEmit(emit, DatabaseSelectionUnselected(recentDatabasePaths: recent));
    }
  }

  String _buildCreationMessage({
    required String databasePath,
    required String? keyFilePath,
  }) {
    final databaseMessage = _isMobilePlatform
        ? 'Database saved in app internal storage.'
        : 'Database saved to: $databasePath';
    final keyMessage = keyFilePath == null || keyFilePath.trim().isEmpty
        ? 'No key file configured.'
        : _isMobilePlatform
        ? 'Key file saved in app internal storage.'
        : 'Key file path: $keyFilePath';
    return '$databaseMessage $keyMessage';
  }

  Future<void> _onSelectDriveDatabaseLocalCopy(
    SelectDriveDatabaseLocalCopy event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    try {
      final recent = await _loadRecentDatabasePaths();
      _safeEmit(emit, DatabaseSelectionLoading(recentDatabasePaths: recent));

      final isValid = await validateDatabaseUseCase(event.localPath);
      if (!isValid) {
        _safeEmit(
          emit,
          const DatabaseSelectionError(
            'The downloaded Drive file is not a valid KDBX database.',
          ),
        );
        _safeEmit(
          emit,
          DatabaseSelectionUnselected(recentDatabasePaths: recent),
        );
        return;
      }

      await saveSelectedDatabasePathUseCase(event.localPath);
      await addRecentDatabasePathUseCase(event.localPath);
      await saveSelectedKeyFilePathUseCase(null);
      await secureDataSource.clearMasterPassword();
      await setBiometricProtectionEnabledUseCase(false);

      try {
        await linkDatabaseToDriveUseCase(
          databasePath: event.localPath,
          remoteFileId: event.remoteFileId,
        );
      } catch (e, st) {
        logWarning('Drive linking failed after download.', e, st);
        _safeEmit(
          emit,
          const DatabaseSelectionError(
            'Database opened, but auto-link to Drive failed. You can link it from the Vault sync menu.',
          ),
        );
      }

      final updatedRecent = await _loadRecentDatabasePaths();
      _safeEmit(
        emit,
        DatabaseSelectionSuccess(
          event.localPath,
          recentDatabasePaths: updatedRecent,
        ),
      );
    } catch (e, st) {
      logError('Failed while selecting database from Drive.', e, st);
      final recent = await _loadRecentDatabasePaths();
      _safeEmit(
        emit,
        DatabaseSelectionError(e.toString(), recentDatabasePaths: recent),
      );
      _safeEmit(emit, DatabaseSelectionUnselected(recentDatabasePaths: recent));
    }
  }

  Future<void> _onRemoveRecentDatabase(
    RemoveRecentDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    final path = event.path.trim();
    if (path.isEmpty) {
      return;
    }

    final recent = await _loadRecentDatabasePaths();
    _safeEmit(emit, DatabaseSelectionLoading(recentDatabasePaths: recent));

    var userMessage = 'Database removed from recent list.';
    try {
      await removeRecentDatabasePathUseCase(path);

      final selectedPath = await getSelectedDatabasePathUseCase();
      if (selectedPath != null && selectedPath.trim() == path) {
        await saveSelectedDatabasePathUseCase('');
        await saveSelectedKeyFilePathUseCase(null);
        await secureDataSource.clearMasterPassword();
      }

      try {
        await databaseSyncRepository.removeMapping(path);
      } catch (e, st) {
        logWarning(
          'Unable to remove sync mapping while deleting recent DB.',
          e,
          st,
        );
      }

      if (event.mode == RecentDatabaseRemovalMode.removeAndDeleteFile &&
          !kIsWeb) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          userMessage = 'Database removed from list and file deleted.';
        } else {
          userMessage = 'Database removed from list. File was already missing.';
        }
      }

      final updatedRecent = await _loadRecentDatabasePaths();
      _safeEmit(
        emit,
        DatabaseSelectionInfo(userMessage, recentDatabasePaths: updatedRecent),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(recentDatabasePaths: updatedRecent),
      );
    } catch (e, st) {
      logError('Failed while removing a recent database.', e, st);
      final updatedRecent = await _loadRecentDatabasePaths();
      final message =
          event.mode == RecentDatabaseRemovalMode.removeAndDeleteFile
          ? 'Database removed from list, but file deletion failed: $e'
          : 'Unable to remove database from recent list: $e';
      _safeEmit(
        emit,
        DatabaseSelectionError(message, recentDatabasePaths: updatedRecent),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(recentDatabasePaths: updatedRecent),
      );
    }
  }

  Future<List<String>> _loadRecentDatabasePaths() async {
    try {
      final paths = await getRecentDatabasePathsUseCase();
      if (paths.isEmpty || kIsWeb) {
        return paths;
      }

      final validPaths = <String>[];
      var hasRemovedMissingEntries = false;
      for (final path in paths) {
        try {
          final exists = await File(path).exists();
          if (exists) {
            validPaths.add(path);
          } else {
            hasRemovedMissingEntries = true;
          }
        } catch (_) {
          validPaths.add(path);
        }
      }

      if (hasRemovedMissingEntries) {
        for (final path in paths) {
          if (!validPaths.contains(path)) {
            await removeRecentDatabasePathUseCase(path);
          }
        }
      }

      return validPaths;
    } catch (e, st) {
      logWarning('Unable to load recent database list.', e, st);
      return const [];
    }
  }

  Uint8List _generateRandomKeyFileBytes() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(64, (_) => random.nextInt(256)),
    );
  }

  Future<String?> _resolveSelectedDatabasePath(FilePickerResult result) async {
    if (kIsWeb) {
      return 'web_selected_db.kdbx';
    }

    final selectedFile = result.files.single;
    if (!_isMobilePlatform) {
      return selectedFile.path;
    }

    final selectedPath = selectedFile.path;
    if (selectedPath != null && selectedPath.isNotEmpty) {
      return MobileFileStorage.copyFileToAppDirectory(
        sourcePath: selectedPath,
        fallbackFileName: selectedFile.name,
        subdirectory: 'databases',
      );
    }

    final selectedBytes = selectedFile.bytes;
    if (selectedBytes == null) {
      return null;
    }
    return MobileFileStorage.saveBytesToAppDirectory(
      bytes: selectedBytes,
      fileName: selectedFile.name,
      subdirectory: 'databases',
    );
  }

  Future<String?> _resolveOutputFilePath(String preferredFileName) async {
    final normalizedFileName = _normalizeDatabaseFileName(preferredFileName);
    if (kIsWeb) {
      return normalizedFileName;
    }
    if (_isMobilePlatform) {
      return normalizedFileName;
    }
    return FilePicker.platform.saveFile(
      dialogTitle: 'Please select an output file:',
      fileName: normalizedFileName,
      type: FileType.custom,
      allowedExtensions: ['kdbx'],
    );
  }

  String _normalizeDatabaseFileName(String value) {
    final trimmed = value.trim();
    final fallback = 'new_database.kdbx';
    if (trimmed.isEmpty) {
      return fallback;
    }

    final normalized = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (normalized.isEmpty) {
      return fallback;
    }

    return normalized.toLowerCase().endsWith('.kdbx')
        ? normalized
        : '$normalized.kdbx';
  }

  Future<String?> _prepareKeyFilePath(
    CreateNewDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    if (event.generateKeyFile) {
      final keyFileBytes = _generateRandomKeyFileBytes();
      if (_isMobilePlatform) {
        final fileName = event.generatedKeyFilePath == null
            ? 'database.key'
            : p.basename(event.generatedKeyFilePath!);
        return MobileFileStorage.saveBytesToAppDirectory(
          bytes: keyFileBytes,
          fileName: fileName,
          subdirectory: 'keys',
        );
      }

      final generatedPath = event.generatedKeyFilePath;
      if (generatedPath == null || generatedPath.trim().isEmpty) {
        _safeEmit(
          emit,
          const DatabaseSelectionError(
            'No destination selected for generated key file.',
          ),
        );
        _safeEmit(emit, DatabaseSelectionUnselected());
        return null;
      }

      await File(generatedPath).writeAsBytes(keyFileBytes);
      return generatedPath;
    }

    final selectedPath = event.keyFilePath;
    if (selectedPath == null || selectedPath.isEmpty) {
      return null;
    }
    if (_isMobilePlatform) {
      return MobileFileStorage.copyFileToAppDirectory(
        sourcePath: selectedPath,
        fallbackFileName: 'database.key',
        subdirectory: 'keys',
      );
    }
    return selectedPath;
  }

  Future<String> _createDatabase({
    required String outputFile,
    required String password,
    required String? keyFilePath,
    required bool biometricProtectionEnabled,
  }) async {
    Uint8List? keyFileBytes;
    if (keyFilePath != null && keyFilePath.isNotEmpty) {
      keyFileBytes = await File(keyFilePath).readAsBytes();
    }

    final credentials = Credentials.composite(
      ProtectedValue.fromString(password),
      keyFileBytes,
    );

    final kdbx = KdbxFormat().create(credentials, 'New Database');
    final savedBytes = await kdbx.save();
    final finalOutputPath = _isMobilePlatform
        ? await MobileFileStorage.saveBytesToAppDirectory(
            bytes: savedBytes,
            fileName: p.basename(outputFile),
            subdirectory: 'databases',
          )
        : outputFile;

    if (!_isMobilePlatform) {
      await File(finalOutputPath).writeAsBytes(savedBytes);
    }

    await saveSelectedKeyFilePathUseCase(keyFilePath);
    await setBiometricProtectionEnabledUseCase(biometricProtectionEnabled);
    await secureDataSource.saveMasterPassword(password);
    return finalOutputPath;
  }

  bool get _isMobilePlatform {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
  }

  void _safeEmit(
    Emitter<DatabaseSelectionState> emit,
    DatabaseSelectionState nextState,
  ) {
    if (isClosed || emit.isDone) {
      return;
    }
    emit(nextState);
  }
}
