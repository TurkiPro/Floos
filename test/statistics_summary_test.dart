import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/dashboard_summary.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/statistics_summary.dart';

// A fixed "now" so month/window math is deterministic. Stats also take a
// FinancialPeriod now; a calendar-July period keeps these expectations, since
// its day counts (15 elapsed, 31 total) match the old calendar-month math.
final now = DateTime(2026, 7, 15);
final july = FinancialPeriod(DateTime(2026, 7, 1), DateTime(2026, 8, 1));

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

// A recurring obligation (rent/subscription): carries a recurrenceId, so it's
// "committed", not discretionary.
TxnRow _recurring(double amount, DateTime date,
        {CategoryKind kind = CategoryKind.essential}) =>
    TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: 1,
        type: TxnType.expense,
        date: date,
        recurrenceId: 9,
        createdAt: date,
      ),
      category: _cat(kind: kind),
    );

SavingsContribution _contrib(double amount, DateTime date,
        {bool external = false}) =>
    SavingsContribution(
        id: 1,
        goalId: 1,
        amount: amount,
        date: date,
        external: external,
        planned: false);

void main() {
  group('StatisticsSummary.from', () {
    test('allExpenseCount is zero for income-only input (drives empty state)',
        () {
      final s = StatisticsSummary.from(
          [_income(1000, DateTime(2026, 7, 1))],
          const [],
          const <RecurrenceRule>[],
          const <RecurrenceRule>[],
          now,
          july,
          debts: const []);
      expect(s.allExpenseCount, 0);
    });

    test('committed (recurring) spend is split out from discretionary', () {
      final rows = [
        _expense(100, DateTime(2026, 7, 3)), // discretionary essential
        _recurring(200, DateTime(2026, 7, 5)), // a rent-like obligation
        _expense(120, DateTime(2026, 7, 6), kind: CategoryKind.luxury),
      ];
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      expect(s.spentThisMonth, 420); // the full total still includes it
      expect(s.committedThisMonth, 200);
      expect(s.discretionaryThisMonth, 220);
      // The needs/wants split, the top categories, and the biggest expense all
      // describe the discretionary money only — the 200 obligation is excluded
      // even though it's the single largest row.
      expect(s.essentialThisMonth, 100);
      expect(s.luxuryThisMonth, 120);
      expect(s.biggestExpense?.txn.amount, 120);
      expect(s.topCategories.fold<double>(0, (a, e) => a + e.value), 220);
    });

    test('splits this-month spend into essentials and luxuries', () {
      final rows = [
        _expense(200, DateTime(2026, 7, 3), kind: CategoryKind.essential),
        _expense(120, DateTime(2026, 7, 6), kind: CategoryKind.luxury),
        // last month, excluded from this-month figures:
        _expense(999, DateTime(2026, 6, 10), kind: CategoryKind.essential),
      ];
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      expect(s.spentThisMonth, 320);
      expect(s.essentialThisMonth, 200);
      expect(s.luxuryThisMonth, 120);
      expect(s.lastMonthSpent, 999);
    });

    test('daily average and projection use the day of month', () {
      final rows = [_expense(150, DateTime(2026, 7, 5))]; // now.day == 15
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      expect(s.dailyAvgThisMonth, closeTo(150 / 15, 1e-9));
      // July has 31 days.
      expect(s.projectedThisMonth, closeTo(150 / 15 * 31, 1e-9));
    });

    test('projectedVsLastMonth is 0 when last month had no spend', () {
      final rows = [_expense(150, DateTime(2026, 7, 5))];
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      expect(s.projectedVsLastMonth, 0);
    });

    test('savingsRate is saved/income, and null when no income', () {
      final withIncome = StatisticsSummary.from(
        [
          _income(2000, DateTime(2026, 7, 1)),
          _expense(100, DateTime(2026, 7, 2))
        ],
        [_contrib(500, DateTime(2026, 7, 3))],
        const <RecurrenceRule>[],
        const <RecurrenceRule>[],
        now,
        july,
        debts: const [],
      );
      expect(withIncome.savingsRate, closeTo(0.25, 1e-9));

      final noIncome = StatisticsSummary.from(
        [_expense(100, DateTime(2026, 7, 2))],
        [_contrib(500, DateTime(2026, 7, 3))],
        const <RecurrenceRule>[],
        const <RecurrenceRule>[],
        now,
        july,
        debts: const [],
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
        const <RecurrenceRule>[],
        const <RecurrenceRule>[],
        now,
        july,
        debts: const [],
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
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
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
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      expect(s.biggestExpense?.txn.amount, 210);
    });

    test('a timed today-transaction counts in the pace window', () {
      // now is 2026-07-15 midnight; a manual add is timestamped mid-afternoon.
      final s = StatisticsSummary.from(
        [_expense(300, DateTime(2026, 7, 15, 14, 30))],
        const [],
        const <RecurrenceRule>[],
        const <RecurrenceRule>[],
        now,
        july,
        debts: const [],
      );
      expect(s.currentWeeklyPace, greaterThan(0),
          reason: 'today with a time-of-day is inside the window');
      expect(s.spentThisMonth, 300);
    });

    test('cycleTrend has 6 entries, oldest -> newest, ending this cycle', () {
      final s = StatisticsSummary.from(
          [_expense(10, DateTime(2026, 7, 1))],
          const [],
          const <RecurrenceRule>[],
          const <RecurrenceRule>[],
          now,
          july,
          debts: const []);
      expect(s.cycleTrend, hasLength(6));
      // Last is the current cycle (July); it holds the one 10 ⃁ expense.
      expect(s.cycleTrend.last.key.start, DateTime(2026, 7, 1));
      expect(s.cycleTrend.last.value, 10);
      // Oldest is five cycles back — February.
      expect(s.cycleTrend.first.key.start, DateTime(2026, 2, 1));
    });
  });

  // These figures were barely tested, which is how the screen came to show
  // numbers like an 87,187 monthly projection on a 19,419 salary. Each test
  // below pins a figure that was wrong.
  group('obligations are not extrapolated', () {
    test('rent posted once is counted once, not stretched across the month',
        () {
      // 15 days into July: 4500 rent posted on the 2nd, 150 of day-to-day
      // spending. Projected = rent as-is + the day-to-day pace over 31 days.
      final rows = [
        _recurring(4500, DateTime(2026, 7, 2)),
        _expense(150, DateTime(2026, 7, 5)),
      ];
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);

      expect(s.projectedThisMonth, closeTo(4500 + 150 / 15 * 31, 1e-9));
      // The old formula: everything ÷ days elapsed × days in month.
      expect(s.projectedThisMonth, lessThan((4500 + 150) / 15 * 31 - 1000),
          reason: 'rent must not be read as a daily habit');
    });

    test('the daily rate is the day-to-day spending only', () {
      final rows = [
        _recurring(4500, DateTime(2026, 7, 2)),
        _expense(150, DateTime(2026, 7, 5)),
      ];
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      expect(s.dailyAvgThisMonth, closeTo(150 / 15, 1e-9));
    });

    test('obligations still due before payday are included', () {
      // Rent last posted 20 June, so the 20 July one is still to come.
      final rent = RecurrenceRule(
        id: 9,
        title: 'إيجار',
        amount: 4500,
        categoryId: 1,
        type: TxnType.expense,
        frequency: Frequency.monthly,
        interval: 1,
        startDate: DateTime(2026, 1, 20),
        lastMaterialized: DateTime(2026, 6, 20),
        active: true,
      );
      final rows = [_expense(150, DateTime(2026, 7, 5))];
      final s = StatisticsSummary.from(
          rows, const [], const <RecurrenceRule>[], [rent], now, july,
          debts: const []);

      expect(s.projectedThisMonth, closeTo(4500 + 150 / 15 * 31, 1e-9),
          reason: 'known rent ahead, plus the day-to-day pace');
    });
  });

  group('per-day figures describe what you chose to spend', () {
    test('rent day is not the "highest spending day"', () {
      final rows = [
        _recurring(4500, DateTime(2026, 7, 2)),
        _expense(150, DateTime(2026, 7, 5)),
        _expense(40, DateTime(2026, 7, 9)),
      ];
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      expect(s.highestDay, DateTime(2026, 7, 5));
      expect(s.highestDayAmount, 150);
    });

    test('a day with only an auto-posted bill is still a no-spend day', () {
      final rows = [
        _recurring(4500, DateTime(2026, 7, 2)),
        _expense(150, DateTime(2026, 7, 5)),
      ];
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      // 15 days elapsed, one day of actual spending.
      expect(s.noSpendDays, 14);
    });

    test('a future-dated row is neither the highest day nor a spend day', () {
      final rows = [
        _expense(40, DateTime(2026, 7, 5)),
        _expense(900, DateTime(2026, 7, 20)), // after "now" (15 July)
      ];
      final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
          const <RecurrenceRule>[], now, july,
          debts: const []);
      expect(s.highestDay, DateTime(2026, 7, 5));
      expect(s.noSpendDays, 14);
    });
  });

  test('"vs last month" uses the real previous cycle, not a guessed length',
      () {
    // July is 31 days but June is 30. Subtracting July's length from 1 July
    // lands on 31 May, so a May expense used to be counted as last month's.
    final rows = [
      _expense(100, DateTime(2026, 7, 5)),
      _expense(800, DateTime(2026, 5, 31)), // May — not last cycle
      _expense(200, DateTime(2026, 6, 10)), // June — last cycle
    ];
    final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
        const <RecurrenceRule>[], now, july,
        debts: const []);
    expect(s.lastMonthSpent, 200);
  });

  test('the daily allowance carries last cycle\'s deficit, like «المتبقي»', () {
    // Ended last cycle 1000 overdrawn; 6000 salary this cycle.
    final rows = [
      _income(5000, DateTime(2026, 6, 1)),
      _expense(6000, DateTime(2026, 6, 20)),
      _income(6000, DateTime(2026, 7, 1)),
      _expense(300, DateTime(2026, 7, 4)),
    ];
    final s = StatisticsSummary.from(rows, const [], const <RecurrenceRule>[],
        const <RecurrenceRule>[], now, july,
        debts: const []);
    final home =
        DashboardSummary.from(rows, const [], const [], july, debts: const []);

    // Same figure as the home card, spread over the days left.
    expect(s.dailyAllowanceRemaining,
        closeTo(home.monthRemaining / s.daysLeftInMonth, 1e-9));
    // And it really is the capped one: 6000 − 300 would be 5700; the balance
    // is 4700.
    expect(home.monthRemaining, closeTo(4700, 1e-9));
  });
}
