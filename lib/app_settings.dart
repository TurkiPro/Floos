import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/theme/tokens.dart';

/// Reactive holder for user UI preferences (theme mode + accent color),
/// backed by SharedPreferences. The app root listens to this so a change
/// re-themes the whole tree immediately, and the choice survives relaunch.
class AppSettings extends ChangeNotifier {
  static const _kThemeMode = 'themeMode';
  static const _kAccent = 'accent';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  AppAccent _accent;

  AppSettings(this._prefs)
      : _themeMode = _readThemeMode(_prefs),
        _accent = _readAccent(_prefs);

  ThemeMode get themeMode => _themeMode;
  AppAccent get accent => _accent;

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    _prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  void setAccent(AppAccent accent) {
    if (accent == _accent) return;
    _accent = accent;
    _prefs.setString(_kAccent, accent.name);
    notifyListeners();
  }

  static ThemeMode _readThemeMode(SharedPreferences prefs) {
    final name = prefs.getString(_kThemeMode);
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  static AppAccent _readAccent(SharedPreferences prefs) {
    final name = prefs.getString(_kAccent);
    return AppAccent.values.firstWhere(
      (a) => a.name == name,
      orElse: () => AppAccent.green,
    );
  }
}
