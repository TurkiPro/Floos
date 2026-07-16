import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/financial_period.dart';
import '../domain/recurrence_math.dart';
import '../domain/spending_window.dart';
import 'badge_service.dart';
import 'notification_service.dart';

/// The remaining spending allowance for the current week.
class WeeklyBudget {
  final double recommended;
  final double spentThisWeek;
  const WeeklyBudget(this.recommended, this.spentThisWeek);

  double get remaining {
    final left = recommended - spentThisWeek;
    return left < 0 ? 0 : left;
  }
}

/// Recomputes everything that depends on live data and pushes it to the OS:
/// the scheduled alerts (which need the next salary date and the week's budget
/// to be worded concretely) and the app-icon badge.
///
/// Called on launch, on resume, and whenever a notification/badge setting
/// changes, so the schedule and badge can never drift out of sync with the data.
Future<void> refreshAlerts(AppDatabase db, AppSettings settings) async {
  final now = DateTime.now();

  final nextSalary = await _nextSalaryDate(db, now);
  final budget = await computeWeeklyBudget(db, now);

  await NotificationService.reschedule(
    settings,
    nextSalary: nextSalary,
    weeklyBudget: budget.recommended,
  );

  if (settings.badgeWeeklyBudget) {
    await BadgeService.setWeeklyBudget(budget.remaining.round());
  } else {
    await BadgeService.clear();
  }
}

/// When the salary next lands — the largest active recurring income,
/// override-aware — the same date the home countdown and the financial period
/// use, so the reminder can't fire on a different day than they show.
Future<DateTime?> _nextSalaryDate(AppDatabase db, DateTime now) async {
  final rules = await db.recurrenceDao.activeRules();
  return nextSalaryDate(rules, now);
}

/// Recommended weekly spend (all essentials + 85% of the discretionary
/// average, the same formula the statistics screen shows) and what's already
/// been spent since the start of this week.
Future<WeeklyBudget> computeWeeklyBudget(AppDatabase db, DateTime now) async {
  final rows = await db.transactionDao.watchAllWithCategory().first;
  final incomeRules = await db.recurrenceDao.watchByType(TxnType.income).first;
  // Weeks are anchored on the salary day (the cycle start), so "this week" runs
  // from the payday-aligned week boundary, not a fixed weekday.
  final period = financialPeriod(incomeRules, now);
  final today = DateTime(now.year, now.month, now.day);
  // Exclusive upper bound: manual adds default to DateTime.now() (with a
  // time-of-day), so a row stamped today at 14:30 is after today-at-midnight
  // and a midnight upper bound would drop it. Constructor arithmetic (not
  // Duration) keeps the window boundaries DST-safe.
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final windowStart =
      DateTime(today.year, today.month, today.day - spendingWindowDays);
  final weekStart = cycleWeekStart(period.start, now);
  final cycleStart = dateOnly(period.start);

  var essentialWindow = 0.0, luxuryWindow = 0.0, spentThisWeek = 0.0;
  var spentBeforeThisWeek = 0.0;
  DateTime? earliest;

  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    // Fixed monthly obligations (rent, subscriptions, bills) are generated from
    // a recurring rule and are planned, not discretionary day-to-day spending.
    // They must not count against the weekly budget — neither eating this week's
    // allowance when one lands this week, nor inflating the 12-week average the
    // recommendation is built from. Anything with a recurrence link is excluded.
    if (r.txn.recurrenceId != null) continue;
    final date = r.txn.date;
    final amount = r.txn.amount;

    if (!date.isBefore(weekStart) && date.isBefore(tomorrow)) {
      spentThisWeek += amount;
    }
    // This cycle's discretionary spending in the weeks BEFORE the current one —
    // drives the adaptive redistribution.
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

  return WeeklyBudget(adaptive, spentThisWeek);
}
