import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/statistics_summary.dart';

// A fixed "now" so month/window math is deterministic.
final now = DateTime(2026, 7, 15);

Category _cat({
  int id = 1,
  TxnType type = TxnType.expense,
  CategoryKind kind = CategoryKind.essential,
  int? parentId,
}) =>
    Category(
      id: id,
      name: 'c$id',
      iconKey: 'k',
      colorValue: 0,
      type: type,
      kind: kind,
      archived: false,
      sortOrder: 0,
      parentId: parentId,
    );

TxnRow _row(Category cat, double amount, DateTime date) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: cat.id,
        type: cat.type,
        date: date,
        createdAt: date,
      ),
      category: cat,
    );

TxnRow _expense(double amount, DateTime date,
        {CategoryKind kind = CategoryKind.essential,
        int id = 1,
        int? parentId}) =>
    _row(_cat(id: id, kind: kind, parentId: parentId), amount, date);

TxnRow _income(double amount, DateTime date) =>
    _row(_cat(id: 9, type: TxnType.income), amount, date);

SavingsContribution _contrib(double amount, DateTime date,
        {bool external = false}) =>
    SavingsContribution(
        id: 1, goalId: 1, amount: amount, date: date, external: external);

void main() {
  group('StatisticsSummary.from', () {
    test('allExpenseCount is zero for income-only input (drives empty state)',
        () {
      final s = StatisticsSummary.from(
          [_income(1000, DateTime(2026, 7, 1))], const [], now);
      expect(s.allExpenseCount, 0);
    });

    test('splits this-month spend into essentials and luxuries', () {
      final rows = [
        _expense(200, DateTime(2026, 7, 3), kind: CategoryKind.essential),
        _expense(120, DateTime(2026, 7, 6), kind: CategoryKind.luxury),
        // last month, excluded from this-month figures:
        _expense(999, DateTime(2026, 6, 10), kind: CategoryKind.essential),
      ];
      final s = StatisticsSummary.from(rows, const [], now);
      expect(s.spentThisMonth, 320);
      expect(s.essentialThisMonth, 200);
      expect(s.luxuryThisMonth, 120);
      expect(s.lastMonthSpent, 999);
    });

    test('daily average and projection use the day of month', () {
      final rows = [_expense(150, DateTime(2026, 7, 5))]; // now.day == 15
      final s = StatisticsSummary.from(rows, const [], now);
      expect(s.dailyAvgThisMonth, closeTo(150 / 15, 1e-9));
      // July has 31 days.
      expect(s.projectedThisMonth, closeTo(150 / 15 * 31, 1e-9));
    });

    test('projectedVsLastMonth is 0 when last month had no spend', () {
      final rows = [_expense(150, DateTime(2026, 7, 5))];
      final s = StatisticsSummary.from(rows, const [], now);
      expect(s.projectedVsLastMonth, 0);
    });

    test('savingsRate is saved/income, and null when no income', () {
      final withIncome = StatisticsSummary.from(
        [
          _income(2000, DateTime(2026, 7, 1)),
          _expense(100, DateTime(2026, 7, 2))
        ],
        [_contrib(500, DateTime(2026, 7, 3))],
        now,
      );
      expect(withIncome.savingsRate, closeTo(0.25, 1e-9));

      final noIncome = StatisticsSummary.from(
        [_expense(100, DateTime(2026, 7, 2))],
        [_contrib(500, DateTime(2026, 7, 3))],
        now,
      );
      expect(noIncome.savingsRate, isNull);
    });

    test('external deposits are excluded from the savings rate', () {
      final rows = [_income(2000, DateTime(2026, 7, 1))];
      final s = StatisticsSummary.from(
        rows,
        [
          _contrib(400, DateTime(2026, 7, 2)), // internal -> counts
          _contrib(5000, DateTime(2026, 7, 3), external: true), // ignored
        ],
        now,
      );
      expect(s.savingsRate, closeTo(0.2, 1e-9)); // 400 / 2000, external ignored
    });

    test('topCategories rolls sub-category spend up to the parent id', () {
      final rows = [
        // two sub-categories (ids 10, 11) of parent 1:
        _expense(100, DateTime(2026, 7, 2), id: 10, parentId: 1),
        _expense(50, DateTime(2026, 7, 4), id: 11, parentId: 1),
        // a top-level category (id 2):
        _expense(70, DateTime(2026, 7, 6), id: 2),
      ];
      final s = StatisticsSummary.from(rows, const [], now);
      // Parent 1 aggregates 150, ranks above category 2's 70.
      expect(s.topCategories.first.key, 1);
      expect(s.topCategories.first.value, 150);
      expect(s.topCategories[1].key, 2);
      expect(s.topCategories[1].value, 70);
    });

    test('biggestExpense is the largest this-month expense, ignoring income',
        () {
      final rows = [
        _income(9999, DateTime(2026, 7, 1)),
        _expense(80, DateTime(2026, 7, 2)),
        _expense(210, DateTime(2026, 7, 3)),
      ];
      final s = StatisticsSummary.from(rows, const [], now);
      expect(s.biggestExpense?.txn.amount, 210);
    });

    test('a timed today-transaction counts in the pace window', () {
      // now is 2026-07-15 midnight; a manual add is timestamped mid-afternoon.
      final s = StatisticsSummary.from(
        [_expense(300, DateTime(2026, 7, 15, 14, 30))],
        const [],
        now,
      );
      expect(s.currentWeeklyPace, greaterThan(0),
          reason: 'today with a time-of-day is inside the window');
      expect(s.spentThisMonth, 300);
    });

    test('monthlyTrend has 6 entries, oldest -> newest, ending this month', () {
      final s = StatisticsSummary.from(
          [_expense(10, DateTime(2026, 7, 1))], const [], now);
      expect(s.monthlyTrend, hasLength(6));
      expect(s.monthlyTrend.last.key.year, 2026);
      expect(s.monthlyTrend.last.key.month, 7);
      expect(s.monthlyTrend.first.key.month, 2); // Feb 2026
    });
  });
}
