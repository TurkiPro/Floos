import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/ui/recurring_screen.dart';

/// The obligations screen's twelve-month figure and its cost sort. The
/// counting itself is covered by recurring_cost_test.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  testWidgets('shows the real 12-month cost and can sort by it',
      (tester) async {
    final today = DateTime.now();
    DateTime inDays(int n) => DateTime(today.year, today.month, today.day + n);
    await db.recurrenceDao.add(
        title: 'نتفليكس',
        amount: 100,
        categoryId: 1,
        type: TxnType.expense,
        frequency: Frequency.monthly,
        startDate: inDays(1)); // 12 charges = 1,200
    await db.recurrenceDao.add(
        title: 'تأمين',
        amount: 1500,
        categoryId: 1,
        type: TxnType.expense,
        frequency: Frequency.yearly,
        startDate: inDays(2)); // 1 charge = 1,500

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: const MaterialApp(
            locale: Locale('ar'), home: ObligationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Not 1,600 (the two amounts added together, as the old header did).
    expect(find.text('2,700.00 ⃁'), findsOneWidget);
    expect(find.text('225.00 ⃁'), findsOneWidget); // per cycle ≈ 2,700 / 12

    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(top('نتفليكس'), lessThan(top('تأمين')),
        reason: 'by default the soonest charge is first');

    await tester.tap(find.byTooltip('الترتيب حسب التكلفة'));
    await tester.pumpAndSettle();
    expect(top('تأمين'), lessThan(top('نتفليكس')),
        reason: 'by cost, the 1,500 a year insurance beats 1,200 of Netflix');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
