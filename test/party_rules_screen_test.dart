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

/// The saved-parties screen, reached the way the user reaches it: from the
/// import page. Same harness conventions as import_flow_test.dart.
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

  Future<void> openSavedParties(WidgetTester tester) async {
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
    final tile = find.textContaining('الجهات المحفوظة');
    await tester.dragUntilVisible(
        tile, find.byType(ListView).first, const Offset(0, -200));
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> seedTwo() async {
    await db.partyRuleDao.remember(
      rawParty: 'RED BOX',
      disposition: PartyDisposition.expense,
      categoryId: 1,
      displayName: 'ريد بوكس',
    );
    await db.partyRuleDao
        .remember(rawParty: 'KR-133', disposition: PartyDisposition.ignore);
  }

  testWidgets('lists each rule with its readable name and the bank string',
      (tester) async {
    await seedTwo();
    await openSavedParties(tester);

    expect(find.text('الجهات المحفوظة'), findsOneWidget); // app bar
    expect(find.text('ريد بوكس'), findsOneWidget);
    expect(find.text('RED BOX'), findsOneWidget,
        reason: 'the bank string stays visible under a given name');
    expect(find.text('KR-133'), findsOneWidget);
    expect(find.text('تجاهل'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('changing what a party means is saved', (tester) async {
    await seedTwo();
    await openSavedParties(tester);

    await tester.tap(find.text('ريد بوكس'));
    await tester.pumpAndSettle();
    expect(find.textContaining('على الاستيرادات القادمة فقط'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'تجاهل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    final rule = (await db.partyRuleDao.lookup('RED BOX'))!;
    expect(rule.disposition, PartyDisposition.ignore);
    expect(rule.categoryId, isNull);
    expect(rule.displayName, 'ريد بوكس');
    expect(find.text('تجاهل'), findsNWidgets(2));

    await teardownTree(tester);
  });

  testWidgets('forgetting a party asks first, then removes it', (tester) async {
    await seedTwo();
    await openSavedParties(tester);

    await tester.tap(find.text('KR-133'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نسيان هذه الجهة'));
    await tester.pumpAndSettle();

    expect(find.text('نسيان الجهة'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'نسيان'));
    await tester.pumpAndSettle();

    expect(await db.partyRuleDao.lookup('KR-133'), isNull);
    expect(await db.partyRuleDao.lookup('RED BOX'), isNotNull);
    expect(find.text('KR-133'), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('says so when nothing has been learned yet', (tester) async {
    await openSavedParties(tester);
    expect(find.textContaining('لم تُحفظ أي جهة بعد'), findsOneWidget);
    await teardownTree(tester);
  });
}
