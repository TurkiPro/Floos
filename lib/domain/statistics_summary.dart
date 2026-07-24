import '../data/database.dart';
import '../data/enums.dart';
import 'date_grouping.dart';
import 'financial_period.dart';
import 'spending_window.dart';

/// All statistics, computed once in a single pass over the transactions.
class StatisticsSummary {
  final int allExpenseCount;
  final double spentThisMonth;
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
  final List<MapEntry<MonthKey, double>> monthlyTrend;

  const StatisticsSummary({
    required this.allExpenseCount,
    required this.spentThisMonth,
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
    required this.monthlyTrend,
  });

  static StatisticsSummary from(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
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
    // Salary-day-anchored week start (weeks run from the cycle start), for the
    // adaptive weekly budget and "spent before this week".
    final weekStart = cycleWeekStart(period.start, now);

    var allExpenseCount = 0;
    var spentThisMonth = 0.0, lastMonthSpent = 0.0, monthIncome = 0.0;
    var essentialThisMonth = 0.0, luxuryThisMonth = 0.0;
    var essentialWindow = 0.0, luxuryWindow = 0.0;
    var spentBeforeThisWeek = 0.0;
    var txnCountThisMonth = 0;
    DateTime? earliestInWindow;
    TxnRow? biggestExpense;
    final byTop = <int, double>{};
    final byMonth = <MonthKey, double>{};
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

      final mk = MonthKey(year: date.year, month: date.month);
      byMonth[mk] = (byMonth[mk] ?? 0) + amount;

      if (!date.isBefore(prevStart) && date.isBefore(period.start)) {
        lastMonthSpent += amount;
      }

      if (inThisMonth(date)) {
        spentThisMonth += amount;
        txnCountThisMonth++;
        final d0 = DateTime(date.year, date.month, date.day);
        byDayThisMonth[d0] = (byDayThisMonth[d0] ?? 0) + amount;
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

      // Recurring obligations are excluded from the weekly-budget figures (same
      // rule as the badge), so the "suggested weekly budget" reflects only
      // discretionary spending.
      final isRecurring = r.txn.recurrenceId != null;
      if (!isRecurring && inThisMonth(date) && date.isBefore(weekStart)) {
        spentBeforeThisWeek += amount;
      }
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
    // The weekly budget adapts to the month so far (see adaptiveWeeklyBudget):
    // over/under-spending earlier redistributes across the remaining weeks.
    final adaptiveWeekly = adaptiveWeeklyBudget(
      recommended: window.recommended,
      spentBeforeThisWeek: spentBeforeThisWeek,
      periodStart: period.start,
      periodEnd: period.end,
      now: now,
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

    // The weekly budget must never assume money you've already spent or set
    // aside is still available. Cap it at the real balance left for the rest of
    // the cycle (income − spending − savings), pro-rated so it can't exceed that
    // balance near payday — otherwise a flat 7-day figure reads as "imaginary"
    // when it's larger than everything you have left. When the cap bites and
    // there are savings behind it, flag it so the card can explain the drop.
    final cappedWeekly = monthIncome > 0
        ? balanceCappedWeekly(
            adaptive: adaptiveWeekly,
            remainingForCycle: unspentIncome,
            daysLeft: daysLeft,
          )
        : adaptiveWeekly;
    final weeklyReducedBySavings =
        monthSaved > 0 && cappedWeekly < adaptiveWeekly;

    final topCategories = byTop.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Last 6 months including this one, oldest -> newest for the bar row.
    final trend = <MapEntry<MonthKey, double>>[];
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final mk = MonthKey(year: d.year, month: d.month);
      trend.add(MapEntry(mk, byMonth[mk] ?? 0));
    }

    return StatisticsSummary(
      allExpenseCount: allExpenseCount,
      spentThisMonth: spentThisMonth,
      dailyAvgThisMonth: dailyAvg,
      projectedThisMonth: projected,
      lastMonthSpent: lastMonthSpent,
      projectedVsLastMonth: projectedVsLast,
      recommendedWeekly: cappedWeekly,
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
      monthlyTrend: trend,
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
