import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/services/alerts_coordinator.dart';

// Default seeded categories: id 1 = طعام (expense, essential),
// id 3 = تسوق (expense, luxury). Confirmed from _defaultCategories order.
const essentialCat = 1;
const luxuryCat = 3;

// A fixed Wednesday. The most recent Saturday (week start) is 2026-07-11.
final now = DateTime(2026, 7, 15);

void main() {
  test('week start is the most recent Saturday for the chosen now', () {
    // Guards the assumptions the other tests rely on.
    expect(now.weekday, DateTime.wednesday);
    expect(DateTime(2026, 7, 11).weekday, DateTime.saturday);
  });

  test('spentThisWeek counts on/after Saturday and on/before now only',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // In this week (Sat 2026-07-11 .. Wed 2026-07-15):
    await db.transactionDao.add(
      amount: 100,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 12),
    );
    await db.transactionDao.add(
      amount: 30,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 15), // today boundary, included
    );
    // Last week (before Saturday) -> excluded from spentThisWeek:
    await db.transactionDao.add(
      amount: 999,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 10),
    );

    final budget = await computeWeeklyBudget(db, now);
    expect(budget.spentThisWeek, 130);
  });

  test('recommended follows essential/weeks + (luxury/weeks) * 0.85', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Earliest at 2026-07-02 => windowDays = 14 => weeks = 2 (all within the
    // 84-day window, and all before the current week so spentThisWeek is 0).
    await db.transactionDao.add(
      amount: 200,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 2), // earliest
    );
    await db.transactionDao.add(
      amount: 100,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 5),
    );
    await db.transactionDao.add(
      amount: 400,
      categoryId: luxuryCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 8),
    );

    final budget = await computeWeeklyBudget(db, now);
    // essentialWindow 300 / 2 + (luxuryWindow 400 / 2) * 0.85 = 150 + 170.
    expect(budget.recommended, closeTo(320, 1e-9));
    expect(budget.spentThisWeek, 0);
  });

  test('a transaction stamped today with a time of day still counts', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // now is 2026-07-15 (midnight). A manual add defaults to DateTime.now()
    // with a time — this must count toward this week and the window, not be
    // dropped for being "after" today-at-midnight.
    await db.transactionDao.add(
      amount: 150,
      categoryId: essentialCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 15, 14, 30),
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
      date: DateTime(2026, 7, 12),
    );

    final before = await computeWeeklyBudget(db, now);

    // A large income in the same week must change nothing.
    await db.transactionDao.add(
      amount: 5000,
      categoryId: essentialCat,
      type: TxnType.income,
      date: DateTime(2026, 7, 12),
    );

    final after = await computeWeeklyBudget(db, now);
    expect(after.recommended, before.recommended);
    expect(after.spentThisWeek, before.spentThisWeek);
    expect(after.spentThisWeek, 200);
  });

  test('remaining clamps to 0 when spent exceeds recommended', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // A single luxury expense this week: it counts 100% toward spentThisWeek
    // but only 85% toward recommended, so spent > recommended.
    await db.transactionDao.add(
      amount: 500,
      categoryId: luxuryCat,
      type: TxnType.expense,
      date: DateTime(2026, 7, 12),
    );

    final budget = await computeWeeklyBudget(db, now);
    // weeks clamps to 1 (windowDays = 4). recommended = 500 * 0.85 = 425.
    expect(budget.recommended, closeTo(425, 1e-9));
    expect(budget.spentThisWeek, 500);
    expect(budget.spentThisWeek > budget.recommended, isTrue);
    expect(budget.remaining, 0);
  });
}
