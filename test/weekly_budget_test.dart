import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/spending_window.dart';
import 'package:floos/services/alerts_coordinator.dart';

// Default seeded categories: id 1 = طعام (expense, essential),
// id 3 = تسوق (expense, luxury). Confirmed from _defaultCategories order.
const essentialCat = 1;
const luxuryCat = 3;

// No recurring income in these tests, so the cycle falls back to the calendar
// month: the cycle starts 1 July, and weeks are anchored on that day. For
// now = 20 July the current week runs 15–21 July.
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

  test('recommended is the flat baseline adapted by the cycle so far',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Earliest at 2026-07-07 => windowDays = 14 => weeks = 2 (all within the
    // 84-day window, and all before the current week so spentThisWeek is 0).
    await db.transactionDao.add(
      amount: 200,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 7), // earliest
    );
    await db.transactionDao.add(
      amount: 100,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 9),
    );
    await db.transactionDao.add(
      amount: 400,
      categoryId: luxuryCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 13),
    );

    final budget = await computeWeeklyBudget(db, now);
    // Flat baseline = essential 300/2 + (luxury 400/2)*0.85 = 320. All three
    // expenses fell before this week (700 spent), so that deficit lowers the
    // adaptive weekly budget.
    final expected = adaptiveWeeklyBudget(
      recommended: 320,
      spentBeforeThisWeek: 700,
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
    // toward this week and the window, not be dropped for being "after" today.
    await db.transactionDao.add(
      amount: 150,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 20, 14, 30),
    );

    final budget = await computeWeeklyBudget(db, now);
    expect(budget.spentThisWeek, 150);
    expect(budget.recommended, greaterThan(0));
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

  test('heavy overspend earlier in the cycle zeroes this week\'s budget',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // A long, light history sets a low weekly baseline...
    await db.transactionDao.add(
      amount: 20,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 5, 1),
    );
    // ...then a heavy spend in a prior week THIS cycle blows way past it.
    await db.transactionDao.add(
      amount: 2000,
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
        reason: 'prior overspend leaves nothing for the rest of the cycle');
    expect(budget.remaining, 0);
  });
}
