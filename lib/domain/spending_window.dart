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
