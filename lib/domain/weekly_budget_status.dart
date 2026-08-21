import '../data/database.dart';
import '../data/enums.dart';
import 'budget_envelope.dart';
import 'financial_period.dart';
import 'recurrence_math.dart';
import 'spending_window.dart';

/// This week's spending against the (balance-capped) weekly budget — enough to
/// tell at a glance whether the week is on track or already blown, and by how
/// much. [budget] is the very same figure the statistics card and the app-icon
/// badge use; [spent] is discretionary (non-recurring) spending since this
/// week's payday-anchored start.
class WeeklyBudgetStatus {
  final double budget;
  final double spent;
  const WeeklyBudgetStatus({required this.budget, required this.spent});

  /// True once this week's spend has passed the budget.
  bool get isOver => spent > budget;

  /// How far over the budget (0 when still within it).
  double get over => spent > budget ? spent - budget : 0;

  /// How much is left to spend this week (0 when over).
  double get remaining => budget > spent ? budget - spent : 0;

  /// Fraction of the budget used, clamped to [0, 1] for a progress bar. With no
  /// budget it reads full when anything was spent, empty otherwise.
  double get ratio =>
      budget > 0 ? (spent / budget).clamp(0.0, 1.0) : (spent > 0 ? 1.0 : 0.0);
}

/// Computes [WeeklyBudgetStatus] from live data. The weekly budget is your
/// disposable income — (monthly salary − this cycle's monthly obligations − what
/// you've actually saved this cycle) ÷ the cycle's weeks — then adapted to how
/// the cycle has gone, and finally capped at your real remaining balance. Pure,
/// so the home card, the badge, and the statistics screen all agree.
WeeklyBudgetStatus weeklyBudgetStatus({
  required List<TxnRow> rows,
  required List<RecurrenceRule> incomeRules,
  required List<RecurrenceRule> expenseRules,
  required List<SavingsContribution> contributions,
  // Internal (non-external) investments reduce the real balance too; optional
  // because the only callers with anything but external portfolio entries are
  // the home card and the badge, which pass them.
  List<Investment> investments = const [],
  required DateTime now,
}) {
  final period = financialPeriod(incomeRules, now);
  final today = DateTime(now.year, now.month, now.day);
  // Exclusive upper bound: manual adds default to DateTime.now() (with a
  // time-of-day), so a row stamped today at 14:30 must still count.
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final weekStart = cycleWeekStart(period.start, now);
  final cycleStart = dateOnly(period.start);

  var spentThisWeek = 0.0, spentBeforeThisWeek = 0.0;
  // This cycle's income and total spend, for grounding the budget in the real
  // remaining balance (the cap, below).
  var periodIncome = 0.0, periodExpense = 0.0;
  // All-time income/expense, for the *actual* current balance (same formula as
  // the home «الرصيد») — the budget is capped so it can never exceed it.
  var allIncome = 0.0, allExpense = 0.0;

  for (final r in rows) {
    final date = r.txn.date;
    final amount = r.txn.amount;

    if (r.txn.type == TxnType.income) {
      allIncome += amount;
      if (period.contains(date)) periodIncome += amount;
      continue;
    }
    allExpense += amount;
    if (period.contains(date)) periodExpense += amount;

    // Fixed obligations (rent, bills, subscriptions) are planned, not
    // discretionary, so they never count against the weekly budget.
    if (r.txn.recurrenceId != null) continue;

    if (!date.isBefore(weekStart) && date.isBefore(tomorrow)) {
      spentThisWeek += amount;
    }
    // Discretionary spend in this cycle's weeks BEFORE the current one drives the
    // adaptive redistribution.
    if (!date.isBefore(cycleStart) && date.isBefore(weekStart)) {
      spentBeforeThisWeek += amount;
    }
  }

  // Salary − monthly obligations − what's been set aside this cycle: the shared
  // disposable envelope (the budget advisor sizes itself against the very same
  // figure, so the two can't disagree). [saved] also grounds the balance cap
  // below.
  final env = monthlyEnvelope(
    incomeRules: incomeRules,
    expenseRules: expenseRules,
    contributions: contributions,
    period: period,
  );
  final saved = env.saved;

  // The forward-looking base: disposable income ÷ the cycle's weeks.
  final base = incomeWeeklyBase(
    salaryMonthly: env.salary,
    obligationsMonthly: env.obligations,
    savedThisCycle: saved,
    periodStart: period.start,
    periodEnd: period.end,
  );

  // Adapt to the cycle so far: over/under-spending earlier lowers/raises what's
  // budgeted for the weeks that remain.
  final adaptive = adaptiveWeeklyBudget(
    recommended: base,
    spentBeforeThisWeek: spentBeforeThisWeek,
    periodStart: period.start,
    periodEnd: period.end,
    now: now,
  );

  // The real money on hand: the current account balance (same formula as the
  // home «الرصيد» — all income − all spend − what's in savings/investments).
  var internalSaved = 0.0;
  for (final c in contributions) {
    if (!c.external) internalSaved += c.amount;
  }
  var internalInvested = 0.0;
  for (final inv in investments) {
    if (!inv.external) internalInvested += inv.amount;
  }
  final actualBalance =
      allIncome - allExpense - internalSaved - internalInvested;

  // Never promise more than is left for the rest of the cycle, and never more
  // than is actually in the account — the LOWER of the two, so carry-over from
  // past cycles can't make the budget exceed the real balance. Only caps once
  // income has landed.
  final cycleRemaining = periodIncome - periodExpense - saved;
  final spendable =
      actualBalance < cycleRemaining ? actualBalance : cycleRemaining;
  final periodDays = period.end.difference(cycleStart).inDays;
  final daysLeft = period.end
      .difference(today)
      .inDays
      .clamp(1, periodDays < 1 ? 1 : periodDays);
  final budget = periodIncome > 0
      ? balanceCappedWeekly(
          adaptive: adaptive,
          remainingForCycle: spendable,
          daysLeft: daysLeft,
        )
      : adaptive;

  return WeeklyBudgetStatus(budget: budget, spent: spentThisWeek);
}
