import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService with ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.system;

  SharedPreferences? _prefs;

  ThemeService() {
    _loadTheme();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();
    _saveTheme();
  }

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _saveTheme() async {
    await _initPrefs();
    await _prefs?.setString(_themeKey, _themeMode.toString());
  }

  Future<void> _loadTheme() async {
    await _initPrefs();
    final themeStr = _prefs?.getString(_themeKey);
    if (themeStr != null) {
      if (themeStr == ThemeMode.light.toString()) {
        _themeMode = ThemeMode.light;
      } else if (themeStr == ThemeMode.dark.toString()) {
        _themeMode = ThemeMode.dark;
      }
    }
    notifyListeners();
  }
}
