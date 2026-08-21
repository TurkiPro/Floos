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
    expect(budget.recommended, closeTo(3000, 1e-9));
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
}
