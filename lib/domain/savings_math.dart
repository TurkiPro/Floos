// Pure, testable math for savings goals. The recommended monthly deposit is
// always derived from (target − saved) / months-remaining, never stored — so
// when a month is skipped or an off-schedule transfer happens, the next
// suggestion recomputes itself automatically (same ledger philosophy as the
// rest of the app).

/// Number of monthly deposits left until [deadline], counting from [now].
/// Never below 1 (a past/current-month deadline means "deposit the rest now").
int monthsUntilDeadline(DateTime now, DateTime deadline) {
  final months = (deadline.year - now.year) * 12 + (deadline.month - now.month);
  return months < 1 ? 1 : months;
}

/// The deposit that, repeated every month until [deadline], reaches [target]
/// from the current [saved] amount. Null when the goal has no deadline (no
/// schedule to spread over); 0 once the goal is already met.
double? suggestedMonthlyDeposit({
  required double target,
  required double saved,
  required DateTime? deadline,
  required DateTime now,
}) {
  if (deadline == null) return null;
  final remaining = target - saved;
  if (remaining <= 0) return 0;
  return remaining / monthsUntilDeadline(now, deadline);
}
