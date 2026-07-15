import 'dart:math';

import 'database.dart';
import 'enums.dart';

/// Fills the database with ~6 months of realistic-looking transactions,
/// savings goals and contributions so the dashboard, month browser and
/// statistics have something to show. Triggered manually from Settings.
///
/// Clears existing transactions and savings first (but keeps the user's
/// categories and recurrence rules) so repeated runs give a clean demo rather
/// than piling up. Uses a fixed seed so the generated data is reproducible.
Future<void> seedDummyData(AppDatabase db) async {
  final rng = Random(42);
  final now = DateTime.now();

  // Transactions first: they carry a recurrenceId foreign key into the rules.
  await db.transactionDao.clearAll();
  await db.recurrenceDao.clearAll();
  await db.savingsDao.clearAll();
  await db.budgetDao.clearAll();

  final cats = await db.categoryDao.getAll();
  final expenseCats = cats
      .where(
          (c) => c.type == TxnType.expense && !c.archived && c.parentId == null)
      .toList();
  final incomeCats =
      cats.where((c) => c.type == TxnType.income && !c.archived).toList();
  if (expenseCats.isEmpty || incomeCats.isEmpty) return;

  final salary = incomeCats.firstWhere(
    (c) => c.iconKey == 'salary',
    orElse: () => incomeCats.first,
  );

  // Rough monthly frequency + amount range per expense category, keyed by the
  // seed icons; anything else falls back to a generic range.
  ({int count, double min, double max}) profileFor(String iconKey) {
    switch (iconKey) {
      case 'food':
        return (count: 18, min: 12, max: 130);
      case 'transport':
        return (count: 8, min: 10, max: 90);
      case 'bills':
        return (count: 3, min: 120, max: 650);
      case 'shopping':
        return (count: 4, min: 40, max: 450);
      case 'entertainment':
        return (count: 5, min: 25, max: 220);
      case 'health':
        return (count: 2, min: 30, max: 320);
      case 'home':
        return (count: 2, min: 90, max: 800);
      default:
        return (count: 3, min: 20, max: 160);
    }
  }

  double roundAmount(double v) => (v * 100).roundToDouble() / 100;

  // 6 months: current + 5 back, oldest first.
  for (var back = 5; back >= 0; back--) {
    final monthAnchor = DateTime(now.year, now.month - back, 1);
    final year = monthAnchor.year;
    final month = monthAnchor.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Don't generate future-dated expenses in the current month.
    final lastDay = back == 0 ? now.day : daysInMonth;

    // Salary on the 1st, with a little month-to-month variation.
    await db.transactionDao.add(
      amount: roundAmount((15500 + rng.nextInt(2500)).toDouble()),
      categoryId: salary.id,
      type: TxnType.income,
      date: DateTime(year, month, 1),
      note: 'راتب',
    );

    for (final cat in expenseCats) {
      final p = profileFor(cat.iconKey);
      for (var i = 0; i < p.count; i++) {
        final day = 1 + rng.nextInt(lastDay);
        final amount = roundAmount(p.min + rng.nextDouble() * (p.max - p.min));
        await db.transactionDao.add(
          amount: amount,
          categoryId: cat.id,
          type: TxnType.expense,
          date: DateTime(year, month, day),
        );
      }
    }
  }

  // A recurring salary rule, so the income screen shows a real recurring entry
  // rather than an empty state. The months above already have their salary
  // transactions, so the marker is parked at today: catch-up then generates
  // nothing retroactively and the rule simply comes due next month.
  final salaryRule = await db.recurrenceDao.add(
    title: 'راتب',
    amount: 17000,
    categoryId: salary.id,
    type: TxnType.income,
    frequency: Frequency.monthly,
    interval: 1,
    startDate: DateTime(now.year, now.month, 1),
    note: 'راتب',
  );
  await db.recurrenceDao.setLastMaterialized(salaryRule, now);

  // A couple of savings goals with deadlines and some history.
  final carGoal = await db.savingsDao.addGoal(
    name: 'سيارة جديدة',
    targetAmount: 60000,
    targetDate: DateTime(now.year, now.month + 8, 1),
  );
  final emergencyGoal = await db.savingsDao.addGoal(
    name: 'صندوق الطوارئ',
    targetAmount: 20000,
    targetDate: DateTime(now.year, now.month + 14, 1),
  );

  for (var back = 4; back >= 1; back--) {
    final d = DateTime(now.year, now.month - back, 3);
    await db.savingsDao.addContribution(
      goalId: carGoal,
      amount: 2000,
      date: d,
      note: 'إيداع شهري',
    );
    if (back.isEven) {
      await db.savingsDao.addContribution(
        goalId: emergencyGoal,
        amount: 1000,
        date: d,
        note: 'إيداع شهري',
      );
    }
  }

  // A few monthly budgets so the budgets screen isn't empty in the demo.
  const budgetByIcon = {'food': 2500.0, 'transport': 800.0, 'bills': 1500.0};
  for (final cat in expenseCats) {
    final amount = budgetByIcon[cat.iconKey];
    if (amount != null) await db.budgetDao.setBudget(cat.id, amount);
  }
}
