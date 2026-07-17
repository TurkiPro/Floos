import '../data/database.dart';
import '../data/enums.dart';
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

/// Computes [WeeklyBudgetStatus] from live data — the same salary-cycle,
/// balance-capped weekly budget the badge and statistics screen use, plus what's
/// been spent since this week's payday-anchored start. Pure, so the home card,
/// the badge, and tests all agree on the number.
WeeklyBudgetStatus weeklyBudgetStatus({
  required List<TxnRow> rows,
  required List<RecurrenceRule> incomeRules,
  required List<SavingsContribution> contributions,
  required DateTime now,
}) {
  final period = financialPeriod(incomeRules, now);
  final today = DateTime(now.year, now.month, now.day);
  // Exclusive upper bound: manual adds default to DateTime.now() (with a
  // time-of-day), so a row stamped today at 14:30 must still count.
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final windowStart =
      DateTime(today.year, today.month, today.day - spendingWindowDays);
  final weekStart = cycleWeekStart(period.start, now);
  final cycleStart = dateOnly(period.start);

  var essentialWindow = 0.0, luxuryWindow = 0.0, spentThisWeek = 0.0;
  var spentBeforeThisWeek = 0.0;
  // This cycle's income and total spend, for grounding the budget in the real
  // remaining balance (below).
  var periodIncome = 0.0, periodExpense = 0.0;
  DateTime? earliest;

  for (final r in rows) {
    final date = r.txn.date;
    final amount = r.txn.amount;

    if (r.txn.type == TxnType.income) {
      if (period.contains(date)) periodIncome += amount;
      continue;
    }
    // Every expense this cycle — recurring obligations included — reduces the
    // balance the weekly budget is capped by.
    if (period.contains(date)) periodExpense += amount;

    // Fixed monthly obligations (rent, subscriptions, bills) are planned, not
    // discretionary, so they never count against the weekly budget.
    if (r.txn.recurrenceId != null) continue;

    if (!date.isBefore(weekStart) && date.isBefore(tomorrow)) {
      spentThisWeek += amount;
    }
    // Discretionary spend in this cycle's weeks BEFORE the current one — drives
    // the adaptive redistribution.
    if (!date.isBefore(cycleStart) && date.isBefore(weekStart)) {
      spentBeforeThisWeek += amount;
    }
    if (!date.isBefore(windowStart) && date.isBefore(tomorrow)) {
      if (r.category.kind == CategoryKind.luxury) {
        luxuryWindow += amount;
      } else {
        essentialWindow += amount;
      }
      if (earliest == null || date.isBefore(earliest)) earliest = date;
    }
  }

  final window = weeklySpend(
    essentialWindow: essentialWindow,
    luxuryWindow: luxuryWindow,
    earliestInWindow: earliest,
    today: today,
  );

  // Adapt the flat weekly baseline to the cycle so far: over/under-spending in
  // earlier weeks lowers/raises what's budgeted for the rest of the cycle.
  final adaptive = adaptiveWeeklyBudget(
    recommended: window.recommended,
    spentBeforeThisWeek: spentBeforeThisWeek,
    periodStart: period.start,
    periodEnd: period.end,
    now: now,
  );

  // Money set aside this cycle (external deposits already existed, so they don't
  // reduce this cycle's spendable income).
  var saved = 0.0;
  for (final c in contributions) {
    if (!c.external && period.contains(c.date)) saved += c.amount;
  }

  // Cap the behavioural budget at the real balance left for the rest of the
  // cycle — only when income is known, otherwise the behavioural figure stands.
  final periodDays = period.end.difference(cycleStart).inDays;
  final daysLeft = period.end
      .difference(today)
      .inDays
      .clamp(1, periodDays < 1 ? 1 : periodDays);
  final budget = periodIncome > 0
      ? balanceCappedWeekly(
          adaptive: adaptive,
          remainingForCycle: periodIncome - periodExpense - saved,
          daysLeft: daysLeft,
        )
      : adaptive;

  return WeeklyBudgetStatus(budget: budget, spent: spentThisWeek);
}
