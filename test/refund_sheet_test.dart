import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/ui/search_screen.dart';

/// Recording a refund by hand: tap a purchase, «تسجيل استرداد», save. The
/// purchase then reads as refunded and the refund as money back.
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

  testWidgets('refund a purchase in part, then in full', (tester) async {
    final purchaseId = await db.transactionDao.add(
      amount: 200,
      categoryId: 1,
      type: TxnType.expense,
      date: DateTime.now(),
      note: 'نمشي',
    );

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

    Future<void> refund(Finder purchase, String amount) async {
      await tester.tap(purchase);
      await tester.pumpAndSettle();
      await tester.tap(find.text('تسجيل استرداد'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'المبلغ المسترد'), amount);
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
    }

    await refund(find.text('نمشي'), '50');
    expect(find.textContaining('مسترد جزئيًا 50.00'), findsOneWidget);
    expect(find.text('+50.00 ⃁'), findsOneWidget);
    expect(find.text('-200.00 ⃁'), findsOneWidget);

    // The second refund defaults to what is left; take it all.
    await refund(find.textContaining('مسترد جزئيًا'), '150');
    expect(find.textContaining('مسترد بالكامل'), findsOneWidget);

    final rows = await db.select(db.transactions).get();
    final refunds = rows.where((t) => t.refundOf == purchaseId).toList();
    expect(refunds.map((t) => t.amount), containsAll([-50.0, -150.0]));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
