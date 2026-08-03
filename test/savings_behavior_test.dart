import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/savings_behavior.dart';

// Salary on the 1st (monthly), now 15 July 2026 → current cycle [07-01, 08-01);
// the six completed cycles before it are the 1st-to-1st windows back to January.
final now = DateTime(2026, 7, 15);

RecurrenceRule _salary() => RecurrenceRule(
      id: 1,
      title: 'راتب',
      amount: 10000,
      categoryId: 9,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: DateTime(2026, 1, 1),
      active: true,
    );

Category _incCat() => const Category(
      id: 9,
      name: 'راتب',
      iconKey: 'k',
      colorValue: 0,
      type: TxnType.income,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
      parentId: null,
    );

TxnRow _income(double amount, DateTime date) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: 9,
        type: TxnType.income,
        date: date,
        createdAt: date,
      ),
      category: _incCat(),
    );

SavingsContribution _contrib(double amount, DateTime date,
        {bool external = false}) =>
    SavingsContribution(
        id: 1, goalId: 1, amount: amount, date: date, external: external);

void main() {
  group('savingsBehavior', () {
    final rows = [
      _income(10000, DateTime(2026, 2, 1)),
      _income(10000, DateTime(2026, 3, 1)),
      _income(10000, DateTime(2026, 4, 1)),
      _income(10000, DateTime(2026, 5, 1)),
      _income(10000, DateTime(2026, 6, 1)),
      _income(10000, DateTime(2026, 7, 1)), // current cycle
    ];
    final contributions = [
      _contrib(2000, DateTime(2026, 2, 5)),
      _contrib(3000, DateTime(2026, 3, 5)),
      _contrib(1000, DateTime(2026, 4, 5)),
      _contrib(-500, DateTime(2026, 5, 5)), // a withdrawal cycle
      _contrib(2000, DateTime(2026, 6, 5)),
      _contrib(2500, DateTime(2026, 7, 5)), // current cycle
      _contrib(50000, DateTime(2026, 2, 6), external: true), // ignored
    ];

    SavingsBehavior run() => savingsBehavior(
          contributions: contributions,
          rows: rows,
          incomeRules: [_salary()],
          now: now,
        );

    test('this cycle: saved amount and rate, external deposits ignored', () {
      final b = run();
      expect(b.savedThisCycle, 2500);
      expect(b.rateThisCycle, closeTo(0.25, 1e-9)); // 2500 / 10000
    });

    test('median per cycle and usual rate come from past active cycles', () {
      final b = run();
      // Past saved: Jun 2000, May −500, Apr 1000, Mar 3000, Feb 2000.
      expect(b.medianPerCycle, closeTo(2000, 1e-9));
      // Rates: 0.2, −0.05, 0.1, 0.3, 0.2 → median 0.2.
      expect(b.usualRate, closeTo(0.2, 1e-9));
    });

    test('streak counts the current cycle plus back to the first miss', () {
      // Jul +2500 (current) and Jun +2000, then May −500 breaks it.
      expect(run().streak, 2);
    });

    test('consistency counts saved cycles among the active ones', () {
      final b = run();
      expect(b.consistencyTotal, 5); // Feb..Jun active
      expect(b.consistencySaved, 4); // all but the May withdrawal cycle
    });

    test('best cycle is the highest net-positive one', () {
      final b = run();
      expect(b.bestCycleAmount, 3000);
      expect(b.bestCycleStart, DateTime(2026, 3, 1));
    });

    test('withdrawals sum the money pulled out and the down cycles', () {
      final b = run();
      expect(b.withdrawnRecently, 500);
      expect(b.withdrawalCycles, 1);
    });

    test('trend is oldest→newest and flags the current cycle', () {
      final b = run();
      expect(b.trend.map((p) => p.saved).toList(),
          [2000, 3000, 1000, -500, 2000, 2500]);
      expect(b.trend.first.cycleStart, DateTime(2026, 2, 1));
      expect(b.trend.last.current, isTrue);
      expect(b.trend.last.cycleStart, DateTime(2026, 7, 1));
    });

    test('a brand-new user (no past activity) has no history', () {
      final b = savingsBehavior(
        contributions: [_contrib(300, DateTime(2026, 7, 5))],
        rows: [_income(10000, DateTime(2026, 7, 1))],
        incomeRules: [_salary()],
        now: now,
      );
      expect(b.hasHistory, isFalse);
      expect(b.savedThisCycle, 300);
      expect(b.streak, 1); // saved this cycle
    });
  });
}
