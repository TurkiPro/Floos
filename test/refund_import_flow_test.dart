import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/ui/import_screen.dart';

/// The live bug, through the real screens: a refund from a merchant the user
/// has an expense rule for used to be imported as a second purchase. Same
/// harness conventions as import_flow_test.dart.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  // A refund in the bank's format (see refunds_test.dart: no real refund
  // message has been collected yet).
  const refundSms = 'مرتجع شراء عبر نقاط بيع SAR 30\n'
      'بطاقة 1672* مدى- ApplePay\n'
      'من RED BOX\n'
      'في 10:15 26-09-14';

  testWidgets('a refund for a known merchant is saved as money back',
      (tester) async {
    await db.partyRuleDao.remember(
      rawParty: 'RED BOX',
      disposition: PartyDisposition.expense,
      categoryId: 1,
    );
    // The purchase being refunded, as an earlier import would have left it.
    final purchaseId = await db.transactionDao.add(
      amount: 30,
      categoryId: 1,
      type: TxnType.expense,
      date: DateTime(2026, 9, 12, 18, 57),
      note: 'RED BOX',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: const MaterialApp(locale: Locale('ar'), home: ImportScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, refundSms);
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    // Arrives resolved by the rule — as a refund, linked to the purchase.
    expect(find.text('استرداد'), findsOneWidget); // the decision button
    expect(find.text('استرداد لشراء 2026-09-12'), findsOneWidget);
    expect(find.text('+30 ⃁'), findsOneWidget);
    expect(find.textContaining('— -30 ⃁'), findsOneWidget,
        reason: 'the footer total nets the refund');

    await tester.tap(find.text('حفظ 1 عملية'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.transactions).get();
    final refund = rows.firstWhere((t) => t.id != purchaseId);
    expect(refund.amount, -30, reason: 'money back, never a second purchase');
    expect(refund.categoryId, 1);
    expect(refund.refundOf, purchaseId);
    expect(rows, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
