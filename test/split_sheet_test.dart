import 'package:drift/drift.dart' show driftRuntimeOptions, OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/ui/search_screen.dart';

/// Splitting from the UI: tap a purchase, choose split, file part of it
/// elsewhere, save; then reopen it and put it back together. The rules are
/// covered by split_transaction_test; this covers the wiring between the
/// row, the edit sheet and the split editor.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    // Left open on purpose — see import_flow_test.dart.
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  Future<List<Txn>> rows() => (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

  testWidgets('split a purchase, then put it back together', (tester) async {
    await db.categoryDao.add(
      name: 'منزل',
      iconKey: 'home',
      colorValue: 0xFF000000,
      type: TxnType.expense,
    );
    final groceries = (await db.categoryDao.getAll())
        .firstWhere((c) => c.id == 1 && c.type == TxnType.expense);
    await db.transactionDao.add(
      amount: 420,
      categoryId: groceries.id,
      type: TxnType.expense,
      date: DateTime.now(),
      note: 'بنده',
    );

    // The search screen lists every row with the shared TransactionRow.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: const MaterialApp(locale: Locale('ar'), home: SearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('بنده'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تقسيم على أكثر من فئة'));
    await tester.pumpAndSettle();

    expect(find.text('الإجمالي 420.00 ⃁'), findsOneWidget);
    await tester.tap(find.text('اختر فئة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('منزل').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'المبلغ'), '120');
    await tester.pumpAndSettle();
    expect(find.text('300.00'), findsOneWidget, reason: 'the first part '
        'takes whatever the others leave');

    await tester.tap(find.text('حفظ التقسيم'));
    await tester.pumpAndSettle();

    var saved = await rows();
    expect(saved.map((t) => t.amount), [300, 120]);
    expect(saved.every((t) => t.splitGroupId == saved.first.id), isTrue);
    expect(find.textContaining('جزء من عملية مقسّمة'), findsNWidgets(2));

    // Tapping a part opens the whole purchase, not a single-row editor.
    await tester.tap(find.textContaining('جزء من عملية مقسّمة').first);
    await tester.pumpAndSettle();
    expect(find.text('عملية مقسّمة'), findsOneWidget);
    await tester.tap(find.text('إلغاء التقسيم'));
    await tester.pumpAndSettle();

    saved = await rows();
    expect(saved.single.amount, 420);
    expect(saved.single.splitGroupId, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
