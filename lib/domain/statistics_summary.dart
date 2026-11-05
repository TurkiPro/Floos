import '../data/database.dart';
import '../data/enums.dart';
import 'budget_advisor.dart' show previousCycles;
import 'dashboard_summary.dart';
import 'financial_period.dart';
import 'spending_window.dart';
import 'upcoming_commitments.dart';
import 'weekly_budget_status.dart';

/// All statistics, computed once in a single pass over the transactions.
class StatisticsSummary {
  final int allExpenseCount;
  final double spentThisMonth;

  /// This cycle's spend split by how controllable it is. [committedThisMonth] is
  /// money already promised through a recurring rule (rent, bills,
  /// subscriptions, family transfers); [discretionaryThisMonth] is everything
  /// chosen in the moment. Their sum is [spentThisMonth]. The needs/wants split,
  /// the top categories, and the biggest expense all describe the discretionary
  /// part only — the money you can actually act on — so fixed obligations don't
  /// drown out the signal. Same recurring test the weekly budget uses.
  final double committedThisMonth;
  final double discretionaryThisMonth;
  final double dailyAvgThisMonth;
  final double projectedThisMonth;
  final double lastMonthSpent;

  /// Percent change of the projected month total vs last month's total.
  final double projectedVsLastMonth;
  final double recommendedWeekly;

  /// True when money set aside this month pulled the weekly budget below its
  /// behaviour-based baseline — i.e. the budget no longer assumes the saved
  /// amount is available to spend. Drives the note on the weekly-budget card.
  final bool weeklyReducedBySavings;

  final double currentWeeklyPace;
  final double essentialThisMonth;
  final double luxuryThisMonth;
  final double monthIncome;
  final double monthSaved;
  final double? savingsRate;
  final double? dailyAllowanceRemaining;
  final int daysLeftInMonth;
  final int daysElapsed;
  final int txnCountThisMonth;
  final double avgTxnThisMonth;
  final TxnRow? biggestExpense;
  final DateTime? highestDay;
  final double highestDayAmount;
  final int noSpendDays;
  final int? topWeekday;
  final double topWeekdayAvg;
  final List<MapEntry<int, double>> topCategories; // topLevelId -> amount
  /// Total spend per salary cycle for the last up to 6 cycles, oldest → newest.
  final List<MapEntry<FinancialPeriod, double>> cycleTrend;

  const StatisticsSummary({
    required this.allExpenseCount,
    required this.spentThisMonth,
    required this.committedThisMonth,
    required this.discretionaryThisMonth,
    required this.dailyAvgThisMonth,
    required this.projectedThisMonth,
    required this.lastMonthSpent,
    required this.projectedVsLastMonth,
    required this.recommendedWeekly,
    required this.weeklyReducedBySavings,
    required this.currentWeeklyPace,
    required this.essentialThisMonth,
    required this.luxuryThisMonth,
    required this.monthIncome,
    required this.monthSaved,
    required this.savingsRate,
    required this.dailyAllowanceRemaining,
    required this.daysLeftInMonth,
    required this.daysElapsed,
    required this.txnCountThisMonth,
    required this.avgTxnThisMonth,
    required this.biggestExpense,
    required this.highestDay,
    required this.highestDayAmount,
    required this.noSpendDays,
    required this.topWeekday,
    required this.topWeekdayAvg,
    required this.topCategories,
    required this.cycleTrend,
  });

