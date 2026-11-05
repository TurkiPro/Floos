import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/ledger_balance.dart';
import 'package:floos/ui/debts_screen.dart';

/// Lend, get repaid, see it settled — through the real screens.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    // Left open on purpose — saves fire refreshAlerts without awaiting it.
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  testWidgets('lend money, record the repayment, and it settles',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: const MaterialApp(locale: Locale('ar'), home: DebtsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('لا توجد ديون'), findsOneWidget);

    // A new loan to Fahad.
    await tester.tap(find.text('دين جديد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'لمن؟'), 'فهد');
    await tester.enterText(find.widgetWithText(TextField, 'المبلغ'), '500');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('فهد'), findsOneWidget);
    expect(find.text('500.00 ⃁'), findsNWidgets(2)); // the row and the section

    final debts =
        (await tester.runAsync(() => db.debtDao.watchAllMovements().first))!;
    expect(debts.single.debt.direction, DebtDirection.lent);
    expect(debts.single.movement.amount, 500);

    // He pays it all back.
    await tester.tap(find.text('فهد'));
    await tester.pumpAndSettle();
    expect(find.text('متبقٍ لك: 500.00 ⃁'), findsOneWidget);
    await tester.tap(find.text('تسجيل سداد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'المبلغ'), '500');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('مسدّد بالكامل'), findsOneWidget);
    expect(find.text('سدّد لك'), findsOneWidget);
    final after =
        (await tester.runAsync(() => db.debtDao.watchAllMovements().first))!;
    expect(debtOutstanding(after).values.single, 0);

    // Back on the list it has moved under «مسدّدة».
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('مسدّدة (1)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
