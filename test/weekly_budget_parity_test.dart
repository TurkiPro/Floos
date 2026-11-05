import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/budget_envelope.dart';
import 'package:floos/domain/spending_window.dart';
import 'package:floos/domain/statistics_summary.dart';
import 'package:floos/domain/weekly_budget_status.dart';
import 'package:floos/domain/weekly_performance.dart';

/// Every surface that states "this week's budget" must state the SAME number.
///
/// There are three of them — the home status card, the statistics card, and the
/// weekly-performance screen — and each one derives it from its own call. This
/// file is what stops them drifting apart.
///
/// It did not always cover all three. It locked home to stats, and the
/// weekly-performance screen, being outside it, drifted: it judged weeks against
/// the UNCAPPED baseline while quoting the capped figure in its own intro line.
/// The same week could read "over by 37" on the home card and "on track by 19"
/// one tap away.

Category _cat(TxnType type, CategoryKind kind) => Category(
      id: 1,
      name: 'c',
      iconKey: 'k',
      colorValue: 0,
      type: type,
      kind: kind,
      archived: false,
      sortOrder: 0,
    );

TxnRow _txn(TxnType type, double amount, DateTime date,
        {int? recurrenceId, CategoryKind kind = CategoryKind.essential}) =>
    TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: 1,
        type: type,
        date: date,
        recurrenceId: recurrenceId,
        createdAt: date,
      ),
      category: _cat(type, kind),
    );

RecurrenceRule _salary(DateTime start) => RecurrenceRule(
      id: 1,
      title: 'راتب',
      amount: 19000,
      categoryId: 1,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: start,
      active: true,
    );

RecurrenceRule _obligation(DateTime start) => RecurrenceRule(
      id: 9,
      title: 'إيجار',
      amount: 1200,
      categoryId: 1,
      type: TxnType.expense,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: start,
      active: true,
    );

