import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/spending_window.dart';
import 'package:floos/services/alerts_coordinator.dart';

// Default seeded categories: id 1 = طعام (expense, essential). Confirmed from
// the _defaultCategories order.
const essentialCat = 1;

// Most tests have no recurring income, so the cycle falls back to the calendar
// month: it starts 1 July, and weeks are anchored on that day. For now = 20 July
// the current week runs 15–21 July. A couple of tests add a salary dated the 1st
// (monthly), which keeps the very same 1 July–1 Aug cycle while giving the
// income-based budget a real number to work from.
final now = DateTime(2026, 7, 20);

void main() {
  test('weeks are anchored on the cycle start (payday), not a weekday', () {
    // Calendar-month fallback anchors on the 1st; 15 July is two whole weeks in.
    expect(cycleWeekStart(DateTime(2026, 7, 1), now), DateTime(2026, 7, 15));
  });

  test('spentThisWeek counts on/after the week start and on/before now only',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // In this week (15–21 July):
    await db.transactionDao.add(
      amount: 100,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 16),
    );
    await db.transactionDao.add(
      amount: 30,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 20), // today boundary, included
    );
    // Before the week start -> excluded from spentThisWeek:
    await db.transactionDao.add(
      amount: 999,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 14),
    );

    final budget = await computeWeeklyBudget(db, now);
    expect(budget.spentThisWeek, 130);
  });

  test('the weekly budget is disposable income, adapted by the cycle so far',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // A recurring salary (6000/mo on the 1st, keeping the cycle at 1 Jul–1 Aug)
    // and a recurring obligation (2000/mo). No savings, no discretionary spend.
    await db.recurrenceDao.add(
      title: 'راتب',
      amount: 6000,
      categoryId: essentialCat, // category is irrelevant to the budget
      type: TxnType.income,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 1),
    );
    await db.recurrenceDao.add(
      title: 'إيجار',
      amount: 2000,
      categoryId: essentialCat,
      type: TxnType.expense,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 1),
    );

    final budget = await computeWeeklyBudget(db, now);
    // Base = (6000 salary − 2000 obligations − 0 saved) ÷ the cycle's ~4.43
    // weeks, then adapted for the weeks already elapsed with nothing spent (the
    // unspent earlier weeks roll forward).
    final base = incomeWeeklyBase(
      salaryMonthly: 6000,
      obligationsMonthly: 2000,
      savedThisCycle: 0,
      periodStart: DateTime(2026, 7, 1),
      periodEnd: DateTime(2026, 8, 1),
    );
    final expected = adaptiveWeeklyBudget(
      recommended: base,
      spentBeforeThisWeek: 0,
      periodStart: DateTime(2026, 7, 1),
      periodEnd: DateTime(2026, 8, 1),
      now: now,
    );
    expect(budget.recommended, closeTo(expected, 1e-9));
    expect(budget.spentThisWeek, 0);
  });

  test('a transaction stamped today with a time of day still counts', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // A manual add defaults to DateTime.now() with a time — this must count
    // toward this week, not be dropped for being "after" today.
    await db.transactionDao.add(
      amount: 150,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 20, 14, 30),
    );

    final budget = await computeWeeklyBudget(db, now);
    expect(budget.spentThisWeek, 150);
  });

  test('income rows are ignored', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.transactionDao.add(
      amount: 200,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 16),
    );

    final before = await computeWeeklyBudget(db, now);

    // A large income in the same week must change nothing.
    await db.transactionDao.add(
      amount: 5000,
      categoryId: essentialCat,
      type: TxnType.income,
      date: DateTime(2026, 7, 16),
    );

    final after = await computeWeeklyBudget(db, now);
    expect(after.recommended, before.recommended);
    expect(after.spentThisWeek, before.spentThisWeek);
    expect(after.spentThisWeek, 200);
  });

  test('recurring (monthly-obligation) expenses are excluded from the budget',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // A discretionary expense this week.
    await db.transactionDao.add(
      amount: 100,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 16),
    );
    final before = await computeWeeklyBudget(db, now);

    // A recurring obligation (e.g. rent) that lands this week must not move
    // either figure: it's generated from a rule, so it carries a recurrenceId.
    final ruleId = await db.recurrenceDao.add(
      title: 'إيجار',
      amount: 3000,
      categoryId: essentialCat,
      type: TxnType.expense,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 1),
    );
    final rule = (await db.recurrenceDao.activeRules())
        .firstWhere((r) => r.id == ruleId);
    await db.transactionDao.insertGenerated(rule, DateTime(2026, 7, 16));

    final after = await computeWeeklyBudget(db, now);
    expect(after.spentThisWeek, before.spentThisWeek);
    expect(after.recommended, before.recommended);
    expect(after.spentThisWeek, 100);
  });

  test('the budget is capped at the real balance, not just cycle-remaining',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final at = DateTime(2026, 7, 28); // a few days before payday

    // Salary landed this cycle...
    await db.recurrenceDao.add(
      title: 'راتب',
      amount: 6000,
      categoryId: essentialCat,
      type: TxnType.income,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 1),
    );
    await db.transactionDao.add(
      amount: 6000,
      categoryId: essentialCat,
      type: TxnType.income,
      date: DateTime(2026, 7, 1),
    );
    // ...but a big spend in the PREVIOUS cycle drained the account. This cycle's
    // "remaining" still looks like 6000; the real balance is only 3000.
    await db.transactionDao.add(
      amount: 3000,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 6, 15),
    );

    final budget = await computeWeeklyBudget(db, at);
    // Bounded by the real balance (6000 − 3000), not the cycle-remaining (6000).
    expect(budget.recommended, lessThanOrEqualTo(3000));

    // The exact figure is set as at the START of the week, not today. 28 July
    // falls in the week that began 22 July, with 10 days to payday then, so the
    // real 3000 is spread across those 10: 3000 ÷ 10 × 7 = 2100. (This used to
    // read 3000, measured from 28 July itself — which is the very thing that
    // made the budget drift every day.)
    expect(budget.recommended, closeTo(2100, 1e-9));

    // And the near-payday rule still holds — it now takes effect from the start
    // of the final, short week rather than creeping in a day at a time. From 29
    // July only 3 days remain, so the whole real balance is this week's money.
    final finalWeek = await computeWeeklyBudget(db, DateTime(2026, 7, 29));
    expect(finalWeek.recommended, closeTo(3000, 1e-9));
  });

  test('overspending past the balance zeroes this week\'s budget', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // A salary that has actually landed (an income transaction, so there's a
    // real balance to cap against)...
    await db.recurrenceDao.add(
      title: 'راتب',
      amount: 6000,
      categoryId: essentialCat,
      type: TxnType.income,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 1),
    );
    await db.transactionDao.add(
      amount: 6000,
      categoryId: essentialCat,
      type: TxnType.income,
      date: DateTime(2026, 7, 1),
    );
    // ...then blowing more than the whole salary in an earlier week of the cycle.
    await db.transactionDao.add(
      amount: 7000,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 4), // before this week (15 July)
    );
    // A little spending this week.
    await db.transactionDao.add(
      amount: 50,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 16),
    );

    final budget = await computeWeeklyBudget(db, now);
    expect(budget.spentThisWeek, 50);
    expect(budget.recommended, 0,
        reason: 'nothing left for the rest of the cycle to budget');
    expect(budget.remaining, 0);
  });

  group('the week\'s budget holds still for the whole week', () {
    // The budget is the TARGET the week is measured against. It used to be
    // recomputed from today on every look, so it drifted on its own — upward
    // each day with nothing spent (fewer days left over the same balance), and
    // down each time something was logged. Someone reported it reading 1300,
    // then 1267 the next morning, in the same week, after a 40 riyal coffee.

    /// A salary that has landed and a real balance the cap can bite on: the
    /// exact conditions under which the drift happened.
    Future<AppDatabase> funded() async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.recurrenceDao.add(
        title: 'راتب',
        amount: 6000,
        categoryId: essentialCat,
        type: TxnType.income,
        frequency: Frequency.monthly,
        startDate: DateTime(2026, 7, 1),
      );
      await db.transactionDao.add(
        amount: 6000,
        categoryId: essentialCat,
        type: TxnType.income,
        date: DateTime(2026, 7, 1),
      );
      // Last cycle drained part of it, so the balance — not the salary — is
      // what the cap measures against.
      await db.transactionDao.add(
        amount: 3500,
        categoryId: essentialCat,
        type: TxnType.expense,
        date: DateTime(2026, 6, 15),
      );
      return db;
    }

    test('is identical on every day of the week when nothing is spent',
        () async {
      final db = await funded();
      // The week of 15–21 July.
      final figures = <double>[
        for (var d = 15; d <= 21; d++)
          (await computeWeeklyBudget(db, DateTime(2026, 7, d, 12))).recommended,
      ];
      for (final f in figures) {
        expect(f, closeTo(figures.first, 1e-9),
            reason: 'every day of one week must read the same budget: '
                '$figures');
      }
    });

    test('logging a purchase moves what was spent, never the budget', () async {
      final db = await funded();
      final before = await computeWeeklyBudget(db, DateTime(2026, 7, 16, 12));

      await db.transactionDao.add(
        amount: 40,
        categoryId: essentialCat,
        type: TxnType.expense,
        date: DateTime(2026, 7, 16, 9),
      );
      final sameDay = await computeWeeklyBudget(db, DateTime(2026, 7, 16, 12));
      final nextDay = await computeWeeklyBudget(db, DateTime(2026, 7, 17, 12));

      expect(sameDay.recommended, closeTo(before.recommended, 1e-9));
      expect(nextDay.recommended, closeTo(before.recommended, 1e-9),
          reason: 'the reported case: budget changed overnight after a 40');
      expect(sameDay.spentThisWeek, before.spentThisWeek + 40);
    });

    test('a savings deposit mid-week shrinks NEXT week, not this one',
        () async {
      final db = await funded();
      final goal = await db.savingsDao.addGoal(name: 'هدف', targetAmount: 1000);
      final before = await computeWeeklyBudget(db, DateTime(2026, 7, 16, 12));

      await db.savingsDao.addContribution(
          goalId: goal, amount: 300, date: DateTime(2026, 7, 17));
      final thisWeek = await computeWeeklyBudget(db, DateTime(2026, 7, 18, 12));
      final nextWeek = await computeWeeklyBudget(db, DateTime(2026, 7, 22, 12));

      expect(thisWeek.recommended, closeTo(before.recommended, 1e-9));
      expect(nextWeek.recommended, isNot(closeTo(before.recommended, 1e-9)),
          reason: 'the money set aside must still count — from the next week');
    });

    test('it is recalculated when a new week begins', () async {
      final db = await funded();
      await db.transactionDao.add(
        amount: 200,
        categoryId: essentialCat,
        type: TxnType.expense,
        date: DateTime(2026, 7, 16),
      );
      final lastDayOfWeek =
          await computeWeeklyBudget(db, DateTime(2026, 7, 21, 12));
      final firstDayOfNext =
          await computeWeeklyBudget(db, DateTime(2026, 7, 22, 12));
      expect(firstDayOfNext.recommended,
          isNot(closeTo(lastDayOfWeek.recommended, 1e-9)),
          reason: 'frozen within a week, not frozen forever');
    });

    test('still drops when the real balance falls below it', () async {
      // The one deliberate exception. A budget that says 1,000 when 200 is
      // left would be a lie, so the safety net still follows the balance down.
      final db = await funded();
      final before = await computeWeeklyBudget(db, DateTime(2026, 7, 16, 12));

      await db.transactionDao.add(
        amount: 2400, // leaves a real balance of 100
        categoryId: essentialCat,
        type: TxnType.expense,
        date: DateTime(2026, 7, 16, 9),
      );
      final after = await computeWeeklyBudget(db, DateTime(2026, 7, 16, 12));

      expect(before.recommended, greaterThan(100));
      expect(after.recommended, closeTo(100, 1e-9),
          reason: 'never name a figure larger than the money that exists');
    });
  });
}
