import '../data/database.dart';
import '../data/enums.dart';
import 'recurrence_math.dart';

/// What recurring charges will really cost over the next twelve months.
///
/// Counted from actual occurrences rather than "amount × 12", so an end date,
/// an every-two-months interval, a yearly charge due in three months, a rule
/// that starts next month, and a charge on the 31st all come out right — with
/// the engine's own date stepping ([occurrencesBetween]), not a second copy
/// of it.
///
/// The window is [today, today + 12 months). An occurrence already booked by
/// the engine ([RecurrenceRule.lastMaterialized]) is behind you even if it
/// fell today, so it is not counted again.
double costNext12Months(RecurrenceRule rule, DateTime now) {
  if (rule.type != TxnType.expense || !rule.active) return 0;
  return occurrencesInNext12Months(rule, now).length * rule.amount;
}

/// The charge dates [costNext12Months] counts, soonest first.
List<DateTime> occurrencesInNext12Months(RecurrenceRule rule, DateTime now) {
  final today = dateOnly(now);
  final windowEnd = addMonths(today, 12); // exclusive
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final booked = rule.lastMaterialized == null
      ? null
      : dateOnly(rule.lastMaterialized!);
  final after =
      booked != null && booked.isAfter(yesterday) ? booked : yesterday;

  final dates = occurrencesBetween(
    startDate: rule.startDate,
    frequency: rule.frequency,
    interval: rule.interval,
    endDate: rule.endDate,
    lastMaterialized: after,
    until: DateTime(windowEnd.year, windowEnd.month, windowEnd.day - 1),
  );

  // A one-shot override moves the next charge; it never adds one.
  final scheduled = rule.nextOverrideScheduled;
  final moved = rule.nextOverrideDate;
  if (scheduled != null && moved != null) {
    final s = dateOnly(scheduled);
    final m = dateOnly(moved);
    if (dates.remove(s) && !m.isBefore(today) && m.isBefore(windowEnd)) {
      dates.add(m);
      dates.sort();
    }
  }
  return dates;
}

/// The sum of [costNext12Months] over every active expense rule in [rules].
double totalNext12Months(List<RecurrenceRule> rules, DateTime now) =>
    rules.fold(0, (sum, r) => sum + costNext12Months(r, now));
