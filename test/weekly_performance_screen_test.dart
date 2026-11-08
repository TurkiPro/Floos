import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/ui/weekly_performance_screen.dart';

/// The week in progress shows its seven-day chart from its first morning,
/// before anything is spent. It used to appear only once the week had some
/// spending, so on the first day of a week the card had no chart at all.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  testWidgets('a week with nothing spent yet still shows its seven days',
      (tester) async {
    // Payday today, so the cycle — and its first week — begins today.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await db.recurrenceDao.add(
      title: 'راتب',
      amount: 10000,
      categoryId: 9,
      type: TxnType.income,
      frequency: Frequency.monthly,
      startDate: DateTime(today.year - 1, today.month, today.day),
    );
    await db.transactionDao
        .add(amount: 10000, categoryId: 9, type: TxnType.income, date: today);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: const MaterialApp(
            locale: Locale('ar'), home: WeeklyPerformanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الإنفاق اليومي'), findsOneWidget,
        reason: 'the current week charts its days before any spending');
    for (var i = 0; i < 7; i++) {
      final day = DateTime(today.year, today.month, today.day + i).day;
      expect(find.text('$day'), findsWidgets,
          reason: 'day $day is on the axis');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
