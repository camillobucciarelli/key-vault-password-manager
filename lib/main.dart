import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loggy/loggy.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_icons.dart';
import 'core/theme/theme_cubit.dart';
import 'core/responsive/responsive_layout.dart';
import 'injection_container.dart' as di;
import 'features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart';
import 'features/password_manager/data/services/desktop_autofill_bridge_service.dart';
import 'features/password_manager/presentation/bloc/database_selection/database_selection_bloc.dart';
import 'features/password_manager/presentation/bloc/database_selection/database_selection_event.dart';
import 'features/password_manager/presentation/screens/database_selection_screen.dart';
import 'features/password_manager/data/services/android_autofill_coordinator.dart';

Future<void> main() async {
  await _bootstrapApp();
}

@pragma('vm:entry-point')
void autofillEntryPoint() {
  unawaited(_bootstrapApp());
}

Future<void> _bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureLogging();
  await di.init();
  await di.sl<AndroidAutofillCoordinator>().initialize();
  await di.sl<IosAutofillSnapshotCoordinator>().initialize();
  await di.sl<DesktopAutofillBridgeService>().start();
  runApp(const PasswordManagerApp());
}

void _configureLogging() {
  Loggy.initLoggy(
    logPrinter: const PrettyPrinter(),
    logOptions: kReleaseMode
        ? const LogOptions(LogLevel.error, stackTraceLevel: LogLevel.error)
        : const LogOptions(LogLevel.all, stackTraceLevel: LogLevel.error),
  );

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logError(
      'Unhandled Flutter framework error',
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logError('Unhandled platform error', error, stack);
    return true;
  };
}

class PasswordManagerApp extends StatelessWidget {
  const PasswordManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit()),
        BlocProvider(
          create: (_) =>
              di.sl<DatabaseSelectionBloc>()..add(CheckInitialDatabase()),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: 'Antigravity Password Manager',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: const DatabaseSelectionScreen(),
          );
        },
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Password Manager MVP'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.magic),
            onPressed: () {
              context.read<ThemeCubit>().toggleTheme();
            },
            tooltip: 'Toggle Theme',
          ),
        ],
      ),
      body: ResponsiveLayout(
        mobileBody: const Center(
          child: Text(
            'Mobile Layout',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        tabletBody: const Center(
          child: Text(
            'Tablet Layout',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
        ),
        desktopBody: const Center(
          child: Text(
            'Desktop Layout',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
