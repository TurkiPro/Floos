import 'dart:io';

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

/// Drives the real import screens end to end: paste, review, resolve, save,
/// then undo. The logic is covered by import_review_test and import_batch_test;
/// this covers the wiring between them and the UI, which is where a feature
/// like this actually breaks.
void main() {
  // Each test builds its own in-memory database and leaves it open (see setUp).
  // They never share a QueryExecutor, so drift's warning does not apply.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    // Deliberately NOT closed in a tearDown. Saving and undoing both fire
    // refreshAlerts without awaiting it (the same pattern the add sheet uses),
    // and that reads drift streams — closing the database out from under it
    // ends those streams empty and throws after the test has finished. The
    // databases here are in-memory and the process is short-lived.
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  String fixture(String name) =>
      File('test/fixtures/bank_sms/$name').readAsStringSync();

  Future<void> pumpImport(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          home: ImportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Unmounts and lets drift's zero-duration stream cleanup timer fire, so the
  /// pending-timer check doesn't fail a test that is actually fine. Same reason
  /// as widget_test.dart.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('pasting shows a count and opens the review screen',
      (tester) async {
    await pumpImport(tester);

    expect(find.text('لا يوجد استيراد سابق'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField).first, fixture('sample_01.txt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('تم العثور على 8'), findsOneWidget);

    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    expect(find.text('مراجعة العمليات'), findsOneWidget);
    // Every merchant is unknown on a first import, so nothing is pre-selected
    // and saving is unavailable until the user says what these parties mean.
    expect(find.text('حفظ 0 عملية'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('RED BOX'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('a full round trip: resolve, save, then undo', (tester) async {
    // One remembered merchant so the row arrives pre-resolved and checked.
    await db.partyRuleDao.remember(
      rawParty: 'RED BOX',
      disposition: PartyDisposition.expense,
      categoryId: 1,
      displayName: 'ريد بوكس',
    );

    await pumpImport(tester);
    await tester.enterText(
        find.byType(TextField).first, fixture('sample_01.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    // The remembered party shows its readable name, not the bank's string.
    expect(find.text('ريد بوكس'), findsOneWidget);
    expect(find.text('حفظ 1 عملية'), findsOneWidget);

    await tester.tap(find.text('حفظ 1 عملية'));
    await tester.pumpAndSettle();

    // Back on the import page, with the batch listed.
    expect(find.text('استيراد من رسائل البنك'), findsOneWidget);
    final txns = await db.select(db.transactions).get();
    expect(txns, hasLength(1));
    expect(txns.single.amount, 30);
    expect(txns.single.note, 'ريد بوكس');
    expect(txns.single.importBatchId, isNotNull);
    expect(txns.single.recurrenceId, isNull);

    // Undo the batch.
    await tester.pumpAndSettle();
    expect(find.text('تراجع'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();

    expect(find.text('التراجع عن الاستيراد'), findsOneWidget);
    expect(find.textContaining('1 عملية'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'تراجع'));
    await tester.pumpAndSettle();

    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await db.select(db.importBatches).get(), isEmpty);

    await teardownTree(tester);
  });

  testWidgets('re-pasting an imported batch selects nothing', (tester) async {
    await db.partyRuleDao.remember(
      rawParty: 'RED BOX',
      disposition: PartyDisposition.expense,
      categoryId: 1,
    );

    await pumpImport(tester);
    await tester.enterText(
        find.byType(TextField).first, fixture('sample_01.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ 1 عملية'));
    await tester.pumpAndSettle();

    // Paste exactly the same blob again.
    await tester.enterText(
        find.byType(TextField).first, fixture('sample_01.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    // The already-imported row is flagged and unchecked, and still visible.
    expect(find.text('مسجّلة من قبل'), findsOneWidget);
    expect(find.text('حفظ 0 عملية'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: 'nothing is selected, so saving is unavailable',
    );
    expect(find.text('RED BOX'), findsOneWidget,
        reason: 'a duplicate is shown, never dropped');

    await teardownTree(tester);
  });

  testWidgets('a top-up resolved as ignore writes nothing', (tester) async {
    await db.partyRuleDao.remember(
      rawParty: 'ابل باي',
      disposition: PartyDisposition.ignore,
    );

    await pumpImport(tester);
    // sample_02 holds the two إضافة اموال top-ups and one transfer.
    await tester.enterText(
        find.byType(TextField).first, fixture('sample_02.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    // The top-ups have no party line, so they stay unresolved rather than being
    // guessed at — the ledger must not gain a 600 SAR "expense".
    expect(find.textContaining('اختر التصنيف'), findsWidgets);
    expect(await db.select(db.transactions).get(), isEmpty);

    await teardownTree(tester);
  });
}
