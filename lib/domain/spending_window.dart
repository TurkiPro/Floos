/// The rolling spending window both the weekly-budget alert and the statistics
/// screen derive their "recommended weekly spend" from: a 12-week (84-day)
/// look-back, recommending all essentials plus 85% of the discretionary
/// average. Kept in one place so the badge/notification and the on-screen card
/// can never disagree.
const spendingWindowDays = 84;
const discretionaryFactor = 0.85;

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

/// Number of Saturdays (week starts) in [fromInclusive, toExclusive).
int _saturdaysInRange(DateTime fromInclusive, DateTime toExclusive) {
  var count = 0;
  var d = DateTime(fromInclusive.year, fromInclusive.month, fromInclusive.day);
  final end = DateTime(toExclusive.year, toExclusive.month, toExclusive.day);
  while (d.isBefore(end)) {
    if (d.weekday == DateTime.saturday) count++;
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return count;
}

/// The weekly budget, adapted to how the month has gone so far. [recommended] is
/// the flat historical weekly baseline (B); [spentBeforeThisWeek] is this
/// month's discretionary spending in the weeks *before* the current one.
///
/// The month's surplus/deficit to date — what the baseline said you'd have
/// spent by now (`B × weeksElapsed`) minus what you actually spent — is spread
/// evenly across the weeks that remain (this week included). So overspending
/// earlier lowers this week's budget and every week after it; a surplus raises
/// them. When spending matches the baseline exactly, it returns B unchanged.
double adaptiveWeeklyBudget({
  required double recommended,
  required double spentBeforeThisWeek,
  required DateTime now,
  required DateTime weekStart,
}) {
  final monthStart = DateTime(now.year, now.month, 1);
  final monthEnd = DateTime(now.year, now.month + 1, 1);
  final weeksElapsed = _saturdaysInRange(monthStart, weekStart);
  // The current week plus every later week start still inside the month.
  final weeksLeft = 1 +
      _saturdaysInRange(
          DateTime(weekStart.year, weekStart.month, weekStart.day + 1),
          monthEnd);
  final carry = recommended * weeksElapsed - spentBeforeThisWeek;
  final adaptive = recommended + carry / weeksLeft;
  return adaptive < 0 ? 0 : adaptive;
}
