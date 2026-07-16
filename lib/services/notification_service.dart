import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../app_settings.dart';

/// Local reminders and alerts. Everything is best-effort: the plugin only has
/// real implementations on mobile/macOS, so on other targets (and if the user
/// denies permission) every call quietly no-ops rather than throwing.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Notification IDs, one per alert kind, so rescheduling replaces cleanly.
  static const _idReminder = 1;
  static const _idWeeklyBudget = 2;
  static const _idStats = 3;
  static const _idSalary = 4;

  static bool get supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks the OS for permission. Returns false when unavailable or denied.
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      final darwin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await darwin?.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // presentBadge:false + no badgeNumber => a reminder never touches the app
  // icon badge. The badge is owned solely by BadgeService (the weekly-budget
  // figure), so notifications can't bundle a count into it. On Android the
  // channel is set to not show a badge dot for the same reason.
  static NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          'floos_alerts',
          'تنبيهات فلوس',
          channelDescription: 'تذكيرات تسجيل المصاريف وتنبيهات الميزانية',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          channelShowBadge: false,
        ),
        iOS: DarwinNotificationDetails(presentBadge: false),
        macOS: DarwinNotificationDetails(presentBadge: false),
      );

  /// Rebuilds the whole schedule from the current settings. Called on launch
  /// and whenever a notification setting changes, so the schedule can never
  /// drift out of sync with what the user asked for.
  ///
  /// [nextSalary] and [weeklyBudget] come from live data (the recurring income
  /// rules and the spending stats) so the salary/budget alerts can be dated and
  /// worded concretely.
  static Future<void> reschedule(
    AppSettings settings, {
    DateTime? nextSalary,
    double? weeklyBudget,
  }) async {
    if (!supported) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!settings.notificationsEnabled) return;

      final time = settings.reminderTime;

      // 1. The core "log your spending" reminder.
      switch (settings.reminderCadence) {
        case ReminderCadence.daily:
          await _scheduleRepeating(
            id: _idReminder,
            title: 'سجّل مصاريفك',
            body: 'لا تنسَ تحديث مصاريف اليوم في فلوس.',
            when: _nextInstanceOfTime(time.hour, time.minute),
            match: DateTimeComponents.time,
          );
          break;
        case ReminderCadence.weekly:
          // Anchored to a fixed weekday: reschedule() runs on every
          // launch/resume, and an anchor of "today-or-tomorrow" + weekly
          // matching would re-arm the reminder to fire within 24h every time
          // — i.e. daily. Sunday avoids stacking on the Saturday budget alert
          // and the Friday stats nudge.
          await _scheduleRepeating(
            id: _idReminder,
            title: 'سجّل مصاريف أسبوعك',
            body: 'خصّص دقيقة لتحديث مصاريف هذا الأسبوع.',
            when:
                _nextInstanceOfWeekday(DateTime.sunday, time.hour, time.minute),
            match: DateTimeComponents.dayOfWeekAndTime,
          );
          break;
        case ReminderCadence.everyOtherDay:
          // The OS can't repeat on a 2-day cycle, so schedule the next one and
          // re-arm on the following launch (the app reschedules on every start).
          final next = _nextInstanceOfTime(time.hour, time.minute)
              .add(const Duration(days: 1));
          await _scheduleOnce(
            id: _idReminder,
            title: 'سجّل مصاريفك',
            body: 'مرّ يومان — حدّث مصاريفك في فلوس.',
            when: next,
          );
          break;
      }

      // 2. Weekly budget ready (Saturday, start of the week).
      if (settings.notifyWeeklyBudget) {
        final body = weeklyBudget == null
            ? 'ميزانية الأسبوع الجديدة جاهزة.'
            : 'ميزانيتك لهذا الأسبوع: ${weeklyBudget.toStringAsFixed(0)} ر.س.';
        await _scheduleRepeating(
          id: _idWeeklyBudget,
          title: 'ميزانية الأسبوع',
          body: body,
          when:
              _nextInstanceOfWeekday(DateTime.saturday, time.hour, time.minute),
          match: DateTimeComponents.dayOfWeekAndTime,
        );
      }

      // 3. Weekly nudge to look at the statistics.
      if (settings.notifyStats) {
        await _scheduleRepeating(
          id: _idStats,
          title: 'تعال شوف إحصائياتك!',
          body: 'اطّلع على ملخص إنفاقك ومعدل ادخارك هذا الأسبوع.',
          when: _nextInstanceOfWeekday(DateTime.friday, time.hour, time.minute),
          match: DateTimeComponents.dayOfWeekAndTime,
        );
      }

      // 4. Salary day (one-off; re-armed each launch from the live rules).
      if (settings.notifySalaryDay && nextSalary != null) {
        final when = tz.TZDateTime(
          tz.local,
          nextSalary.year,
          nextSalary.month,
          nextSalary.day,
          time.hour,
          time.minute,
        );
        if (when.isAfter(tz.TZDateTime.now(tz.local))) {
          await _scheduleOnce(
            id: _idSalary,
            title: 'يوم الراتب!',
            body: 'وصل دخلك — وزّعه على أهدافك وميزانيتك.',
            when: when,
          );
        }
      }
    } catch (_) {
      // Scheduling is best-effort; never break app start over it.
    }
  }

  static Future<void> cancelAll() async {
    if (!supported || !_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static Future<void> _scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required DateTimeComponents match,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: match,
    );
  }

  static Future<void> _scheduleOnce({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  static tz.TZDateTime _nextInstanceOfWeekday(
      int weekday, int hour, int minute) {
    var when = _nextInstanceOfTime(hour, minute);
    while (when.weekday != weekday) {
      when = when.add(const Duration(days: 1));
    }
    return when;
  }
}
