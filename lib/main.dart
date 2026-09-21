import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_settings.dart';
import 'data/database.dart';
import 'domain/recurrence_engine.dart';
import 'services/alerts_coordinator.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  final settings = AppSettings(await SharedPreferences.getInstance());

  // Every startup chore below is best-effort, and none of them may stop the
  // app from starting.
  //
  // They used to run unguarded, on the reasoning that a loud crash is the
  // honest failure mode. On a release build on a phone that reasoning does not
  // hold: an exception here escapes main(), runApp is never reached, and the
  // user is left looking at a blank white screen with nothing to report and no
  // way back in — the app simply appears dead. Silent is the opposite of loud.
  //
  // So: catch, keep going, and carry the message into the UI where it can
  // actually be read and reported. The data itself is untouched either way.
  final failures = <String>[];

  Future<void> attempt(String what, Future<void> Function() work) async {
    try {
      await work();
    } catch (error, stack) {
      failures.add('$what: $error');
      // Still loud where anyone can hear it.
      debugPrint('startup step failed — $what: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  // Materialize any recurring transactions that came due while the app was
  // closed. This is the deterministic "catch-up" that replaces fragile
  // background scheduling — it runs on every cold start, and HomeScreen runs it
  // again on resume. Idempotent, so running it repeatedly is safe. This is also
  // the first thing to touch the database, so a failed schema migration
  // surfaces here.
  await attempt(
      'تحديث العمليات المتكررة', () => RecurrenceEngine(db).catchUp());

  // Re-arm the notification schedule and the icon badge from the fresh data.
  await attempt('تهيئة التنبيهات', NotificationService.init);
  await attempt('تحديث التنبيهات', () => refreshAlerts(db, settings));

  runApp(FloosApp(
    db: db,
    settings: settings,
    startupFailures: failures,
  ));
}
