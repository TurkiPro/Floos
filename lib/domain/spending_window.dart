import 'recurrence_math.dart';

/// The rolling spending window both the weekly-budget alert and the statistics
/// screen derive their "recommended weekly spend" from: a 12-week (84-day)
/// look-back, recommending all essentials plus 85% of the discretionary
/// average. Kept in one place so the badge/notification and the on-screen card
/// can never disagree.
const spendingWindowDays = 84;
const discretionaryFactor = 0.85;

/// The start of the week containing [now], anchored on the salary day: weeks run
/// from [periodStart] (the cycle start / payday) in whole 7-day blocks, not from
/// a fixed weekday. So the first week of a cycle begins the day the salary lands.
DateTime cycleWeekStart(DateTime periodStart, DateTime now) {
  final start = dateOnly(periodStart);
  final elapsedDays = dateOnly(now).difference(start).inDays;
  final weeks = elapsedDays <= 0 ? 0 : elapsedDays ~/ 7;
  return DateTime(start.year, start.month, start.day + 7 * weeks);
}

class WeeklySpend {
  /// All essentials + 85% of the discretionary average, per week.
  final double recommended;

  /// The raw total average per week, with no discretionary discount.
  final double pace;

  const WeeklySpend({required this.recommended, required this.pace});
}

/// Derives the weekly figures from window totals already split by kind.
/// [earliestInWindow] is the oldest expense actually seen in the window (null
/// when there are none), so a new user with a few days of history isn't
/// averaged across a full 12 weeks.
WeeklySpend weeklySpend({
  required double essentialWindow,
  required double luxuryWindow,
  required DateTime? earliestInWindow,
  required DateTime today,
}) {
  final windowDays = earliestInWindow == null
      ? 1
      : today.difference(earliestInWindow).inDays + 1;
  final weeks = (windowDays / 7).clamp(1.0, 12.0);
  return WeeklySpend(
    recommended:
        essentialWindow / weeks + (luxuryWindow / weeks) * discretionaryFactor,
    pace: (essentialWindow + luxuryWindow) / weeks,
  );
}

/// The weekly budget, adapted to how the cycle has gone so far. [recommended] is
/// the flat historical weekly baseline (B); [spentBeforeThisWeek] is this
/// cycle's discretionary spending in the weeks *before* the current one. Weeks
/// are the salary-day-anchored 7-day blocks of the cycle [periodStart,
/// periodEnd).
///
/// The cycle's surplus/deficit to date — what the baseline said you'd have spent
/// by now (`B × weeksElapsed`) minus what you actually spent — is spread evenly
/// across the weeks that remain (this week included). So overspending earlier
/// lowers this week's budget and every week after it; a surplus raises them.
/// When spending matches the baseline exactly, it returns B unchanged.
double adaptiveWeeklyBudget({
  required double recommended,
  required double spentBeforeThisWeek,
  required DateTime periodStart,
  required DateTime periodEnd,
  required DateTime now,
}) {
  final start = dateOnly(periodStart);
  final elapsedDays = dateOnly(now).difference(start).inDays;
  final weeksElapsed = elapsedDays <= 0 ? 0 : elapsedDays ~/ 7;
  final totalDays = dateOnly(periodEnd).difference(start).inDays;
  final totalWeeks = totalDays <= 0 ? 1 : (totalDays / 7).ceil();
  final left = totalWeeks - weeksElapsed;
  final weeksLeft = left < 1 ? 1 : left;
  final carry = recommended * weeksElapsed - spentBeforeThisWeek;
  final adaptive = recommended + carry / weeksLeft;
  return adaptive < 0 ? 0 : adaptive;
}
