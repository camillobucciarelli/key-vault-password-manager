import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit() : super(ThemeMode.system);

  void toggleTheme() {
    if (state == ThemeMode.light) {
      emit(ThemeMode.dark);
    } else if (state == ThemeMode.dark) {
      emit(ThemeMode.light);
    } else {
      // If system, switch to light or dark based on a default (here we choose dark to toggle to light, or vice-versa)
      // For simplicity, from system, let's go to light
      emit(ThemeMode.light);
    }
  }

  void setTheme(ThemeMode mode) {
    emit(mode);
  }
}
