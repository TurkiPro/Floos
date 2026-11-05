import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/ui/add_contribution_sheet.dart';

/// Withdrawing from savings without the money landing in the balance — for
/// when it was spent straight from the savings account, or moved somewhere this
/// app does not track. The "external" toggle used to be hidden for withdrawals
/// and forced off on save.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late int goalId;

  setUp(() async {
    // Left open on purpose, as in import_flow_test: closing it under a widget
    // tree that still holds streams ends them empty after the test.
    db = AppDatabase.forTesting(NativeDatabase.memory());
    goalId = await db.savingsDao.addGoal(name: 'سيارة', targetAmount: 50000);
    // Something to withdraw against: the sheet refuses to take out more than
    // the goal holds.
    await db.savingsDao.addContribution(
      goalId: goalId,
      amount: 1000,
      date: DateTime(2026, 11, 1),
    );
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      home: Scaffold(body: AddContributionSheet(db: db, goalId: goalId)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  /// Reads outside the fake-async clock: a drift query never resolves inside
  /// testWidgets' fake time, so both the save and this read need real time.
  Future<List<SavingsContribution>> contributions(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.savingsContributions).get()))!;

  /// Taps save and lets the sheet's real async work finish. _save awaits a
  /// drift query (the can't-withdraw-more-than-the-goal-holds check), which
  /// hangs forever under fake time.
  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('حفظ'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the external option is offered when withdrawing',
      (tester) async {
    await pumpSheet(tester);
    expect(find.text('إيداع خارجي (لا يُخصم من الرصيد)'), findsOneWidget);

    await tester.tap(find.text('سحب'));
    await tester.pumpAndSettle();

    expect(find.text('سحب خارجي (لا يُضاف إلى الرصيد)'), findsOneWidget,
        reason: 'used to be hidden entirely in withdraw mode');
    expect(find.text('إيداع خارجي (لا يُخصم من الرصيد)'), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('an external withdrawal is saved negative AND external',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('سحب'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '400');
    await tester.tap(find.text('سحب خارجي (لا يُضاف إلى الرصيد)'));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = (await contributions(tester)).firstWhere((c) => c.amount < 0);
    expect(saved.amount, -400);
    expect(saved.external, isTrue,
        reason: 'save used to force external=false for every withdrawal');

    await teardownTree(tester);
  });

  testWidgets('a plain withdrawal still goes back to the balance',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('سحب'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '400');
    await save(tester);

    final saved = (await contributions(tester)).firstWhere((c) => c.amount < 0);
    expect(saved.external, isFalse, reason: 'off by default, as before');

    await teardownTree(tester);
  });

  testWidgets('the planned option exists only for withdrawals', (tester) async {
    const plannedLabel = 'سحب مخطط له (لا يُحسب تراجعًا في الادخار)';
    await pumpSheet(tester);
    expect(find.text(plannedLabel), findsNothing,
        reason: 'a deposit cannot be "the goal used as intended"');

    await tester.tap(find.text('سحب'));
    await tester.pumpAndSettle();
    expect(find.text(plannedLabel), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('a planned withdrawal is saved planned, independent of external',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('سحب'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '300');
    // Planned, but NOT external: moved back to the balance on purpose.
    await tester.tap(find.text('سحب مخطط له (لا يُحسب تراجعًا في الادخار)'));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = (await contributions(tester)).firstWhere((c) => c.amount < 0);
    expect(saved.planned, isTrue);
    expect(saved.external, isFalse, reason: 'the two flags are independent');

    await teardownTree(tester);
  });

  testWidgets('switching direction clears the toggle', (tester) async {
    // "Money I already had" and "money that went elsewhere" are different
    // claims. A tick made as a deposit must not silently become an external
    // withdrawal because the user changed their mind about the direction.
    await pumpSheet(tester);
    await tester.tap(find.text('إيداع خارجي (لا يُخصم من الرصيد)'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);

    await tester.tap(find.text('سحب'));
    await tester.pumpAndSettle();

    // Withdraw mode has two switches now (external, planned). Both must start
    // off: the external tick was cleared, and planned is never inherited.
    final switches =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches, hasLength(2));
    expect(switches.every((s) => !s.value), isTrue);

    await teardownTree(tester);
  });
}
