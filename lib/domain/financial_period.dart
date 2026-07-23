import '../data/database.dart';
import '../data/enums.dart';
import 'recurrence_math.dart';

/// The current financial period — salary-day to salary-day — anchored on the
/// largest active recurring income. The home dashboard's "this month" figures
/// use this instead of the calendar month, so the salary you were just paid
/// counts toward the period you're actually living in (and an obligation dated
/// late last month falls inside it). Falls back to the calendar month when
/// there is no recurring income yet, or it hasn't started.
class FinancialPeriod {
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  const FinancialPeriod(this.start, this.end);

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
}

FinancialPeriod financialPeriod(
    List<RecurrenceRule> incomeRules, DateTime now) {
  final today = dateOnly(now);
  final calendar = FinancialPeriod(
    DateTime(now.year, now.month, 1),
    DateTime(now.year, now.month + 1, 1),
  );

  final salary = _largestActiveIncome(incomeRules);
  if (salary == null) return calendar;

  final scheduledStart = _latestOnOrBefore(salary, today);

  // The ACTUAL last payday. An override can move the salary off its scheduled
  // slot (e.g. a 25th salary pulled in to the 23rd), and once the override is
  // consumed the schedule alone can't tell — so anchor the cycle to the day the
  // salary really landed.
  final paid =
      salary.lastPaidDate == null ? null : dateOnly(salary.lastPaidDate!);
  final lastPaid = (paid != null && !paid.isAfter(today)) ? paid : null;

  // Cycle start = the actual last payday when we have one (it's always the most
  // recent payment, and an early/late payday moves it off the scheduled slot);
  // otherwise the scheduled start (a rule that hasn't paid yet).
  final start = lastPaid ?? scheduledStart;
  if (start == null) return calendar; // the salary rule hasn't started yet

  // Next salary = the first scheduled occurrence AFTER the last materialized
  // slot, so an early payday's slot (already paid) isn't still counted as
  // upcoming. The marker holds that slot even when it's a day or two ahead of
  // the actual early payday.
  final marker = salary.lastMaterialized == null
      ? null
      : dateOnly(salary.lastMaterialized!);
  final anchor = (marker != null && marker.isAfter(today)) ? marker : today;
  final scheduledEnd = nextOccurrence(
        startDate: salary.startDate,
        frequency: salary.frequency,
        interval: salary.interval,
        endDate: salary.endDate,
        afterExclusive: anchor,
      ) ??
      // The salary rule has ended — cap a month out from the last payday.
      DateTime(start.year, start.month + 1, start.day);
  // A pending next-payday override (a future early/late payday not yet arrived)
  // moves the actual next payday, so the period ends on it.
  final override = salary.nextOverrideDate == null
      ? null
      : dateOnly(salary.nextOverrideDate!);
  final end =
      (override != null && override.isAfter(today)) ? override : scheduledEnd;
  return FinancialPeriod(start, end.isAfter(start) ? end : scheduledEnd);
}

/// The "salary": the largest active recurring income, which anchors the cycle.
RecurrenceRule? _largestActiveIncome(List<RecurrenceRule> incomeRules) {
  RecurrenceRule? salary;
  for (final r in incomeRules) {
    if (r.type != TxnType.income || !r.active) continue;
    if (salary == null || r.amount > salary.amount) salary = r;
  }
  return salary;
}

/// When the salary next lands — the same date the financial period ends —
/// honouring a pending next-payday override. Today counts (opening the app on
/// payday still reads as "today"). Null when there's no recurring income, so the
/// home countdown and every "days until salary" figure agree with the cycle.
DateTime? nextSalaryDate(List<RecurrenceRule> incomeRules, DateTime now) {
  final salary = _largestActiveIncome(incomeRules);
  if (salary == null) return null;
  final today = dateOnly(now);
  // A pending override (an upcoming early/late payday not yet arrived).
  if (salary.nextOverrideDate != null) {
    final o = dateOnly(salary.nextOverrideDate!);
    if (!o.isBefore(today)) return o;
  }
  // The salary already landed today (a normal payday, or one moved to today) —
  // read as "today" so the home shows "salary landed today", not a countdown.
  final paid =
      salary.lastPaidDate == null ? null : dateOnly(salary.lastPaidDate!);
  if (paid != null && paid == today) return today;
  // Otherwise, the next scheduled occurrence AFTER the last materialized slot,
  // so an already-paid early payday isn't counted as still upcoming.
  final marker = salary.lastMaterialized == null
      ? null
      : dateOnly(salary.lastMaterialized!);
  final anchor = (marker != null && !marker.isBefore(today))
      ? marker
      // Exclusive of yesterday => an occurrence dated today still counts.
      : DateTime(today.year, today.month, today.day - 1);
  return nextOccurrence(
    startDate: salary.startDate,
    frequency: salary.frequency,
    interval: salary.interval,
    endDate: salary.endDate,
    afterExclusive: anchor,
  );
}

/// The latest occurrence of [rule] on or before [cap], or null if the rule
/// starts after [cap].
DateTime? _latestOnOrBefore(RecurrenceRule rule, DateTime cap) {
  final base = dateOnly(rule.startDate);
  if (base.isAfter(cap)) return null;
  final end = rule.endDate == null ? null : dateOnly(rule.endDate!);
  DateTime? last;
  const safety = 100000;
  for (var n = 0; n < safety; n++) {
    final o = occurrence(
        freq: rule.frequency, interval: rule.interval, base: base, n: n);
    if (o.isAfter(cap)) break;
    if (end != null && o.isAfter(end)) break;
    last = o;
  }
  return last;
}
