import '../data/database.dart';
import '../data/enums.dart';
import 'budget_envelope.dart';
import 'financial_period.dart';
import 'ledger_balance.dart';
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

  /// Whether money set aside this cycle actually lowered [budget]. Only savings
  /// made before the current week count toward the budget (a mid-week deposit
  /// shrinks next week's), so this is decided here, where that cut-off is known,
  /// rather than guessed by anything that merely sees "savings this cycle".
  final bool reducedBySavings;

  const WeeklyBudgetStatus({
    required this.budget,
    required this.spent,
    this.reducedBySavings = false,
  });

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
  // Internal (non-external) investments reduce the real balance too. Required:
  // when this defaulted to empty, the statistics screen silently left them
  // out and stated a different weekly budget from the home card.
  required List<Investment> investments,
  // Lending lowers the cap (the money left); borrowing never raises it.
  required List<DebtMovementRow> debts,
  required DateTime now,
}) {
  final period = financialPeriod(incomeRules, now);
  // Exclusive upper bound: manual adds default to DateTime.now() (with a
  // time-of-day), so a row stamped today at 14:30 must still count.
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final weekStart = cycleWeekStart(period.start, now);
  final cycleStart = dateOnly(period.start);

  var spentThisWeek = 0.0, spentBeforeThisWeek = 0.0;
  // This cycle's income and total spend, for grounding the budget in the real
  // remaining balance (the cap, below).
  var periodIncome = 0.0;
  // This cycle's spend as it stood when THIS WEEK began. The budget is set
  // from it, so spending during the week moves `spent` and never the target
  // it is measured against.
  var periodExpenseBeforeWeek = 0.0;

  for (final r in rows) {
    final date = r.txn.date;
    final amount = r.txn.amount;

    if (r.txn.type == TxnType.income) {
      if (period.contains(date)) periodIncome += amount;
      continue;
    }
    if (date.isBefore(weekStart) && period.contains(date)) {
      periodExpenseBeforeWeek += amount;
    }

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

  // Set aside this cycle, counted only up to the start of this week — the same
  // freeze the cap uses below. A deposit made on Wednesday shrinks next week's
  // budget, not the one already in progress.
  var savedBeforeWeek = 0.0;
  for (final c in contributions) {
    if (c.external) continue;
    if (period.contains(c.date) && c.date.isBefore(weekStart)) {
      savedBeforeWeek += c.amount;
    }
  }

  // The forward-looking base: disposable income ÷ the cycle's weeks.
  final base = incomeWeeklyBase(
    salaryMonthly: env.salary,
    obligationsMonthly: env.obligations,
    savedThisCycle: savedBeforeWeek,
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

  // The money on hand that is yours to spend, now and as at the start of
  // this week — the home «الرصيد» less anything borrowed, from the one
  // function that computes it. Borrowed money is in the account but owed, so
  // it never raises the budget (plan 029).
  final ledger = LedgerInputs(
    rows: rows,
    contributions: contributions,
    investments: investments,
    debts: debts,
  );
  final actualBalance = spendableTotals(ledger).balance;
  final weekStartBalance = spendableAtWeekStart(ledger, weekStart);

  // The cap, measured AS AT THE START OF THIS WEEK.
  //
  // It used to be measured as at today, and that quietly made the whole figure
  // a moving target: `remainingForCycle / daysLeft * 7` is recomputed every
  // day, so with daysLeft shrinking the budget drifted upward on its own —
  // 1400 on Monday, 1448 on Tuesday, 1500 on Wednesday, with nothing spent at
  // all — and each expense knocked it back down. A weekly budget you cannot
  // look at twice and see the same number is not a budget.
  //
  // Everything the cap reads is therefore frozen to the week's start: the
  // balance, the cycle spend, the savings, and the days remaining. Income is
  // the exception and is counted as it lands — a salary or bonus arriving is
  // rare, always raises the figure, and would be strange to withhold until the
  // following week.
  final cycleRemainingAtWeekStart =
      periodIncome - periodExpenseBeforeWeek - savedBeforeWeek;
  final spendable = weekStartBalance < cycleRemainingAtWeekStart
      ? weekStartBalance
      : cycleRemainingAtWeekStart;
  final periodDays = period.end.difference(cycleStart).inDays;
  final daysLeft = period.end
      .difference(weekStart)
      .inDays
      .clamp(1, periodDays < 1 ? 1 : periodDays);
  final weekBudget = periodIncome > 0
      ? balanceCappedWeekly(
          adaptive: adaptive,
          remainingForCycle: spendable,
          daysLeft: daysLeft,
        )
      : adaptive;

  // One live exception to the freeze: never name a figure larger than the
  // money that currently exists. This is what the cap was originally for, and
  // it must not be lost — but it now only engages when the balance has
  // genuinely fallen below the week's target, which is precisely when the
  // number SHOULD move. In normal weeks the balance is far above it and this
  // changes nothing.
  //
  // Same guard as the cap: only once this cycle's income has landed. Before
  // payday the balance can legitimately sit at zero or below — the salary is
  // known from its rule but not yet in the ledger — and clamping to it would
  // zero the forward-looking budget for exactly the days someone is planning
  // what to spend once it arrives.
  final headroom = actualBalance < 0 ? 0.0 : actualBalance;
  final budget =
      periodIncome > 0 && weekBudget > headroom ? headroom : weekBudget;

  return WeeklyBudgetStatus(
    budget: budget,
    spent: spentThisWeek,
    reducedBySavings: savedBeforeWeek > 0,
  );
}
