import 'package:flutter/material.dart';

import 'app.dart';
import 'data/database.dart';
import 'domain/recurrence_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();

  // Materialize any recurring transactions that came due while the app was
  // closed. This is the deterministic "catch-up" that replaces fragile
  // background scheduling — it runs on every cold start, and HomeScreen runs it
  // again on resume. Idempotent, so running it repeatedly is safe.
  await RecurrenceEngine(db).catchUp();

  runApp(FloosApp(db: db));
}
