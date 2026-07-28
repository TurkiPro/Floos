// Pure, testable math for savings goals. The recommended monthly deposit is
// always derived from (target − saved) / months-remaining, never stored — so
// when a month is skipped or an off-schedule transfer happens, the next
// suggestion recomputes itself automatically (same ledger philosophy as the
// rest of the app).

import '../data/database.dart';
import 'recurrence_math.dart';

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

/// The date the goal is projected to be reached at the user's *actual* recent
/// saving pace — their average internal deposit rate since the first internal
/// deposit. External (imported) deposits count toward the balance but not the
/// pace, since a one-off import isn't an ongoing habit.
///
/// Null when there's nothing to project: the goal is already met, there's no
/// positive internal saving pace yet, or the estimate is absurdly far off (a
/// near-zero pace). A gentle "at this rate…" hint, never a promise.
DateTime? goalEta({
  required List<SavingsContribution> contributions,
  required double target,
  required DateTime now,
}) {
  var total = 0.0;
  var internal = 0.0;
  DateTime? firstInternal;
  for (final c in contributions) {
    total += c.amount;
    if (c.external) continue;
    internal += c.amount;
    final d = dateOnly(c.date);
    if (firstInternal == null || d.isBefore(firstInternal)) firstInternal = d;
  }

  final remaining = target - total;
  if (remaining <= 0) return null; // already reached
  if (firstInternal == null || internal <= 0) return null; // no real pace

  final spanDays = dateOnly(now).difference(firstInternal).inDays;
  final days = spanDays < 1 ? 1 : spanDays;
  final dailyPace = internal / days;
  if (dailyPace <= 0) return null;

  final etaDays = (remaining / dailyPace).ceil();
  if (etaDays > 366 * 60) return null; // > ~60 years out: not useful
  return dateOnly(now).add(Duration(days: etaDays));
}