void main() {
  test('home and stats derive the same weekly budget from the same data', () {
    final now = DateTime(2026, 7, 16);
    final incomeRules = [_salary(DateTime(2026, 1, 25))];
    final expenseRules = [_obligation(DateTime(2026, 1, 25))];
    final rows = [
      _txn(TxnType.income, 19000, DateTime(2026, 6, 25)),
      _txn(TxnType.expense, 500, DateTime(2026, 6, 28)),
      _txn(TxnType.expense, 300, DateTime(2026, 7, 2),
          kind: CategoryKind.luxury),
      // A recurring obligation: excluded from the weekly budget, but it still
      // reduces the balance the budget is capped by.
      _txn(TxnType.expense, 1200, DateTime(2026, 7, 5), recurrenceId: 9),
      _txn(TxnType.expense, 250, DateTime(2026, 7, 14)),
      _txn(TxnType.expense, 120, DateTime(2026, 7, 16)),
    ];
    final contributions = [
      SavingsContribution(
          id: 1,
          goalId: 1,
          amount: 1000,
          date: DateTime(2026, 7, 1),
          external: false,
          planned: false),
    ];

    final period = financialPeriod(incomeRules, now);
    final stats = StatisticsSummary.from(
        rows, contributions, incomeRules, expenseRules, now, period);
    final home = weeklyBudgetStatus(
      rows: rows,
      incomeRules: incomeRules,
      expenseRules: expenseRules,
      contributions: contributions,
      investments: const [],
      now: now,
    );

    expect(stats.recommendedWeekly, closeTo(home.budget, 1e-9),
        reason: 'the home card and the statistics card must agree');
  });

  test('the weekly-performance screen agrees with the home card', () {
    final now = DateTime(2026, 7, 16);
    final incomeRules = [_salary(DateTime(2026, 1, 25))];
    final expenseRules = [_obligation(DateTime(2026, 1, 25))];
    final rows = [
      _txn(TxnType.income, 19000, DateTime(2026, 6, 25)),
      _txn(TxnType.expense, 500, DateTime(2026, 6, 28)),
      _txn(TxnType.expense, 300, DateTime(2026, 7, 2),
          kind: CategoryKind.luxury),
      // A large obligation: excluded from the discretionary baseline, so it
      // does NOT lower the adapted budget — but it does drain the balance, so
      // the cap bites. This is the shape of the real case.
      _txn(TxnType.expense, 14000, DateTime(2026, 7, 5), recurrenceId: 9),
      _txn(TxnType.expense, 250, DateTime(2026, 7, 14)),
      _txn(TxnType.expense, 120, DateTime(2026, 7, 16)),
    ];
    final contributions = [
      SavingsContribution(
          id: 1,
          goalId: 1,
          amount: 1000,
          date: DateTime(2026, 7, 1),
          external: false,
          planned: false),
    ];

    final period = financialPeriod(incomeRules, now);
    final stats = StatisticsSummary.from(
        rows, contributions, incomeRules, expenseRules, now, period);
    final home = weeklyBudgetStatus(
      rows: rows,
      incomeRules: incomeRules,
      expenseRules: expenseRules,
      contributions: contributions,
      investments: const [],
      now: now,
    );

    // Exactly what the screen does to get its per-week baseline.
    final env = monthlyEnvelope(
      incomeRules: incomeRules,
      expenseRules: expenseRules,
      contributions: contributions,
      period: period,
    );
    final baseWeekly = incomeWeeklyBase(
      salaryMonthly: env.salary,
      obligationsMonthly: env.obligations,
      savedThisCycle: env.saved,
      periodStart: period.start,
      periodEnd: period.end,
    );

    final weeks = weeklyPerformance(
      rows: rows,
      byId: const {},
      baseWeekly: baseWeekly,
      now: now,
      periodStart: period.start,
      periodEnd: period.end,
      currentWeekBudget: stats.recommendedWeekly,
    );
    final current = weeks.firstWhere((w) => w.current);

    // The test only means something if the cap actually bites here — otherwise
    // capped and uncapped coincide and nothing is being checked.
    expect(home.budget, lessThan(baseWeekly),
        reason: 'the balance cap must be the binding constraint in this case');

    expect(current.budget, closeTo(home.budget, 1e-9),
        reason: 'the current week must be judged against the home figure');
    expect(current.budget, closeTo(stats.recommendedWeekly, 1e-9),
        reason: "and against the screen's own intro line");

    // The verdict, not just the number: the same week cannot be over on one
    // screen and on track on the next.
    expect(current.over, home.isOver,
        reason: 'one week, one verdict, wherever it is shown');
  });

  test('home and stats agree when the user has investments', () {
    // The case the first parity test could not see: its data had no
    // investments. Home passed them into the weekly budget; stats did not, so
    // money moved into investments still counted as spendable on the stats
    // screen — and on the weekly-performance screen, which takes its current
    // week from stats.
    final now = DateTime(2026, 7, 16);
    final incomeRules = [_salary(DateTime(2026, 1, 25))];
    final expenseRules = [_obligation(DateTime(2026, 1, 25))];
    final rows = [
      _txn(TxnType.income, 19000, DateTime(2026, 6, 25)),
      _txn(TxnType.expense, 300, DateTime(2026, 7, 2)),
    ];
    // Most of the balance moved into a portfolio — enough for the cap to bite.
    final investments = [
      Investment(
        id: 1,
        name: 'سهم',
        amount: 17000,
        date: DateTime(2026, 6, 26),
        external: false,
      ),
    ];

    final period = financialPeriod(incomeRules, now);
    final home = weeklyBudgetStatus(
      rows: rows,
      incomeRules: incomeRules,
      expenseRules: expenseRules,
      contributions: const [],
      investments: investments,
      now: now,
    );
    final stats = StatisticsSummary.from(
        rows, const [], incomeRules, expenseRules, now, period,
        investments: investments);
    final withoutInvestments = StatisticsSummary.from(
        rows, const [], incomeRules, expenseRules, now, period);

    // Only meaningful if investments actually change the answer here.
    expect(withoutInvestments.recommendedWeekly, greaterThan(home.budget),
        reason: 'the fixture must exercise the investment-reduced cap');
    expect(stats.recommendedWeekly, closeTo(home.budget, 1e-9));
  });

  test('"reduced by savings" means the budget really was reduced', () {
    // The budget only counts savings from before this week, so a deposit made
    // this week has not lowered it yet — and the note must not say it has.
    final now = DateTime(2026, 7, 16); // week began 16 July
    final incomeRules = [_salary(DateTime(2026, 1, 25))];
    final rows = [_txn(TxnType.income, 19000, DateTime(2026, 6, 25))];
    final period = financialPeriod(incomeRules, now);

    SavingsContribution deposit(DateTime d) => SavingsContribution(
        id: 1,
        goalId: 1,
        amount: 500,
        date: d,
        external: false,
        planned: false);

    final thisWeek = StatisticsSummary.from(rows,
        [deposit(DateTime(2026, 7, 16))], incomeRules, const [], now, period);
    final earlier = StatisticsSummary.from(rows,
        [deposit(DateTime(2026, 7, 1))], incomeRules, const [], now, period);

    expect(thisWeek.weeklyReducedBySavings, isFalse);
    expect(earlier.weeklyReducedBySavings, isTrue);
  });

  test('past weeks stay frozen and uncapped', () {
    // Only the week in progress takes the capped figure. A finished week is
    // history; today's balance has no bearing on how it went, and capping it
    // would rewrite the past every time the balance moved.
    final now = DateTime(2026, 7, 16);
    final incomeRules = [_salary(DateTime(2026, 1, 25))];
    final rows = [
      _txn(TxnType.income, 19000, DateTime(2026, 6, 25)),
      _txn(TxnType.expense, 400, DateTime(2026, 6, 28)),
      _txn(TxnType.expense, 120, DateTime(2026, 7, 16)),
    ];
    final period = financialPeriod(incomeRules, now);

    final weeks = weeklyPerformance(
      rows: rows,
      byId: const {},
      baseWeekly: 1000,
      now: now,
      periodStart: period.start,
      periodEnd: period.end,
      currentWeekBudget: 1, // an absurd cap, to prove it reaches only one week
    );

    final current = weeks.firstWhere((w) => w.current);
    expect(current.budget, 1);
    for (final w in weeks.where((w) => !w.current)) {
      expect(w.budget, greaterThan(1),
          reason: 'a finished week keeps its own frozen budget');
    }
  });
}