  /// [investments] matters more than its default suggests: money moved into
  /// investments has left the balance, and both the weekly budget's cap and the
  /// daily allowance are bounded by the balance. Omit it and this screen
  /// reports a larger budget than the home card for anyone who invests — the
  /// home card has always passed it. Optional only so call sites that genuinely
  /// have none (tests) need not invent an empty list.
  static StatisticsSummary from(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
    List<RecurrenceRule> incomeRules,
    List<RecurrenceRule> expenseRules,
    DateTime now,
    FinancialPeriod period, {
    List<Investment> investments = const [],
    // Required, unlike investments above: the balance caps read it, and a
    // defaulted list is how investments once went missing from this screen.
    required List<DebtMovementRow> debts,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    // Exclusive upper bound so rows stamped today with a time-of-day (manual
    // adds default to DateTime.now(), not midnight) still count. Constructor
    // arithmetic keeps the window DST-safe.
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    // "This month" is the current salary cycle (see FinancialPeriod): its
    // length, how far into it we are, and how much of it remains.
    final periodDays = period.end.difference(period.start).inDays;
    final daysElapsed =
        (today.difference(period.start).inDays + 1).clamp(1, periodDays);
    final daysLeft = period.end.difference(today).inDays.clamp(1, periodDays);
    // The real previous salary cycle, for the "vs last month" comparison. It was
    // assumed to be the same length as this one (start − periodDays), but cycles
    // are 28–31 days and a payday override moves them, so that window could
    // borrow or drop a day belonging to a different cycle.
    final prevCycles = previousCycles(incomeRules, now, 1);
    final prevCycle = prevCycles.isEmpty ? null : prevCycles.first;
    final windowStart =
        DateTime(today.year, today.month, today.day - spendingWindowDays);

    var allExpenseCount = 0;
    var spentThisMonth = 0.0, lastMonthSpent = 0.0, monthIncome = 0.0;
    var essentialThisMonth = 0.0, luxuryThisMonth = 0.0;
    var committedThisMonth = 0.0, discretionaryThisMonth = 0.0;
    var essentialWindow = 0.0, luxuryWindow = 0.0;
    var txnCountThisMonth = 0;
    DateTime? earliestInWindow;
    TxnRow? biggestExpense;
    final byTop = <int, double>{};
    final byDayThisMonth = <DateTime, double>{};
    final weekdayTotals = <int, double>{};

    bool inThisMonth(DateTime d) => period.contains(d);

    for (final r in rows) {
      final date = r.txn.date;
      final amount = r.txn.amount;

      if (r.txn.type == TxnType.income) {
        if (inThisMonth(date)) monthIncome += amount;
        continue;
      }

      allExpenseCount++;
      final kind = r.category.kind;

      if (prevCycle != null && prevCycle.contains(date)) {
        lastMonthSpent += amount;
      }

      if (inThisMonth(date)) {
        spentThisMonth += amount;
        txnCountThisMonth++;

        // Committed = money already promised through a recurring rule (rent,
        // bills, subscriptions, family transfers). Discretionary = everything
        // chosen in the moment. The needs/wants split, the top categories, and
        // the biggest expense all describe the DISCRETIONARY money — the part
        // you can actually act on — so obligations don't drown out the signal;
        // they get their own line on the card. Same recurring test the weekly
        // budget uses, so the two halves of the app finally agree.
        if (r.txn.recurrenceId != null) {
          committedThisMonth += amount;
        } else {
          discretionaryThisMonth += amount;
          // Tallied per day for the highest-spend day and the no-spend days —
          // discretionary only. Counting obligations here made rent day the
          // "highest spending day" every single cycle, and an auto-posted bill
          // break a no-spend day the user did nothing on.
          // Up to today only: these describe days that have actually happened.
          // A row dated tomorrow was otherwise reported as the highest-spend
          // day before it existed, and counted as a spend day against the
          // no-spend total.
          if (date.isBefore(tomorrow)) {
            final d0 = DateTime(date.year, date.month, date.day);
            byDayThisMonth[d0] = (byDayThisMonth[d0] ?? 0) + amount;
          }
          if (kind == CategoryKind.luxury) {
            luxuryThisMonth += amount;
          } else {
            essentialThisMonth += amount;
          }
          final topId = r.category.parentId ?? r.category.id;
          byTop[topId] = (byTop[topId] ?? 0) + amount;
          if (biggestExpense == null || amount > biggestExpense.txn.amount) {
            biggestExpense = r;
          }
        }
      }

      // Recurring obligations are excluded from the weekly-budget figures (same
      // rule as the badge), so the "suggested weekly budget" reflects only
      // discretionary spending.
      final isRecurring = r.txn.recurrenceId != null;
      if (!isRecurring &&
          !date.isBefore(windowStart) &&
          date.isBefore(tomorrow)) {
        if (kind == CategoryKind.luxury) {
          luxuryWindow += amount;
        } else {
          essentialWindow += amount;
        }
        weekdayTotals[date.weekday] =
            (weekdayTotals[date.weekday] ?? 0) + amount;
        if (earliestInWindow == null || date.isBefore(earliestInWindow)) {
          earliestInWindow = date;
        }
      }
    }

    // External deposits are money that already existed, so they don't count
    // as income saved this month (excluded from the savings rate and the
    // daily-allowance calculation below).
    var monthSaved = 0.0;
    for (final c in contributions) {
      if (!c.external && inThisMonth(c.date)) monthSaved += c.amount;
    }

    // The daily rate and the month projection extrapolate only what actually
    // recurs day to day: the DISCRETIONARY spend. Obligations are known
    // amounts — what has already posted this cycle plus what is still due
    // before payday — and are added as they are, never stretched across the
    // month.
    //
    // They used to be extrapolated with everything else, so rent posting on day
    // 2 of a cycle was read as a daily habit: on a 19,419 salary the screen
    // projected 87,187 for the month, then 58,125 the next day and 29,062 three
    // days later with nothing new spent, with a "+501% vs last month" beside it.
    final dailyAvg = discretionaryThisMonth / daysElapsed;
    // Still due before payday — the same figure as the home card's
    // «قادم هذه الدورة», from the same function.
    final stillDue =
        upcomingTotal(upcomingCommitments(expenseRules, now, period.end));
    final projected = committedThisMonth + stillDue + dailyAvg * periodDays;
    final projectedVsLast = lastMonthSpent > 0
        ? (projected - lastMonthSpent) / lastMonthSpent * 100
        : 0.0;

    // The rolling window's recommended weekly spend + raw pace, shared with the
    // weekly-budget alert so the badge and this screen can't disagree.
    final window = weeklySpend(
      essentialWindow: essentialWindow,
      luxuryWindow: luxuryWindow,
      earliestInWindow: earliestInWindow,
      today: today,
    );

    // Average spend per weekday over the window: divide each weekday's total
    // by how many times that weekday actually occurred in the window.
    final effectiveStart = earliestInWindow ?? today;
    int? topWeekday;
    var topWeekdayAvg = 0.0;
    for (final wd in weekdayTotals.keys) {
      final occurrences = _countWeekday(effectiveStart, today, wd);
      if (occurrences == 0) continue;
      final avg = weekdayTotals[wd]! / occurrences;
      if (avg > topWeekdayAvg) {
        topWeekdayAvg = avg;
        topWeekday = wd;
      }
    }

    // Highest-spend day and no-spend days, within the elapsed part of the month.
    DateTime? highestDay;
    var highestDayAmount = 0.0;
    byDayThisMonth.forEach((day, amount) {
      if (amount > highestDayAmount) {
        highestDayAmount = amount;
        highestDay = day;
      }
    });
    final noSpendDays = daysElapsed - byDayThisMonth.length;

    // What is left to spend per day until payday: the home card's «المتبقي»,
    // divided by the days remaining. Taken from DashboardSummary rather than
    // re-derived, because it was re-derived — as this cycle's income minus its
    // spending, with no knowledge of a deficit carried in from last cycle — and
    // so it overstated the daily allowance in exactly the case «المتبقي» was
    // fixed for. Reusing the one figure is what keeps them from drifting apart
    // again.
    final remaining =
        DashboardSummary.from(rows, contributions, investments, period,
                debts: debts)
            .monthRemaining;
    final allowance = monthIncome > 0 ? remaining / daysLeft : null;
    final savingsRate = monthIncome > 0 ? monthSaved / monthIncome : null;

    // The weekly budget is the exact figure the home card and the app-icon
    // badge show — computed by the one shared function so this screen can never
    // disagree with them. It's income-based (salary − obligations − savings ÷
    // the cycle's weeks), adapted to the cycle so far, then capped at the real
    // remaining balance. Since savings are subtracted in that base, any saving
    // this cycle lowers the budget — flag it so the card can explain the drop.
    final wbs = weeklyBudgetStatus(
      rows: rows,
      incomeRules: incomeRules,
      expenseRules: expenseRules,
      contributions: contributions,
      // The home card passes these; without them this screen's budget ignored
      // money moved into investments and came out larger than home's.
      investments: investments,
      debts: debts,
      now: now,
    );
    final recommendedWeekly = wbs.budget;
    // From the budget itself, not re-guessed from this cycle's savings. The
    // budget only counts savings made BEFORE the current week (a deposit
    // mid-week shrinks next week), so "this cycle saved anything" claimed a
    // reduction that had not happened yet.
    final weeklyReducedBySavings = wbs.reducedBySavings;

    final topCategories = byTop.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Last up to 6 salary cycles including this one, oldest -> newest, each with
    // its total spend — the bar row browses by cycle, never the calendar month.
    final trendPeriods = <FinancialPeriod>[
      ...previousCycles(incomeRules, now, 5).reversed,
      period,
    ];
    final trend = [
      for (final p in trendPeriods)
        MapEntry(
          p,
          rows.fold<double>(
              0,
              (sum, r) =>
                  r.txn.type == TxnType.expense && p.contains(r.txn.date)
                      ? sum + r.txn.amount
                      : sum),
        ),
    ];

    return StatisticsSummary(
      allExpenseCount: allExpenseCount,
      spentThisMonth: spentThisMonth,
      committedThisMonth: committedThisMonth,
      discretionaryThisMonth: discretionaryThisMonth,
      dailyAvgThisMonth: dailyAvg,
      projectedThisMonth: projected,
      lastMonthSpent: lastMonthSpent,
      projectedVsLastMonth: projectedVsLast,
      recommendedWeekly: recommendedWeekly,
      weeklyReducedBySavings: weeklyReducedBySavings,
      currentWeeklyPace: window.pace,
      essentialThisMonth: essentialThisMonth,
      luxuryThisMonth: luxuryThisMonth,
      monthIncome: monthIncome,
      monthSaved: monthSaved,
      savingsRate: savingsRate,
      dailyAllowanceRemaining: allowance,
      daysLeftInMonth: daysLeft,
      daysElapsed: daysElapsed,
      txnCountThisMonth: txnCountThisMonth,
      avgTxnThisMonth:
          txnCountThisMonth > 0 ? spentThisMonth / txnCountThisMonth : 0,
      biggestExpense: biggestExpense,
      highestDay: highestDay,
      highestDayAmount: highestDayAmount,
      noSpendDays: noSpendDays < 0 ? 0 : noSpendDays,
      topWeekday: topWeekday,
      topWeekdayAvg: topWeekdayAvg,
      topCategories: topCategories.take(5).toList(),
      cycleTrend: trend,
    );
  }

  /// How many times [weekday] falls between [from] and [to], inclusive.
  static int _countWeekday(DateTime from, DateTime to, int weekday) {
    var count = 0;
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end)) {
      if (d.weekday == weekday) count++;
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return count;
  }
}
