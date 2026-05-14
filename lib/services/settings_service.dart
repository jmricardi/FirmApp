import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  bool _isManualCropEnabled = false;
  String _localeCode = 'es';
  ThemeMode _themeMode = ThemeMode.light;
  bool _hasSeenWelcome = false;
  bool _isHelpModeEnabled = false;

  bool get isManualCropEnabled => _isManualCropEnabled;
  String get localeCode => _localeCode;
  ThemeMode get themeMode => _themeMode;
  bool get hasSeenWelcome => _hasSeenWelcome;
  bool get isHelpModeEnabled => _isHelpModeEnabled;

  SettingsService() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isManualCropEnabled = prefs.getBool('manual_crop') ?? false;
    _localeCode = prefs.getString('locale') ?? 'es';
    final themeIdx = prefs.getInt('theme_mode') ?? 1; // Default Light
    _themeMode = ThemeMode.values[themeIdx];
    _hasSeenWelcome = prefs.getBool('has_seen_welcome') ?? false;
    notifyListeners();
  }


  Future<void> toggleManualCrop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    _isManualCropEnabled = value;
    await prefs.setBool('manual_crop', value);
    notifyListeners();
  }

  Future<void> setLocale(String code) async {
    final prefs = await SharedPreferences.getInstance();
    _localeCode = code;
    await prefs.setString('locale', code);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = mode;
    await prefs.setInt('theme_mode', mode.index);
    notifyListeners();
  }

  Future<void> setWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    _hasSeenWelcome = true;
    await prefs.setBool('has_seen_welcome', true);
    notifyListeners();
  }

  void toggleHelpMode() {
    _isHelpModeEnabled = !_isHelpModeEnabled;
    notifyListeners();
  }
}
