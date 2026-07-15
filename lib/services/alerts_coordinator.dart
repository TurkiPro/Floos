import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
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

/// The soonest upcoming occurrence of any active recurring income rule.
Future<DateTime?> _nextSalaryDate(AppDatabase db, DateTime now) async {
  final rules = await db.recurrenceDao.activeRules();
  final today = dateOnly(now);
  DateTime? soonest;
  for (final r in rules) {
    if (r.type != TxnType.income) continue;
    final next = nextOccurrence(
      startDate: r.startDate,
      frequency: r.frequency,
      interval: r.interval,
      endDate: r.endDate,
      afterExclusive: today,
    );
    if (next == null) continue;
    if (soonest == null || next.isBefore(soonest)) soonest = next;
  }
  return soonest;
}

/// Recommended weekly spend (all essentials + 85% of the discretionary
/// average, the same formula the statistics screen shows) and what's already
/// been spent since the start of this week.
Future<WeeklyBudget> computeWeeklyBudget(AppDatabase db, DateTime now) async {
  final rows = await db.transactionDao.watchAllWithCategory().first;
  final today = DateTime(now.year, now.month, now.day);
  final windowStart = today.subtract(const Duration(days: spendingWindowDays));
  // Weeks here start on Saturday.
  final daysSinceSaturday = (today.weekday + 1) % 7;
  final weekStart = today.subtract(Duration(days: daysSinceSaturday));

  var essentialWindow = 0.0, luxuryWindow = 0.0, spentThisWeek = 0.0;
  DateTime? earliest;

  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    final date = r.txn.date;
    final amount = r.txn.amount;

    if (!date.isBefore(weekStart) && !date.isAfter(today)) {
      spentThisWeek += amount;
    }
    if (!date.isBefore(windowStart) && !date.isAfter(today)) {
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

  return WeeklyBudget(window.recommended, spentThisWeek);
}
