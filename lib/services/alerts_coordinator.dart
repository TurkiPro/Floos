import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/financial_period.dart';
import '../domain/weekly_budget_status.dart';
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

/// The current week's balance-capped budget and what's been spent against it —
/// loads the live data and hands it to the pure [weeklyBudgetStatus] (shared
/// with the home status card so the badge and the card can't disagree).
Future<WeeklyBudget> computeWeeklyBudget(AppDatabase db, DateTime now) async {
  final rows = await db.transactionDao.watchAllWithCategory().first;
  final incomeRules = await db.recurrenceDao.watchByType(TxnType.income).first;
  final contributions = await db.savingsDao.watchAllContributions().first;
  final status = weeklyBudgetStatus(
    rows: rows,
    incomeRules: incomeRules,
    contributions: contributions,
    now: now,
  );
  return WeeklyBudget(status.budget, status.spent);
}
