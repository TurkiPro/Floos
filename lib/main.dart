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

  // Materialize any recurring transactions that came due while the app was
  // closed. This is the deterministic "catch-up" that replaces fragile
  // background scheduling — it runs on every cold start, and HomeScreen runs it
  // again on resume. Idempotent, so running it repeatedly is safe.
  await RecurrenceEngine(db).catchUp();

  // Re-arm the notification schedule and the icon badge from the fresh data.
  // Both are best-effort and no-op on platforms without support, so a failure
  // here can never stop the app from starting.
  await NotificationService.init();
  await refreshAlerts(db, settings);

  runApp(FloosApp(db: db, settings: settings));
}
