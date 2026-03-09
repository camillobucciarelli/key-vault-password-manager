import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../../core/navigation/app_navigation.dart';
import '../../../../../core/responsive/breakpoints.dart';
import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../injection_container.dart' as di;
import '../../data/datasources/secure_data_source.dart';
import '../../domain/models/database_sync_status.dart';
import '../../domain/models/drive_remote_folder.dart';
import '../../domain/models/sync_conflict.dart';
import '../../domain/models/vault_custom_field.dart';
import '../../domain/models/vault_entry.dart';
import '../../domain/models/vault_group.dart';
import '../../domain/usecases/save_selected_database_path_usecase.dart';
import '../../domain/usecases/save_selected_key_file_path_usecase.dart';
import '../bloc/vault/vault_bloc.dart';
import '../bloc/vault/vault_event.dart';
import '../bloc/vault/vault_state.dart';
import 'database_selection_screen.dart';
import 'database_unlock_screen.dart';
import '../utils/totp_utils.dart';
import '../widgets/android_autofill_action.dart';

part 'vault/vault_shell.part.dart';
part 'vault/vault_navigation.part.dart';
part 'vault/vault_recycle_bin.part.dart';
part 'vault/vault_entries.part.dart';
part 'vault/vault_dialogs.part.dart';
part 'vault/vault_shared.part.dart';
