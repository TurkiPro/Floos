import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/theme/tokens.dart';

/// How often the "log your spending" reminder fires.
enum ReminderCadence { daily, everyOtherDay, weekly }

extension ReminderCadenceLabel on ReminderCadence {
  String get label => switch (this) {
        ReminderCadence.daily => 'يوميًا',
        ReminderCadence.everyOtherDay => 'كل يومين',
        ReminderCadence.weekly => 'أسبوعيًا',
      };
}

/// Which calendar dates are shown in.
enum CalendarSystem { gregorian, hijri }

extension CalendarSystemLabel on CalendarSystem {
  String get label => this == CalendarSystem.gregorian ? 'ميلادي' : 'هجري';
}

/// How generously the budgets page seeds its day-one suggestions from income,
/// before there's real spending history to learn from. Once history exists the
/// suggestions come from actual spending and this no longer applies.
enum SpendingStyle { frugal, balanced, comfortable }

extension SpendingStyleLabel on SpendingStyle {
  String get label => switch (this) {
        SpendingStyle.frugal => 'مقتصد',
        SpendingStyle.balanced => 'متوازن',
        SpendingStyle.comfortable => 'مريح',
      };

  /// Multiplier applied to the income-based seed.
  double get factor => switch (this) {
        SpendingStyle.frugal => 0.8,
        SpendingStyle.balanced => 1.0,
        SpendingStyle.comfortable => 1.2,
      };
}

/// Reactive holder for every user preference, backed by SharedPreferences. The
/// app root listens to this so a change re-themes/re-schedules immediately, and
/// the choices survive relaunch.
class AppSettings extends ChangeNotifier {
  static const _kThemeMode = 'themeMode';
  static const _kAccent = 'accent';
  static const _kSkippedDeposits = 'skippedDeposits';
  static const _kNotificationsEnabled = 'notificationsEnabled';
  static const _kReminderCadence = 'reminderCadence';
  static const _kReminderHour = 'reminderHour';
  static const _kReminderMinute = 'reminderMinute';
  static const _kNotifyWeeklyBudget = 'notifyWeeklyBudget';
  static const _kNotifyStats = 'notifyStats';
  static const _kNotifySalaryDay = 'notifySalaryDay';
  static const _kCalendar = 'calendar';
  static const _kSoundEnabled = 'soundEnabled';
  static const _kAppLockEnabled = 'appLockEnabled';
  static const _kBadgeWeeklyBudget = 'badgeWeeklyBudget';
  static const _kFont = 'font';
  static const _kBudgetStyle = 'budgetStyle';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  AppAccent _accent;
  AppFont _font;
  // Keys of the form "goalId:YYYY-MM" the user dismissed on the income-day
  // savings prompt, so it doesn't nag again that month for that goal.
  final Set<String> _skippedDeposits;

  bool _notificationsEnabled;
  ReminderCadence _reminderCadence;
  TimeOfDay _reminderTime;
  bool _notifyWeeklyBudget;
  bool _notifyStats;
  bool _notifySalaryDay;
  CalendarSystem _calendar;
  bool _soundEnabled;
  bool _appLockEnabled;
  bool _badgeWeeklyBudget;
  SpendingStyle _budgetStyle;

  AppSettings(this._prefs)
      : _themeMode = _readThemeMode(_prefs),
        _accent = _readAccent(_prefs),
        _skippedDeposits =
            (_prefs.getStringList(_kSkippedDeposits) ?? const []).toSet(),
        _notificationsEnabled = _prefs.getBool(_kNotificationsEnabled) ?? false,
        _reminderCadence = ReminderCadence.values.firstWhere(
          (c) => c.name == _prefs.getString(_kReminderCadence),
          orElse: () => ReminderCadence.daily,
        ),
        _reminderTime = TimeOfDay(
          hour: _prefs.getInt(_kReminderHour) ?? 21,
          minute: _prefs.getInt(_kReminderMinute) ?? 0,
        ),
        _notifyWeeklyBudget = _prefs.getBool(_kNotifyWeeklyBudget) ?? true,
        _notifyStats = _prefs.getBool(_kNotifyStats) ?? true,
        _notifySalaryDay = _prefs.getBool(_kNotifySalaryDay) ?? true,
        _calendar = CalendarSystem.values.firstWhere(
          (c) => c.name == _prefs.getString(_kCalendar),
          orElse: () => CalendarSystem.gregorian,
        ),
        _soundEnabled = _prefs.getBool(_kSoundEnabled) ?? true,
        _appLockEnabled = _prefs.getBool(_kAppLockEnabled) ?? false,
        _badgeWeeklyBudget = _prefs.getBool(_kBadgeWeeklyBudget) ?? false,
        _budgetStyle = _readBudgetStyle(_prefs),
        _font = _readFont(_prefs);

