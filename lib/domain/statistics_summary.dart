import '../data/database.dart';
import '../data/enums.dart';
import 'budget_advisor.dart' show previousCycles;
import 'financial_period.dart';
import 'spending_window.dart';
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

  static StatisticsSummary from(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
    List<RecurrenceRule> incomeRules,
    List<RecurrenceRule> expenseRules,
    DateTime now,
    FinancialPeriod period,
  ) {
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
    // The previous cycle (same length) for the "vs last month" comparison.
    final prevStart = DateTime(
        period.start.year, period.start.month, period.start.day - periodDays);
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

      if (!date.isBefore(prevStart) && date.isBefore(period.start)) {
        lastMonthSpent += amount;
      }

      if (inThisMonth(date)) {
        spentThisMonth += amount;
        txnCountThisMonth++;
        final d0 = DateTime(date.year, date.month, date.day);
        byDayThisMonth[d0] = (byDayThisMonth[d0] ?? 0) + amount;

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

    final dailyAvg = spentThisMonth / daysElapsed;
    final projected = dailyAvg * periodDays;
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

    final unspentIncome = monthIncome - spentThisMonth - monthSaved;
    final allowance = monthIncome > 0 ? unspentIncome / daysLeft : null;
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
      now: now,
    );
    final recommendedWeekly = wbs.budget;
    final weeklyReducedBySavings = monthSaved > 0;

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
