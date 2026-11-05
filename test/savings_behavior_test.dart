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
        {bool external = false, bool planned = false}) =>
    SavingsContribution(
        id: 1,
        goalId: 1,
        amount: amount,
        date: date,
        external: external,
        planned: planned);

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

  group('countsAsSavingHabit', () {
    final d = DateTime(2026, 7, 5);

    test('deposits count unless external', () {
      expect(countsAsSavingHabit(_contrib(500, d)), isTrue);
      expect(countsAsSavingHabit(_contrib(500, d, external: true)), isFalse,
          reason: 'money that already existed is not a habit');
    });

    test('withdrawals count unless planned — in all four combinations', () {
      // back to balance, unplanned: raided it to cover spending
      expect(countsAsSavingHabit(_contrib(-500, d)), isTrue);
      // back to balance, planned: moved it back on purpose
      expect(countsAsSavingHabit(_contrib(-500, d, planned: true)), isFalse);
      // elsewhere, unplanned: raided it for something untracked
      expect(countsAsSavingHabit(_contrib(-500, d, external: true)), isTrue,
          reason: 'leaving the balance out does not make it not a lapse');
      // elsewhere, planned: the car fund paid for the car
      expect(
          countsAsSavingHabit(_contrib(-500, d, external: true, planned: true)),
          isFalse);
    });
  });

  group('a planned withdrawal is not scored as a lapse', () {
    final rows = [
      _income(10000, DateTime(2026, 6, 1)),
      _income(10000, DateTime(2026, 7, 1)),
    ];

    SavingsBehavior behave(List<SavingsContribution> c) => savingsBehavior(
          contributions: c,
          rows: rows,
          incomeRules: [_salary()],
          now: now,
        );

    test('it is left out of "withdrawn recently"', () {
      final planned = behave([
        _contrib(3000, DateTime(2026, 6, 5)),
        _contrib(-2000, DateTime(2026, 7, 5), planned: true),
      ]);
      final lapse = behave([
        _contrib(3000, DateTime(2026, 6, 5)),
        _contrib(-2000, DateTime(2026, 7, 5)),
      ]);

      expect(planned.withdrawnRecently, 0);
      expect(lapse.withdrawnRecently, 2000);
    });

    test('it does not turn a cycle net-negative or break the streak', () {
      // June: saved 3000. July: saved 500, then used 2000 of the goal as
      // intended. Unplanned, July ends 1500 down and the streak breaks;
      // planned, July is a 500 saving cycle like any other.
      final planned = behave([
        _contrib(3000, DateTime(2026, 6, 5)),
        _contrib(500, DateTime(2026, 7, 3)),
        _contrib(-2000, DateTime(2026, 7, 5), planned: true),
      ]);
      final lapse = behave([
        _contrib(3000, DateTime(2026, 6, 5)),
        _contrib(500, DateTime(2026, 7, 3)),
        _contrib(-2000, DateTime(2026, 7, 5)),
      ]);

      expect(planned.savedThisCycle, 500);
      expect(lapse.savedThisCycle, -1500);
      expect(planned.streak, greaterThan(lapse.streak));
    });

    test('an UNPLANNED external withdrawal still counts as dipping', () {
      // The money never came back to the balance, but it was still taken out
      // of savings for something other than the goal.
      final b = behave([
        _contrib(3000, DateTime(2026, 6, 5)),
        _contrib(-2000, DateTime(2026, 7, 5), external: true),
      ]);
      expect(b.withdrawnRecently, 2000);
    });
  });
}
