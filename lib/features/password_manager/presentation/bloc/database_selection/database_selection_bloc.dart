import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kdbx/kdbx.dart';
import 'package:loggy/loggy.dart';

import '../../../data/datasources/secure_data_source.dart';
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

  DatabaseSelectionBloc({
    required this.getSelectedDatabasePathUseCase,
    required this.saveSelectedDatabasePathUseCase,
    required this.saveSelectedKeyFilePathUseCase,
    required this.setBiometricProtectionEnabledUseCase,
    required this.secureDataSource,
    required this.validateDatabaseUseCase,
  }) : super(DatabaseSelectionInitial()) {
    on<CheckInitialDatabase>(_onCheckInitialDatabase);
    on<SelectExistingDatabase>(_onSelectExistingDatabase);
    on<CreateNewDatabase>(_onCreateNewDatabase);
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kdbx'],
        withData: kIsWeb, // Required to get file bytes on Web
      );

      if (result != null) {
        emit(DatabaseSelectionLoading());

        String path;
        if (kIsWeb) {
          path = 'web_selected_db.kdbx';
          // NOTE: On Web, the file bytes are in result.files.single.bytes
          // To fully support reading the KDBX on Web, these bytes should be saved
          // to SharedPreferences or a Memory Cache here. For now, we save the virtual path.
        } else {
          if (result.files.single.path == null) {
            emit(const DatabaseSelectionError('Could not resolve file path.'));
            emit(DatabaseSelectionUnselected());
            return;
          }
          path = result.files.single.path!;
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
      String? outputFile;

      if (kIsWeb) {
        outputFile = 'web_internal_db.kdbx';
      } else {
        outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Please select an output file:',
          fileName: 'new_database.kdbx',
          type: FileType.custom,
          allowedExtensions: ['kdbx'],
        );
      }

      if (outputFile != null) {
        emit(DatabaseSelectionLoading());

        if (!outputFile.toLowerCase().endsWith('.kdbx')) {
          outputFile += '.kdbx';
        }

        if (!kIsWeb) {
          Uint8List? keyFileBytes;
          String? selectedKeyFilePath;

          if (event.generateKeyFile) {
            if (event.generatedKeyFilePath == null ||
                event.generatedKeyFilePath!.trim().isEmpty) {
              emit(
                const DatabaseSelectionError(
                  'No destination selected for generated key file.',
                ),
              );
              emit(DatabaseSelectionUnselected());
              return;
            }

            selectedKeyFilePath = event.generatedKeyFilePath;
            keyFileBytes = _generateRandomKeyFileBytes();
            await File(selectedKeyFilePath!).writeAsBytes(keyFileBytes);
          } else if (event.keyFilePath != null &&
              event.keyFilePath!.isNotEmpty) {
            selectedKeyFilePath = event.keyFilePath;
            keyFileBytes = await File(event.keyFilePath!).readAsBytes();
          }

          final credentials = Credentials.composite(
            ProtectedValue.fromString(event.password),
            keyFileBytes,
          );

          final kdbx = KdbxFormat().create(credentials, 'New Database');
          await File(outputFile).writeAsBytes(await kdbx.save());

          await saveSelectedKeyFilePathUseCase(selectedKeyFilePath);
          await setBiometricProtectionEnabledUseCase(true);
          await secureDataSource.saveMasterPassword(event.password);
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

  Uint8List _generateRandomKeyFileBytes() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(64, (_) => random.nextInt(256)),
    );
  }
}
