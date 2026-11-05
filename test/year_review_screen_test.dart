import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/ui/months_screen.dart';

/// The twelve-cycle review, reached from the cycles screen. The figures are
/// covered by year_review_test; this checks the wiring and that it renders.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  testWidgets('opens from the cycles screen and shows the totals',
      (tester) async {
    final now = DateTime.now();
    final payday = DateTime(now.year, now.month, 1);
    await db.recurrenceDao.add(
      title: 'راتب',
      amount: 10000,
      categoryId: 9,
      type: TxnType.income,
      frequency: Frequency.monthly,
      startDate: DateTime(now.year - 1, now.month, 1),
    );
    await db.transactionDao.add(
        amount: 10000, categoryId: 9, type: TxnType.income, date: payday);
    await db.transactionDao.add(
        amount: 2500, categoryId: 1, type: TxnType.expense, date: payday);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: const MaterialApp(locale: Locale('ar'), home: MonthsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ملخص آخر ١٢ دورة'));
    await tester.pumpAndSettle();

    expect(find.text('آخر ١٢ دورة'), findsOneWidget);
    expect(find.text('1 دورة حتى الآن'), findsOneWidget);
    expect(find.text('10,000 ⃁'), findsOneWidget);
    expect(find.textContaining('(جارية)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
