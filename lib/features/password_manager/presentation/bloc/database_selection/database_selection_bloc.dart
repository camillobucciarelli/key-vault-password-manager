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
import '../../../domain/usecases/link_database_to_drive_usecase.dart';
import '../../../domain/usecases/save_selected_key_file_path_usecase.dart';
import '../../../domain/usecases/get_selected_database_path_usecase.dart';
import '../../../domain/usecases/set_biometric_protection_enabled_usecase.dart';
import '../../../domain/usecases/save_selected_database_path_usecase.dart';
import '../../../domain/usecases/validate_database_usecase.dart';
import 'database_selection_event.dart';
import 'database_selection_state.dart';

class DatabaseSelectionBloc
    extends Bloc<DatabaseSelectionEvent, DatabaseSelectionState> {
  final GetSelectedDatabasePathUseCase getSelectedDatabasePathUseCase;
  final SaveSelectedDatabasePathUseCase saveSelectedDatabasePathUseCase;
  final SaveSelectedKeyFilePathUseCase saveSelectedKeyFilePathUseCase;
  final SetBiometricProtectionEnabledUseCase
  setBiometricProtectionEnabledUseCase;
  final SecureDataSource secureDataSource;
  final ValidateDatabaseUseCase validateDatabaseUseCase;
  final LinkDatabaseToDriveUseCase linkDatabaseToDriveUseCase;

  DatabaseSelectionBloc({
    required this.getSelectedDatabasePathUseCase,
    required this.saveSelectedDatabasePathUseCase,
    required this.saveSelectedKeyFilePathUseCase,
    required this.setBiometricProtectionEnabledUseCase,
    required this.secureDataSource,
    required this.validateDatabaseUseCase,
    required this.linkDatabaseToDriveUseCase,
  }) : super(DatabaseSelectionInitial()) {
    on<CheckInitialDatabase>(_onCheckInitialDatabase);
    on<SelectExistingDatabase>(_onSelectExistingDatabase);
    on<CreateNewDatabase>(_onCreateNewDatabase);
    on<SelectDriveDatabaseLocalCopy>(_onSelectDriveDatabaseLocalCopy);
  }

  Future<void> _onCheckInitialDatabase(
    CheckInitialDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    _safeEmit(emit, DatabaseSelectionLoading());
    try {
      final path = await getSelectedDatabasePathUseCase();
      if (path != null && path.isNotEmpty) {
        // Also validate it still exists and is correct
        final isValid = await validateDatabaseUseCase(path);
        if (isValid) {
          _safeEmit(emit, DatabaseSelectionSuccess(path));
        } else {
          // Path saved but invalid file (maybe deleted or corrupted)
          _safeEmit(
            emit,
            const DatabaseSelectionError(
              'Database file not found or corrupted.',
            ),
          );
          _safeEmit(emit, DatabaseSelectionUnselected());
        }
      } else {
        _safeEmit(emit, DatabaseSelectionUnselected());
      }
    } catch (e, st) {
      logError('Failed to check initial database selection state.', e, st);
      _safeEmit(emit, DatabaseSelectionError(e.toString()));
      _safeEmit(emit, DatabaseSelectionUnselected());
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
        _safeEmit(emit, DatabaseSelectionLoading());

        final path = await _resolveSelectedDatabasePath(result);
        if (path == null) {
          _safeEmit(
            emit,
            const DatabaseSelectionError('Could not resolve file path.'),
          );
          _safeEmit(emit, DatabaseSelectionUnselected());
          return;
        }

        final isValid = await validateDatabaseUseCase(path);
        if (isValid) {
          await saveSelectedDatabasePathUseCase(path);
          await saveSelectedKeyFilePathUseCase(null);
          await secureDataSource.clearMasterPassword();
          await setBiometricProtectionEnabledUseCase(true);
          _safeEmit(
            emit,
            DatabaseSelectionSuccess(
              path,
              userMessage: _isMobilePlatform
                  ? 'Database imported to app internal storage for reliable access.'
                  : null,
            ),
          );
        } else {
          _safeEmit(
            emit,
            const DatabaseSelectionError(
              'The selected file is not a valid KDBX file.',
            ),
          );
          _safeEmit(emit, DatabaseSelectionUnselected());
        }
      }
    } catch (e, st) {
      logError('Failed while selecting an existing database file.', e, st);
      _safeEmit(emit, DatabaseSelectionError(e.toString()));
      _safeEmit(emit, DatabaseSelectionUnselected());
    }
  }

  Future<void> _onCreateNewDatabase(
    CreateNewDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    try {
      var outputFile = await _resolveOutputFilePath();

      if (outputFile != null) {
        _safeEmit(emit, DatabaseSelectionLoading());

        if (!outputFile.toLowerCase().endsWith('.kdbx')) {
          outputFile += '.kdbx';
        }

        if (!kIsWeb) {
          final selectedKeyFilePath = await _prepareKeyFilePath(event, emit);
          if (selectedKeyFilePath == null && event.generateKeyFile) {
            return;
          }

          outputFile = await _createDatabase(
            outputFile: outputFile,
            password: event.password,
            keyFilePath: selectedKeyFilePath,
          );
        }

        await saveSelectedDatabasePathUseCase(outputFile);
        _safeEmit(
          emit,
          DatabaseSelectionSuccess(
            outputFile,
            userMessage: _isMobilePlatform
                ? 'New database saved to app internal storage.'
                : null,
          ),
        );
      }
    } catch (e, st) {
      logError('Failed while creating a new database file.', e, st);
      _safeEmit(emit, DatabaseSelectionError(e.toString()));
      _safeEmit(emit, DatabaseSelectionUnselected());
    }
  }

  Future<void> _onSelectDriveDatabaseLocalCopy(
    SelectDriveDatabaseLocalCopy event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    try {
      _safeEmit(emit, DatabaseSelectionLoading());

      final isValid = await validateDatabaseUseCase(event.localPath);
      if (!isValid) {
        _safeEmit(
          emit,
          const DatabaseSelectionError(
            'The downloaded Drive file is not a valid KDBX database.',
          ),
        );
        _safeEmit(emit, DatabaseSelectionUnselected());
        return;
      }

      await saveSelectedDatabasePathUseCase(event.localPath);
      await saveSelectedKeyFilePathUseCase(null);
      await secureDataSource.clearMasterPassword();
      await setBiometricProtectionEnabledUseCase(true);

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

      _safeEmit(emit, DatabaseSelectionSuccess(event.localPath));
    } catch (e, st) {
      logError('Failed while selecting database from Drive.', e, st);
      _safeEmit(emit, DatabaseSelectionError(e.toString()));
      _safeEmit(emit, DatabaseSelectionUnselected());
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

  Future<String?> _resolveOutputFilePath() async {
    if (kIsWeb) {
      return 'web_internal_db.kdbx';
    }
    if (_isMobilePlatform) {
      return 'new_database.kdbx';
    }
    return FilePicker.platform.saveFile(
      dialogTitle: 'Please select an output file:',
      fileName: 'new_database.kdbx',
      type: FileType.custom,
      allowedExtensions: ['kdbx'],
    );
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
    await setBiometricProtectionEnabledUseCase(true);
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
