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

/// The search screen against a real (in-memory) database. The matching rules
/// are covered by txn_search_test; this covers the wiring — typing, the
/// summary, and that a result row is the real row, delete and all.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    // Left open on purpose — see import_flow_test.dart (deleting fires
    // refreshAlerts without awaiting it).
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  Future<void> pumpSearch(WidgetTester tester) async {
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
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> seed() async {
    final today = DateTime.now();
    await db.transactionDao.add(
        amount: 30,
        categoryId: 1,
        type: TxnType.expense,
        date: today,
        note: 'RED BOX');
    await db.transactionDao.add(
        amount: 87,
        categoryId: 1,
        type: TxnType.expense,
        date: today,
        note: 'جاهز');
  }

  Future<void> typeQuery(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump(const Duration(milliseconds: 200)); // past the debounce
    await tester.pumpAndSettle();
  }

  testWidgets('typing narrows the results and the summary follows',
      (tester) async {
    await seed();
    await pumpSearch(tester);

    expect(find.text('2 عملية · مصروفات 117.00 ⃁'), findsOneWidget);

    await typeQuery(tester, 'red box');
    expect(find.text('RED BOX'), findsOneWidget);
    expect(find.text('جاهز'), findsNothing);
    expect(find.text('1 عملية · مصروفات 30.00 ⃁'), findsOneWidget);

    await typeQuery(tester, '٨٧');
    expect(find.text('جاهز'), findsOneWidget);
    expect(find.text('RED BOX'), findsNothing);

    await typeQuery(tester, 'لا شيء يطابق هذا');
    expect(find.text('لا توجد عمليات مطابقة'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('a result can be swiped away like anywhere else',
      (tester) async {
    await seed();
    await pumpSearch(tester);
    await typeQuery(tester, 'red box');

    await tester.drag(find.text('RED BOX'), const Offset(600, 0));
    await tester.pumpAndSettle();

    final left = await db.select(db.transactions).get();
    expect(left.map((t) => t.note), ['جاهز']);
    expect(find.text('RED BOX'), findsNothing);
    expect(find.text('لا توجد عمليات مطابقة'), findsOneWidget,
        reason: 'the results follow the ledger');

    await teardownTree(tester);
  });
}