  ThemeMode get themeMode => _themeMode;
  AppAccent get accent => _accent;
  AppFont get fontChoice => _font;
  bool get notificationsEnabled => _notificationsEnabled;
  ReminderCadence get reminderCadence => _reminderCadence;
  TimeOfDay get reminderTime => _reminderTime;
  bool get notifyWeeklyBudget => _notifyWeeklyBudget;
  bool get notifyStats => _notifyStats;
  bool get notifySalaryDay => _notifySalaryDay;
  CalendarSystem get calendar => _calendar;
  bool get useHijri => _calendar == CalendarSystem.hijri;
  bool get soundEnabled => _soundEnabled;
  bool get appLockEnabled => _appLockEnabled;
  bool get badgeWeeklyBudget => _badgeWeeklyBudget;
  SpendingStyle get budgetStyle => _budgetStyle;

  /// Multiplier the budgets page applies to its income-based day-one seed.
  double get lifestyleFactor => _budgetStyle.factor;

  // ------------------------------------------------------ savings prompt

  static String _depositKey(int goalId, DateTime month) =>
      '$goalId:${month.year}-${month.month}';

  bool isDepositSkipped(int goalId, DateTime month) =>
      _skippedDeposits.contains(_depositKey(goalId, month));

  void skipDeposit(int goalId, DateTime month) {
    _skippedDeposits.add(_depositKey(goalId, month));
    _prefs.setStringList(_kSkippedDeposits, _skippedDeposits.toList());
    notifyListeners();
  }

  // ------------------------------------------------------------ setters

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

  void setFontChoice(AppFont font) {
    if (font == _font) return;
    _font = font;
    _prefs.setString(_kFont, font.name);
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    _prefs.setBool(_kNotificationsEnabled, value);
    notifyListeners();
  }

  void setReminderCadence(ReminderCadence cadence) {
    _reminderCadence = cadence;
    _prefs.setString(_kReminderCadence, cadence.name);
    notifyListeners();
  }

  void setReminderTime(TimeOfDay time) {
    _reminderTime = time;
    _prefs.setInt(_kReminderHour, time.hour);
    _prefs.setInt(_kReminderMinute, time.minute);
    notifyListeners();
  }

  void setNotifyWeeklyBudget(bool value) {
    _notifyWeeklyBudget = value;
    _prefs.setBool(_kNotifyWeeklyBudget, value);
    notifyListeners();
  }

  void setNotifyStats(bool value) {
    _notifyStats = value;
    _prefs.setBool(_kNotifyStats, value);
    notifyListeners();
  }

  void setNotifySalaryDay(bool value) {
    _notifySalaryDay = value;
    _prefs.setBool(_kNotifySalaryDay, value);
    notifyListeners();
  }

  void setCalendar(CalendarSystem calendar) {
    if (calendar == _calendar) return;
    _calendar = calendar;
    _prefs.setString(_kCalendar, calendar.name);
    notifyListeners();
  }

  void setSoundEnabled(bool value) {
    _soundEnabled = value;
    _prefs.setBool(_kSoundEnabled, value);
    notifyListeners();
  }

  void setAppLockEnabled(bool value) {
    _appLockEnabled = value;
    _prefs.setBool(_kAppLockEnabled, value);
    notifyListeners();
  }

  void setBadgeWeeklyBudget(bool value) {
    _badgeWeeklyBudget = value;
    _prefs.setBool(_kBadgeWeeklyBudget, value);
    notifyListeners();
  }

  void setBudgetStyle(SpendingStyle style) {
    if (style == _budgetStyle) return;
    _budgetStyle = style;
    _prefs.setString(_kBudgetStyle, style.name);
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

  static AppFont _readFont(SharedPreferences prefs) {
    final name = prefs.getString(_kFont);
    return AppFont.values.firstWhere(
      (f) => f.name == name,
      orElse: () => AppFont.plexArabic,
    );
  }

  static SpendingStyle _readBudgetStyle(SharedPreferences prefs) {
    final name = prefs.getString(_kBudgetStyle);
    return SpendingStyle.values.firstWhere(
      (s) => s.name == name,
      orElse: () => SpendingStyle.balanced,
    );
  }
}
