import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kdbx/kdbx.dart';
import 'package:loggy/loggy.dart';

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
    emit(DatabaseSelectionLoading());
    try {
      final path = await getSelectedDatabasePathUseCase();
      if (path != null && path.isNotEmpty) {
        // Also validate it still exists and is correct
        final isValid = await validateDatabaseUseCase(path);
        if (isValid) {
          emit(DatabaseSelectionSuccess(path));
        } else {
          // Path saved but invalid file (maybe deleted or corrupted)
          emit(
            const DatabaseSelectionError(
              'Database file not found or corrupted.',
            ),
          );
          emit(DatabaseSelectionUnselected());
        }
      } else {
        emit(DatabaseSelectionUnselected());
      }
    } catch (e, st) {
      logError('Failed to check initial database selection state.', e, st);
      emit(DatabaseSelectionError(e.toString()));
      emit(DatabaseSelectionUnselected());
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
        withData: kIsWeb,
      );

      if (result != null) {
        emit(DatabaseSelectionLoading());

        final path = _resolveSelectedDatabasePath(result);
        if (path == null) {
          emit(const DatabaseSelectionError('Could not resolve file path.'));
          emit(DatabaseSelectionUnselected());
          return;
        }

        final isValid = await validateDatabaseUseCase(path);
        if (isValid) {
          await saveSelectedDatabasePathUseCase(path);
          await saveSelectedKeyFilePathUseCase(null);
          await secureDataSource.clearMasterPassword();
          await setBiometricProtectionEnabledUseCase(true);
          emit(DatabaseSelectionSuccess(path));
        } else {
          emit(
            const DatabaseSelectionError(
              'The selected file is not a valid KDBX file.',
            ),
          );
          emit(DatabaseSelectionUnselected());
        }
      }
    } catch (e, st) {
      logError('Failed while selecting an existing database file.', e, st);
      emit(DatabaseSelectionError(e.toString()));
      emit(DatabaseSelectionUnselected());
    }
  }

  Future<void> _onCreateNewDatabase(
    CreateNewDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    try {
      var outputFile = await _resolveOutputFilePath();

      if (outputFile != null) {
        emit(DatabaseSelectionLoading());

        if (!outputFile.toLowerCase().endsWith('.kdbx')) {
          outputFile += '.kdbx';
        }

        if (!kIsWeb) {
          final selectedKeyFilePath = await _prepareKeyFilePath(event, emit);
          if (selectedKeyFilePath == null && event.generateKeyFile) {
            return;
          }

          await _createDesktopDatabase(
            outputFile: outputFile,
            password: event.password,
            keyFilePath: selectedKeyFilePath,
          );
        }

        await saveSelectedDatabasePathUseCase(outputFile);
        emit(DatabaseSelectionSuccess(outputFile));
      }
    } catch (e, st) {
      logError('Failed while creating a new database file.', e, st);
      emit(DatabaseSelectionError(e.toString()));
      emit(DatabaseSelectionUnselected());
    }
  }

  Future<void> _onSelectDriveDatabaseLocalCopy(
    SelectDriveDatabaseLocalCopy event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    try {
      emit(DatabaseSelectionLoading());

      final isValid = await validateDatabaseUseCase(event.localPath);
      if (!isValid) {
        emit(
          const DatabaseSelectionError(
            'The downloaded Drive file is not a valid KDBX database.',
          ),
        );
        emit(DatabaseSelectionUnselected());
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
        emit(
          const DatabaseSelectionError(
            'Database opened, but auto-link to Drive failed. You can link it from the Vault sync menu.',
          ),
        );
      }

      emit(DatabaseSelectionSuccess(event.localPath));
    } catch (e, st) {
      logError('Failed while selecting database from Drive.', e, st);
      emit(DatabaseSelectionError(e.toString()));
      emit(DatabaseSelectionUnselected());
    }
  }

  Uint8List _generateRandomKeyFileBytes() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(64, (_) => random.nextInt(256)),
    );
  }

  String? _resolveSelectedDatabasePath(FilePickerResult result) {
    if (kIsWeb) {
      return 'web_selected_db.kdbx';
    }
    return result.files.single.path;
  }

  Future<String?> _resolveOutputFilePath() async {
    if (kIsWeb) {
      return 'web_internal_db.kdbx';
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
      final generatedPath = event.generatedKeyFilePath;
      if (generatedPath == null || generatedPath.trim().isEmpty) {
        emit(
          const DatabaseSelectionError(
            'No destination selected for generated key file.',
          ),
        );
        emit(DatabaseSelectionUnselected());
        return null;
      }

      final keyFileBytes = _generateRandomKeyFileBytes();
      await File(generatedPath).writeAsBytes(keyFileBytes);
      return generatedPath;
    }

    final selectedPath = event.keyFilePath;
    if (selectedPath == null || selectedPath.isEmpty) {
      return null;
    }
    return selectedPath;
  }

  Future<void> _createDesktopDatabase({
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
    await File(outputFile).writeAsBytes(await kdbx.save());

    await saveSelectedKeyFilePathUseCase(keyFilePath);
    await setBiometricProtectionEnabledUseCase(true);
    await secureDataSource.saveMasterPassword(password);
  }
}
